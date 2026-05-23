import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'app_env.dart';

class VpsUploadedMedia {
  const VpsUploadedMedia({
    required this.fileId,
    required this.url,
    required this.mimeType,
    this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.kind,
  });

  final String fileId;
  final String url;
  final String mimeType;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? kind;

  factory VpsUploadedMedia.fromJson(Map<String, dynamic> json) {
    return VpsUploadedMedia(
      fileId: (json['fileId'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      mimeType: (json['mimeType'] as String?) ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      kind: json['kind'] as String?,
    );
  }
}

class VpsMediaService {
  VpsMediaService._();

  static const String _fallbackBaseUrl = 'http://159.89.98.134:8080';
  static const String _fallbackPublicUrl = 'http://159.89.98.134';

  static String get _configuredBaseUrl {
    final raw =
        AppEnv.get('VPS_MEDIA_BASE_URL') ??
        AppEnv.get('VPS_BASE_URL') ??
        _fallbackBaseUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const <String, String>{};
    final token = await user.getIdToken();
    return <String, String>{
      'Authorization': 'Bearer $token',
      'X-User-Id': user.uid,
    };
  }

  static Future<VpsUploadedMedia> uploadFile({
    required File file,
    required String category,
    String? conversationId,
    int? durationMs,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('$_configuredBaseUrl/api/media/upload');
    debugPrint('VPS upload start: category=$category uri=$uri');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Utilisateur non connecté');
    final token = await user.getIdToken();

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['X-User-Id'] = user.uid;
    request.fields['category'] = category;
    if (conversationId != null && conversationId.trim().isNotEmpty) {
      request.fields['conversationId'] = conversationId.trim();
    }
    if (durationMs != null) {
      request.fields['durationMs'] = durationMs.toString();
    }

    final mimeType = _mimeTypeFor(file.path, category: category);
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'upload.bin';
    final fileBytes = await file.readAsBytes();

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      ),
    );

    onProgress?.call(0.1); // started

    final streamedResponse = await request
        .send()
        .timeout(const Duration(seconds: 120));

    onProgress?.call(0.8); // sent

    final responseBody = await streamedResponse.stream
        .bytesToString()
        .timeout(const Duration(seconds: 60));

    onProgress?.call(1.0); // done

    if (streamedResponse.statusCode < 200 ||
        streamedResponse.statusCode >= 300) {
      debugPrint(
        'VPS upload failed: status=${streamedResponse.statusCode} body=$responseBody uri=$uri',
      );
      throw HttpException(
        'VPS upload failed (${streamedResponse.statusCode})',
        uri: uri,
      );
    }

    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
    final media = Map<String, dynamic>.from(
      decoded['media'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
    final normalized = VpsUploadedMedia.fromJson(<String, dynamic>{
      ...media,
      'url': normalizeMediaUrlSync(media['url'] as String?),
    });
    debugPrint(
      'VPS upload success: fileId=${normalized.fileId} url=${normalized.url}',
    );
    return normalized;
  }

  static Future<void> deleteFiles(List<String> fileIds) async {
    final cleaned = fileIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) return;

    final uri = Uri.parse('$_configuredBaseUrl/api/media/delete-many');
    final client = HttpClient();
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    final authHeaders = await _authHeaders();
    authHeaders.forEach(request.headers.set);
    request.write(jsonEncode(<String, dynamic>{'fileIds': cleaned}));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'VPS delete failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
  }

  static String normalizeMediaUrlSync(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return '';

    final parsed = Uri.tryParse(value);
    final fallback = Uri.tryParse(_fallbackPublicUrl);
    if (parsed == null || fallback == null || !parsed.hasAuthority) {
      return value;
    }

    final configured = Uri.tryParse(_configuredBaseUrl);
    final publicHost = configured?.replace(
      path: parsed.path,
      query: parsed.hasQuery ? parsed.query : null,
    );
    return (publicHost ?? fallback.replace(path: parsed.path)).toString();
  }

  static String? resolveProfileImageUrl(Map<String, dynamic> data) {
    const candidateKeys = <String>[
      'photoUrl',
      'photoURL',
      'profileImageUrl',
      'profileImage',
      'avatarUrl',
      'avatar',
      'imageUrl',
      'image',
    ];
    for (final key in candidateKeys) {
      final value = (data[key] as String?)?.trim();
      if (value != null && value.isNotEmpty) {
        return normalizeMediaUrlSync(value);
      }
    }
    return null;
  }

  static String _mimeTypeFor(String path, {required String category}) {
    final extension = path.split('.').last.toLowerCase();
    if (category.contains('audio')) {
      switch (extension) {
        case 'm4a':
        case 'mp4':
          return 'audio/mp4';
        case 'aac':
          return 'audio/aac';
        case 'wav':
          return 'audio/wav';
        case 'mp3':
          return 'audio/mpeg';
        default:
          return 'audio/mp4';
      }
    }
    if (category.contains('video')) {
      switch (extension) {
        case 'mov':
          return 'video/quicktime';
        case 'webm':
          return 'video/webm';
        default:
          return 'video/mp4';
      }
    }
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
