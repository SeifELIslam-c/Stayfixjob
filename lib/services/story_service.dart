import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'vps_media_service.dart';

class WorkerStory {
  const WorkerStory({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerPhotoUrl,
    required this.mediaUrl,
    required this.mediaMimeType,
    required this.fileId,
    required this.caption,
    required this.kind,
    required this.isActive,
    required this.viewCount,
    required this.viewedBy,
    required this.visibility,
    required this.visibilityKey,
    required this.overlayText,
    required this.overlayTextX,
    required this.overlayTextY,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String ownerUid;
  final String ownerName;
  final String ownerPhotoUrl;
  final String mediaUrl;
  final String mediaMimeType;
  final String fileId;
  final String caption;
  final String kind;
  final bool isActive;
  final int viewCount;
  final List<String> viewedBy;
  final String visibility;
  final String visibilityKey;
  final String overlayText;
  final double overlayTextX;
  final double overlayTextY;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isVideo =>
      kind == 'story-video' || mediaMimeType.startsWith('video/');

  factory WorkerStory.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return WorkerStory(
      id: doc.id,
      ownerUid: data['ownerUid'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? 'Intervenant',
      ownerPhotoUrl: VpsMediaService.normalizeMediaUrlSync(
        data['ownerPhotoUrl'] as String?,
      ),
      mediaUrl: VpsMediaService.normalizeMediaUrlSync(
        data['mediaUrl'] as String?,
      ),
      mediaMimeType: data['mediaMimeType'] as String? ?? '',
      fileId: data['fileId'] as String? ?? '',
      caption: data['caption'] as String? ?? '',
      kind: data['kind'] as String? ?? 'story-image',
      isActive: data['isActive'] != false,
      viewCount: (data['viewCount'] as num?)?.toInt() ?? 0,
      viewedBy: ((data['viewedBy'] as List?) ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      visibility: data['visibility'] as String? ?? '',
      visibilityKey: data['visibilityKey'] as String? ?? '',
      overlayText: data['overlayText'] as String? ?? '',
      overlayTextX: (data['overlayTextX'] as num?)?.toDouble() ?? 0.5,
      overlayTextY: (data['overlayTextY'] as num?)?.toDouble() ?? 0.4,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      createdAt: _dateTimeFrom(data['createdAt']),
      expiresAt: _dateTimeFrom(data['expiresAt']),
    );
  }

  static DateTime? _dateTimeFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class StoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<_StoryLocationSnapshot?> _capturePublishLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      return _StoryLocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (error) {
      debugPrint('Story location capture skipped: $error');
      return null;
    }
  }

  Stream<List<WorkerStory>> watchOwnActiveStories() {
    final uid = _uid;
    if (uid == null) return const Stream<List<WorkerStory>>.empty();
    return _firestore
        .collection('stories')
        .where('ownerUid', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final stories = snapshot.docs
              .map(WorkerStory.fromDocument)
              .where(
                (story) =>
                    story.expiresAt == null || story.expiresAt!.isAfter(now),
              )
              .toList();
          stories.sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return stories;
        });
  }

  Future<String> publishStory({
    required String workerName,
    required String workerDepartment,
    required String workerSpecialty,
    required String? workerPhotoUrl,
    required bool isAvailable,
    required File mediaFile,
    required String mediaType,
    required String caption,
    required String visibility,
    String visibilityKey = '',
    void Function(double progress)? onProgress,
    VpsUploadedMedia? uploadedMedia,
    String overlayText = '',
    double overlayTextX = 0.5,
    double overlayTextY = 0.4,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utilisateur non connecté');

    final category = mediaType == 'video' ? 'story-video' : 'story-image';
    final locationFuture = _capturePublishLocation();
    debugPrint(
      'Story publish start: uid=$uid category=$category mediaType=$mediaType visibility=$visibility',
    );
    final uploaded =
        uploadedMedia ??
        await VpsMediaService.uploadFile(
          file: mediaFile,
          category: category,
          folder: 'stories/$uid',
          onProgress: onProgress,
        );

    if (uploaded.url.trim().isEmpty) {
      throw Exception(
        'L\'URL du média est vide après l\'envoi. Vérifiez la connexion au serveur.',
      );
    }
    final location = await locationFuture;

    final storyRef = _firestore.collection('stories').doc();
    final expiresAt = DateTime.now().add(const Duration(hours: 24));

    await storyRef.set({
      'storyId': storyRef.id,
      'ownerUid': uid,
      'ownerName': workerName.trim(),
      'ownerDepartment': workerDepartment.trim(),
      'ownerSpecialty': workerSpecialty.trim(),
      'ownerPhotoUrl': workerPhotoUrl ?? '',
      'mediaUrl': uploaded.url,
      'mediaMimeType': uploaded.mimeType,
      'fileId': uploaded.fileId,
      'caption': caption.trim(),
      'visibility': visibility.trim(),
      'visibilityKey': visibilityKey.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'viewedBy': <String>[],
      'viewCount': 0,
      'kind': category,
      'isActive': true,
      'isAvailableSnapshot': isAvailable,
      'overlayText': overlayText,
      'overlayTextX': overlayTextX,
      'overlayTextY': overlayTextY,
      if (location != null) 'latitude': location.latitude,
      if (location != null) 'longitude': location.longitude,
      if (location != null)
        'location': <String, double>{
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
    });

    debugPrint('Story publish success: storyId=${storyRef.id}');
    return storyRef.id;
  }

  Future<void> recordStoryView({
    required String storyId,
    required String ownerUid,
  }) async {
    final viewerUid = _uid;
    if (viewerUid == null || viewerUid == ownerUid) return;

    final storyRef = _firestore.collection('stories').doc(storyId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(storyRef);
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return;
      final viewedBy = ((data['viewedBy'] as List?) ?? const <dynamic>[])
          .map((item) => item.toString())
          .toSet();
      if (viewedBy.contains(viewerUid)) return;
      transaction.set(storyRef, {
        'viewedBy': FieldValue.arrayUnion([viewerUid]),
        'viewCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    });
  }

  Future<void> deleteStory({
    required String storyId,
    required String fileId,
  }) async {
    await _firestore.collection('stories').doc(storyId).delete();
    if (fileId.isNotEmpty) {
      try {
        await VpsMediaService.deleteFiles([fileId]);
      } catch (error) {
        debugPrint('Story VPS delete error: $error');
      }
    }
  }

  Future<void> cleanupExpiredStories() async {
    try {
      final now = Timestamp.now();
      final expired = await _firestore
          .collection('stories')
          .where('expiresAt', isLessThanOrEqualTo: now)
          .get();
      if (expired.docs.isEmpty) return;

      final fileIds = <String>[];
      final batch = _firestore.batch();
      for (final doc in expired.docs) {
        final data = doc.data();
        final fileId = (data['fileId'] as String?)?.trim() ?? '';
        if (fileId.isNotEmpty) fileIds.add(fileId);
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (fileIds.isNotEmpty) {
        try {
          await VpsMediaService.deleteFiles(fileIds);
        } catch (error) {
          debugPrint('Story VPS cleanup error: $error');
        }
      }
    } catch (error) {
      debugPrint('Cleanup expired stories error: $error');
    }
  }
}

class _StoryLocationSnapshot {
  const _StoryLocationSnapshot({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}
