import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotel_lux_profile/screens/messages_screen.dart';
import 'package:hotel_lux_profile/services/messages_repository.dart';
import 'package:hotel_lux_profile/services/vps_media_service.dart';
import 'package:http/http.dart' as http;
import 'package:hotel_lux_profile/widgets/address_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _kThreadBg = Color(0xFFF7FAFF);
const _kThreadBorder = Color(0x331D4ED8);
const _kThreadSurface = Color(0xF2FFFFFF);
const _kThreadPeerBubble = Color(0xFFF0F6FF);
const _kChatBackgroundAsset =
    'lib/assets/stayfixjob_chat_background_dark_doodle.png';
const _kAccent = kMessagesBlue;

const Map<String, IconData> _kReactionIcons = {
  'thumbs_up': LucideIcons.thumbsUp,
  'heart': LucideIcons.heart,
  'check': LucideIcons.check,
  'clap': LucideIcons.partyPopper,
  'fire': LucideIcons.flame,
  'pin': LucideIcons.pin,
};

const Map<String, Color> _kReactionColors = {
  'thumbs_up': Color(0xFF4F8CFF),
  'heart': Color(0xFFD6A85A),
  'check': Color(0xFF4DD4D2),
  'clap': Color(0xFF8B96A9),
  'fire': Color(0xFFFF9A54),
  'pin': Color(0xFFAAB3C2),
};

Future<void> _clearConversationHistoryById(String conversationId) async {
  final messagesRef = FirebaseFirestore.instance
      .collection('conversations')
      .doc(conversationId)
      .collection('messages');
  final messagesSnapshot = await messagesRef.get();
  final allFileIds = <String>[];
  final batch = FirebaseFirestore.instance.batch();
  for (final doc in messagesSnapshot.docs) {
    final fileIds = ((doc.data()['fileIds'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    allFileIds.addAll(fileIds);
    batch.delete(doc.reference);
  }
  await batch.commit();
  if (allFileIds.isNotEmpty) {
    await VpsMediaService.deleteFiles(allFileIds);
  }
  await FirebaseFirestore.instance
      .collection('conversations')
      .doc(conversationId)
      .set({
        'lastMessage': '',
        'systemBannerText': 'History was cleared',
        'systemBannerAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

class WorkerChatThreadScreen extends StatefulWidget {
  const WorkerChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.avatarBase64,
    required this.avatarUrl,
    required this.isAvailable,
    this.initialBannerText,
  });

  final String conversationId;
  final String title;
  final String subtitle;
  final String? avatarBase64;
  final String? avatarUrl;
  final bool isAvailable;
  final String? initialBannerText;

  @override
  State<WorkerChatThreadScreen> createState() => _WorkerChatThreadScreenState();
}

class _WorkerChatThreadScreenState extends State<WorkerChatThreadScreen> {
  final MessagesRepository _messagesRepository = MessagesRepository();
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  // Cached streams — must not be recreated on setState or the StreamBuilders
  // cancel their subscriptions and briefly show an empty state.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _conversationStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;

  bool _isSending = false;
  bool _uploadingMedia = false;
  bool _isRecording = false;
  DateTime? _recordingStartedAt;
  String? _recordingPath;
  Timer? _recordingTicker;
  Duration _recordingElapsed = Duration.zero;
  bool _isMarkingSeen = false;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<int> _recordingWaveform = [];
  Timer? _typingTimer;
  bool _showRecordComposer = false;
  bool _isRecordLocked = false;
  bool _isRecordPaused = false;
  double _holdDx = 0;
  double _holdDy = 0;
  bool _recordCanceledByGesture = false;
  String? _lastIncomingMessageId;
  String? _ephemeralBannerText;
  Timer? _ephemeralBannerTimer;

  // Pagination
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _olderMessages = [];
  bool _loadingMore = false;
  bool _hasMoreMessages = true;
  DocumentSnapshot<Map<String, dynamic>>? _oldestStreamDoc;
  final ScrollController _scrollController = ScrollController();

  // Message selection
  final Set<String> _selectedMessageIds = {};
  bool get _isSelectMode => _selectedMessageIds.isNotEmpty;

  // Camera / video
  CameraController? _cameraController;
  bool _isRecordingVideo = false;
  Timer? _recordingVideoTimer;
  List<CameraDescription> _cameras = [];

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _typingTimer?.cancel();
    _amplitudeSub?.cancel();
    _ephemeralBannerTimer?.cancel();
    _recordingVideoTimer?.cancel();
    _scrollController.dispose();
    _cameraController?.dispose();
    _controller.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _conversationStream = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .snapshots();
    _messagesStream = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(50)
        .snapshots();
    if (widget.initialBannerText?.trim().isNotEmpty == true) {
      _showEphemeralBanner(widget.initialBannerText!.trim());
    }
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 200 &&
          !_loadingMore &&
          _hasMoreMessages) {
        _loadMoreMessages();
      }
    });
    unawaited(_initCameras());
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
    } catch (_) {}
  }

  Future<void> _loadMoreMessages() async {
    if (_loadingMore || !_hasMoreMessages || _oldestStreamDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages')
          .orderBy('createdAt')
          .endBeforeDocument(_oldestStreamDoc!)
          .limitToLast(30)
          .get();
      if (snap.docs.isEmpty) {
        setState(() => _hasMoreMessages = false);
      } else {
        final existingIds = _olderMessages.map((d) => d.id).toSet();
        final newDocs =
            snap.docs.where((d) => !existingIds.contains(d.id)).toList();
        setState(() {
          _olderMessages.insertAll(0, newDocs);
          _oldestStreamDoc = snap.docs.first;
        });
      }
    } catch (_) {
    } finally {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameras.isEmpty) return;
    final ctrl = CameraController(
      _cameras.first,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    try {
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _cameraController = ctrl;
        _isRecordingVideo = true;
      });
      await ctrl.startVideoRecording();
      _recordingVideoTimer =
          Timer(const Duration(seconds: 15), _stopVideoRecording);
    } catch (e) {
      await ctrl.dispose();
    }
  }

  Future<void> _stopVideoRecording() async {
    _recordingVideoTimer?.cancel();
    final ctrl = _cameraController;
    if (ctrl == null || !_isRecordingVideo) return;
    setState(() {
      _isRecordingVideo = false;
      _cameraController = null;
    });
    try {
      final xfile = await ctrl.stopVideoRecording();
      await ctrl.dispose();
      final file = File(xfile.path);
      int durationMs = 0;
      try {
        final vpc = VideoPlayerController.file(file);
        await vpc.initialize();
        durationMs = vpc.value.duration.inMilliseconds;
        await vpc.dispose();
      } catch (_) {}
      setState(() => _uploadingMedia = true);
      try {
        final uploaded = await VpsMediaService.uploadFile(
          file: file,
          category: 'chat-video',
          conversationId: widget.conversationId,
        );
        await _sendMessage(
          videoUrl: uploaded.url,
          videoMimeType: uploaded.mimeType,
          videoFileId: uploaded.fileId,
          videoDurationMs: durationMs,
          lastMessage: '🎥 Vidéo',
        );
      } finally {
        setState(() => _uploadingMedia = false);
      }
    } catch (_) {
      await ctrl.dispose();
    }
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedMessageIds);
    setState(() => _selectedMessageIds.clear());
    try {
      // Fetch all docs in parallel
      final futures = ids.map((id) => _messagesRef.doc(id).get());
      final docs = await Future.wait(futures);
      // Batch delete from Firestore
      final batch = FirebaseFirestore.instance.batch();
      final allFileIds = <String>[];
      for (final doc in docs) {
        if (doc.exists) {
          batch.delete(doc.reference);
          final fileIds = (doc.data()?['fileIds'] as List?)?.cast<String>() ?? [];
          allFileIds.addAll(fileIds);
        }
      }
      await batch.commit();
      // Delete VPS files after Firestore batch succeeds
      if (allFileIds.isNotEmpty) {
        VpsMediaService.deleteFiles(allFileIds).catchError((_) {});
      }
    } catch (_) {}
  }

  DocumentReference<Map<String, dynamic>> get _conversationRef =>
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId);

  void _showEphemeralBanner(String text) {
    _ephemeralBannerTimer?.cancel();
    setState(() => _ephemeralBannerText = text);
    _ephemeralBannerTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _ephemeralBannerText = null);
    });
  }

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _conversationRef.collection('messages');

  Future<void> _markIncomingMessagesSeen(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
  ) async {
    if (_isMarkingSeen) return;

    final pending = docs.where((doc) {
      final data = doc.data();
      if (data['senderId'] == uid) return false;
      final seenBy = (data['seenBy'] as List?)?.cast<String>() ?? const [];
      return !seenBy.contains(uid);
    }).toList();

    if (pending.isEmpty) return;

    _isMarkingSeen = true;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in pending) {
        batch.set(doc.reference, {
          'deliveredTo': FieldValue.arrayUnion([uid]),
          'seenBy': FieldValue.arrayUnion([uid]),
          'seenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {
    } finally {
      _isMarkingSeen = false;
    }
  }

  Future<void> _deleteMessage(
    String messageId, {
    required List<String> fileIds,
  }) async {
    try {
      await _messagesRef.doc(messageId).delete();
      if (fileIds.isNotEmpty) {
        await VpsMediaService.deleteFiles(fileIds);
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible de supprimer ce message pour le moment.');
    }
  }

  Future<void> _setTyping(bool isTyping) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _conversationRef.set({
        'typingBy': {user.uid: isTyping},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _handleComposerChanged() {
    setState(() {});
    final hasText = _controller.text.trim().isNotEmpty;
    unawaited(_setTyping(hasText));
    _typingTimer?.cancel();
    if (hasText) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        unawaited(_setTyping(false));
      });
    }
  }

  Future<void> _showChatOptionsSheet() async {
    final snapshot = await _conversationRef.get();
    final data = snapshot.data() ?? const <String, dynamic>{};
    final mutedBy = ((data['mutedBy'] as List?) ?? const []).map((e) => '$e');
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    bool notificationsMuted = mutedBy.contains(uid);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ChatOptionTile(
                      icon: LucideIcons.bell,
                      title: 'Notifications',
                      trailing: Switch(
                        value: !notificationsMuted,
                        onChanged: (enabled) async {
                          notificationsMuted = !enabled;
                          setModalState(() {});
                          final op = notificationsMuted
                              ? FieldValue.arrayUnion([uid])
                              : FieldValue.arrayRemove([uid]);
                          await _conversationRef.set({
                            'mutedBy': op,
                          }, SetOptions(merge: true));
                        },
                      ),
                    ),
                    _ChatOptionTile(
                      icon: LucideIcons.info,
                      title: 'Contact info',
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.of(this.context).push(
                          MaterialPageRoute(
                            builder: (_) => _ChatContactInfoScreen(
                              conversationId: widget.conversationId,
                              title: widget.title,
                              subtitle: widget.subtitle,
                              avatarBase64: widget.avatarBase64,
                              avatarUrl: widget.avatarUrl,
                            ),
                          ),
                        );
                      },
                    ),
                    _ChatOptionTile(
                      icon: LucideIcons.trash2,
                      title: 'Clear chat',
                      destructive: true,
                      onTap: () async {
                        Navigator.pop(context);
                        await _clearChatHistory();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _clearChatHistory() async {
    try {
      await _clearConversationHistoryById(widget.conversationId);
      _showEphemeralBanner('History was cleared');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible de vider cette conversation pour le moment.');
    }
  }

  Future<void> _reactToMessage(String messageId, String reaction) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _messagesRef.doc(messageId).set({
        'reaction': reaction,
        'reactionByUserId': user.uid,
        'reactionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      SystemSound.play(SystemSoundType.click);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Impossible d ajouter cette reaction pour le moment.');
    }
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    _controller.clear();
    unawaited(_setTyping(false));
    // Fire and forget — Firestore offline persistence makes it appear instantly
    unawaited(_sendMessage(text: text, lastMessage: text));
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_isSending) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2200,
      );
      if (picked == null) return;

      setState(() => _uploadingMedia = true);
      try {
        final uploaded = await VpsMediaService.uploadFile(
          file: File(picked.path),
          category: 'chat-image',
          conversationId: widget.conversationId,
        );

        await _sendMessage(
          imageUrl: uploaded.url,
          imageMimeType: uploaded.mimeType,
          imageFileId: uploaded.fileId,
          imageName: picked.name,
          imageSizeBytes: uploaded.sizeBytes,
          imageWidth: uploaded.width,
          imageHeight: uploaded.height,
          lastMessage: 'Photo',
        );
      } finally {
        setState(() => _uploadingMedia = false);
      }
    } catch (_) {
      setState(() => _uploadingMedia = false);
      _showSnack('Impossible d envoyer cette photo pour le moment.');
    }
  }

  Future<void> _openAttachmentPicker() async {
    if (_isSending) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFDCE7FA)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                _AttachmentOption(
                  icon: LucideIcons.image,
                  title: 'Photo galerie',
                  subtitle: 'Envoyer une photo depuis la galerie',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndSendImage(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 10),
                _AttachmentOption(
                  icon: LucideIcons.mapPin,
                  title: 'Partager une adresse',
                  subtitle: 'Choisir une adresse via Google Maps',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openAddressPickerSheet();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddressPickerSheet() async {
    if (!mounted) return;

    final result = await showAddressPicker(
      context: context,
      presentation: AddressPickerPresentation.modal,
      title: 'Modifier adresse',
      confirmationText:
          'Confirmez cette position pour partager votre adresse dans ce chat.',
      confirmLabel: 'Partager adresse',
    );

    if (result == null || result.address.trim().isEmpty) return;
    await _sendMessage(
      address: result.address.trim(),
      latitude: result.latitude,
      longitude: result.longitude,
      lastMessage: 'Adresse partagee',
    );
  }

  Future<void> _toggleRecording() async {
    if (_isSending) return;
    if (_isRecording) {
      await _stopAndSendRecording();
    } else {
      await _startRecording(locked: true, fromHold: false);
    }
  }

  Future<void> _startRecording({
    required bool locked,
    required bool fromHold,
  }) async {
    try {
      if (!await _recorder.hasPermission()) {
        _showSnack('Microphone non autorise.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _recordingWaveform
        ..clear()
        ..addAll(List<int>.filled(36, 4));
      _amplitudeSub?.cancel();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 90))
          .listen((amp) {
            if (!mounted || !_isRecording) return;
            final db = amp.current;
            final normalized = (((db + 45).clamp(0, 45) / 45) * 30).round() + 6;
            setState(() {
              if (_recordingWaveform.length > 52) {
                _recordingWaveform.removeAt(0);
              }
              _recordingWaveform.add(normalized);
            });
          });

      SystemSound.play(SystemSoundType.click);
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _isRecordLocked = locked;
        _showRecordComposer = true;
        _isRecordPaused = false;
        _recordCanceledByGesture = false;
        _holdDx = 0;
        _holdDy = 0;
        _recordingStartedAt = DateTime.now();
        _recordingPath = path;
        _recordingElapsed = Duration.zero;
      });
      _recordingTicker?.cancel();
      _recordingTicker = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || _recordingStartedAt == null || _isRecordPaused) return;
        setState(() {
          _recordingElapsed = DateTime.now().difference(_recordingStartedAt!);
        });
      });
    } catch (_) {
      _showSnack('Impossible de demarrer l enregistrement.');
    }
  }

  Future<void> _pauseResumeRecording() async {
    if (!_isRecording) return;
    try {
      if (_isRecordPaused) {
        await _recorder.resume();
      } else {
        await _recorder.pause();
      }
      if (!mounted) return;
      setState(() {
        _isRecordPaused = !_isRecordPaused;
      });
    } catch (_) {}
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTicker?.cancel();
      _amplitudeSub?.cancel();
      await _recorder.stop();
    } catch (_) {}
    final path = _recordingPath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _showRecordComposer = false;
      _isRecordLocked = false;
      _isRecordPaused = false;
      _recordingStartedAt = null;
      _recordingPath = null;
      _recordingElapsed = Duration.zero;
      _recordingWaveform.clear();
      _holdDx = 0;
      _holdDy = 0;
    });
  }

  Future<void> _stopAndSendRecording() async {
    try {
      final path = await _recorder.stop();
      final resolvedPath = path ?? _recordingPath;
      _recordingTicker?.cancel();
      _amplitudeSub?.cancel();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _showRecordComposer = false;
        _isRecordLocked = false;
        _isRecordPaused = false;
        _recordingElapsed = Duration.zero;
      });

      if (resolvedPath == null || resolvedPath.isEmpty) return;

      final durationMs = _recordingStartedAt == null
          ? null
          : DateTime.now().difference(_recordingStartedAt!).inMilliseconds;
      _recordingStartedAt = null;
      _recordingPath = null;
      _holdDx = 0;
      _holdDy = 0;

      final uploaded = await VpsMediaService.uploadFile(
        file: File(resolvedPath),
        category: 'chat-audio',
        conversationId: widget.conversationId,
        durationMs: durationMs,
      );

      await _sendMessage(
        audioUrl: uploaded.url,
        audioMimeType: uploaded.mimeType,
        audioFileId: uploaded.fileId,
        audioDurationMs: uploaded.durationMs ?? durationMs,
        audioSizeBytes: uploaded.sizeBytes,
        audioWaveform: _recordingWaveform.isEmpty
            ? null
            : List<int>.from(_recordingWaveform),
        lastMessage: 'Message vocal',
      );

      try {
        await File(resolvedPath).delete();
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _showRecordComposer = false;
        _isRecordLocked = false;
        _isRecordPaused = false;
        _recordingStartedAt = null;
        _recordingPath = null;
        _recordingElapsed = Duration.zero;
        _recordingWaveform.clear();
        _holdDx = 0;
        _holdDy = 0;
      });
      _showSnack('Impossible d envoyer le vocal pour le moment.');
    }
  }

  Future<void> _sendMessage({
    String? text,
    String? imageUrl,
    String? imageMimeType,
    String? imageFileId,
    String? imageName,
    int? imageSizeBytes,
    int? imageWidth,
    int? imageHeight,
    String? audioUrl,
    String? audioMimeType,
    String? audioFileId,
    int? audioDurationMs,
    int? audioSizeBytes,
    List<int>? audioWaveform,
    String? videoUrl,
    String? videoMimeType,
    String? videoFileId,
    int? videoDurationMs,
    String? address,
    double? latitude,
    double? longitude,
    required String lastMessage,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final fileIds = <String>[
      if (imageFileId != null && imageFileId.isNotEmpty) imageFileId,
      if (audioFileId != null && audioFileId.isNotEmpty) audioFileId,
      if (videoFileId != null && videoFileId.isNotEmpty) videoFileId,
    ];

    try {
      await _messagesRepository.sendConversationMessage(
        conversationId: widget.conversationId,
        messageData: {
          'type': videoUrl != null
              ? 'video'
              : audioUrl != null
              ? 'audio'
              : imageUrl != null
              ? 'image'
              : address != null
              ? 'address'
              : 'text',
          'text': text ?? '',
          'imageUrl': imageUrl,
          'imageMimeType': imageMimeType,
          'imageFileId': imageFileId,
          'imageName': imageName,
          'imageSizeBytes': imageSizeBytes,
          'imageWidth': imageWidth,
          'imageHeight': imageHeight,
          'audioUrl': audioUrl,
          'audioMimeType': audioMimeType,
          'audioFileId': audioFileId,
          'audioDurationMs': audioDurationMs,
          'audioSizeBytes': audioSizeBytes,
          'audioWaveform': audioWaveform,
          'videoUrl': videoUrl,
          'videoMimeType': videoMimeType,
          'videoFileId': videoFileId,
          'videoDurationMs': videoDurationMs,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'fileIds': fileIds,
          'mediaStorage': fileIds.isEmpty ? null : 'vps',
          'sentAt': FieldValue.serverTimestamp(),
        },
        lastMessage: lastMessage,
      );
      SystemSound.play(SystemSoundType.click);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
    );
  }

  Widget _buildMessageBubble({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String uid,
  }) {
    final data = doc.data();
    final isMine = data['senderId'] == uid;
    final isSelected = _selectedMessageIds.contains(doc.id);
    final bubble = _MessageBubble(
      key: ValueKey(doc.id),
      senderName: widget.title,
      messageId: doc.id,
      conversationId: widget.conversationId,
      isMine: isMine,
      text: (data['text'] as String?)?.trim() ?? '',
      imageUrl: VpsMediaService.normalizeMediaUrlSync(
        (data['imageUrl'] as String?)?.trim(),
      ),
      imageBase64: (data['imageBase64'] as String?)?.trim(),
      audioUrl: VpsMediaService.normalizeMediaUrlSync(
        (data['audioUrl'] as String?)?.trim(),
      ),
      audioDurationMs: (data['audioDurationMs'] as num?)?.toInt(),
      audioWaveform:
          ((data['audioWaveform'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .toList(),
      videoUrl: VpsMediaService.normalizeMediaUrlSync(
        (data['videoUrl'] as String?)?.trim(),
      ),
      videoDurationMs: (data['videoDurationMs'] as num?)?.toInt(),
      address: (data['address'] as String?)?.trim(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      fileIds:
          ((data['fileIds'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
      deliveredTo:
          ((data['deliveredTo'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
      seenBy:
          ((data['seenBy'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
      reaction: (data['reaction'] as String?)?.trim(),
      reactionByUserId: (data['reactionByUserId'] as String?)?.trim(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      isSelected: isSelected,
      isSelectMode: _isSelectMode,
      onDelete: (fileIds) => _deleteMessage(doc.id, fileIds: fileIds),
      onReact: (reaction) => _reactToMessage(doc.id, reaction),
      onLongPress: () => setState(
        () => _selectedMessageIds.add(doc.id),
      ),
      onSelectToggle: () => setState(() {
        if (_selectedMessageIds.contains(doc.id)) {
          _selectedMessageIds.remove(doc.id);
        } else {
          _selectedMessageIds.add(doc.id);
        }
      }),
    );
    return bubble;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: _kThreadBg,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _conversationStream,
        builder: (context, conversationSnapshot) {
          final conversationData =
              conversationSnapshot.data?.data() ?? const <String, dynamic>{};
          final typingBy =
              (conversationData['typingBy'] as Map?)?.map(
                (k, v) => MapEntry('$k', v == true),
              ) ??
              const <String, bool>{};
          final isOtherTyping = typingBy.entries.any(
            (entry) => entry.key != user.uid && entry.value,
          );
          final systemBannerText =
              (conversationData['systemBannerText'] as String?)?.trim();
          final systemBannerAt =
              (conversationData['systemBannerAt'] as Timestamp?)?.toDate();
          final shouldShowStoredBanner =
              systemBannerText != null &&
              systemBannerText.isNotEmpty &&
              systemBannerAt != null &&
              DateTime.now().difference(systemBannerAt).inSeconds <= 12;

          final bannerVisible =
              _ephemeralBannerText != null || shouldShowStoredBanner;
          final topInset = MediaQuery.paddingOf(context).top;

          return Stack(
            children: [
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        _kChatBackgroundAsset,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        final streamDocs = snapshot.data?.docs ?? const [];
                        unawaited(
                          _markIncomingMessagesSeen(streamDocs, user.uid),
                        );
                        if (streamDocs.isNotEmpty) {
                          final latest = streamDocs.last;
                          final latestData = latest.data();
                          if (latestData['senderId'] != user.uid &&
                              _lastIncomingMessageId != latest.id) {
                            _lastIncomingMessageId = latest.id;
                            SystemSound.play(SystemSoundType.click);
                          }
                          // Pagination: track oldest doc in stream
                          if (_oldestStreamDoc == null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _oldestStreamDoc == null) {
                                setState(
                                  () => _oldestStreamDoc = streamDocs.first,
                                );
                              }
                            });
                          }
                        }

                        // Merge older paginated docs with live stream docs
                        final seenIds = <String>{};
                        final allDocs = <QueryDocumentSnapshot<
                          Map<String, dynamic>
                        >>[];
                        for (final d in [..._olderMessages, ...streamDocs]) {
                          if (seenIds.add(d.id)) allDocs.add(d);
                        }

                        if (allDocs.isEmpty && !_uploadingMedia) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 34,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 18,
                                    sigmaY: 18,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 20,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: _kThreadBorder),
                                    ),
                                    child: Text(
                                      'Commencez la conversation avec un message, une photo, une adresse ou un vocal.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        color: kMessagesText.withValues(
                                          alpha: 0.82,
                                        ),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        height: 1.55,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        // Item count: messages + optional uploading indicator
                        // + optional load-more spinner at top (last index in
                        // reversed list)
                        final uploadingExtra = _uploadingMedia ? 1 : 0;
                        final loadMoreExtra = _loadingMore ? 1 : 0;
                        final totalCount =
                            allDocs.length + uploadingExtra + loadMoreExtra;

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            bannerVisible ? 190 : 150,
                            16,
                            118,
                          ),
                          itemCount: totalCount,
                          itemBuilder: (context, index) {
                            // index 0 = bottom of list (most recent)
                            // Uploading indicator at index 0 (above composer)
                            if (_uploadingMedia && index == 0) {
                              return Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  height: 36,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Envoi...',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: kMessagesBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            // Adjust index for uploading offset
                            final adjustedIndex = index - uploadingExtra;

                            // Load-more spinner at the last index (top of list)
                            if (_loadingMore &&
                                adjustedIndex == allDocs.length) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    color: kMessagesBlue,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }

                            final doc =
                                allDocs[allDocs.length - 1 - adjustedIndex];
                            return _buildMessageBubble(doc: doc, uid: user.uid);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _isSelectMode
                    ? AppBar(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        leading: IconButton(
                          icon: const Icon(Icons.close, color: Colors.black),
                          onPressed: () =>
                              setState(() => _selectedMessageIds.clear()),
                        ),
                        title: Text(
                          '${_selectedMessageIds.length} sélectionné(s)',
                          style: const TextStyle(
                            color: kMessagesText,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFEF4444),
                            ),
                            onPressed: _deleteSelected,
                          ),
                        ],
                      )
                    : _ThreadHeader(
                        title: widget.title,
                        subtitle: isOtherTyping
                            ? 'En train d\'ecrire...'
                            : widget.subtitle,
                        avatarBase64: widget.avatarBase64,
                        avatarUrl: widget.avatarUrl,
                        isAvailable: widget.isAvailable,
                        onMenuTap: _showChatOptionsSheet,
                      ),
              ),
              Positioned(
                top: topInset + 72,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: true,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child:
                          (_ephemeralBannerText != null ||
                              shouldShowStoredBanner)
                          ? _SystemBanner(
                              key: ValueKey(
                                _ephemeralBannerText ?? systemBannerText ?? '',
                              ),
                              text: _ephemeralBannerText ?? systemBannerText!,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ThreadComposer(
                  controller: _controller,
                  isSending: _isSending,
                  isRecording: _isRecording,
                  isRecordLocked: _isRecordLocked,
                  isRecordPaused: _isRecordPaused,
                  showRecordComposer: _showRecordComposer,
                  recordingElapsed: _recordingElapsed,
                  recordingWaveform: _recordingWaveform,
                  holdDx: _holdDx,
                  holdDy: _holdDy,
                  onChanged: _handleComposerChanged,
                  onAttachTap: _openAttachmentPicker,
                  onCameraTap: () => _pickAndSendImage(ImageSource.camera),
                  onCameraLongPress: _startVideoRecording,
                  onCameraLongPressEnd: (_) => _stopVideoRecording(),
                  onSendTap: _sendText,
                  onMicTap: _toggleRecording,
                  onMicPressStart: () =>
                      _startRecording(locked: false, fromHold: true),
                  onMicPressMove: (dx, dy) async {
                    if (!_isRecording || _isRecordLocked) return;
                    setState(() {
                      _holdDx = dx;
                      _holdDy = dy;
                    });
                    if (dx < -110) {
                      _recordCanceledByGesture = true;
                      await _cancelRecording();
                    } else if (dy < -80) {
                      setState(() {
                        _isRecordLocked = true;
                        _holdDx = 0;
                        _holdDy = 0;
                      });
                    }
                  },
                  onMicPressEnd: () async {
                    if (!_isRecording) return;
                    if (_recordCanceledByGesture) {
                      _recordCanceledByGesture = false;
                      return;
                    }
                    if (!_isRecordLocked) {
                      await _stopAndSendRecording();
                    }
                  },
                  onRecordDelete: _cancelRecording,
                  onRecordPauseResume: _pauseResumeRecording,
                  onRecordSend: _stopAndSendRecording,
                ),
              ),
              // Camera video recording overlay
              if (_isRecordingVideo && _cameraController != null)
                Positioned.fill(
                  child: Stack(
                    children: [
                      CameraPreview(_cameraController!),
                      Container(color: Colors.black26),
                      Positioned(
                        bottom: 80,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(seconds: 15),
                              builder: (context2, v, child2) => SizedBox(
                                width: 80,
                                height: 80,
                                child: CircularProgressIndicator(
                                  value: v,
                                  color: const Color(0xFFFF3B30),
                                  strokeWidth: 6,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Relâchez pour envoyer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 50,
                        right: 20,
                        child: GestureDetector(
                          onTap: () async {
                            _recordingVideoTimer?.cancel();
                            final ctrl = _cameraController;
                            setState(() {
                              _isRecordingVideo = false;
                              _cameraController = null;
                            });
                            try {
                              await ctrl?.stopVideoRecording();
                            } catch (_) {}
                            await ctrl?.dispose();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({
    required this.title,
    required this.subtitle,
    required this.avatarBase64,
    required this.avatarUrl,
    required this.isAvailable,
    required this.onMenuTap,
  });

  final String title;
  final String subtitle;
  final String? avatarBase64;
  final String? avatarUrl;
  final bool isAvailable;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    Uint8List? photoBytes;
    if (avatarBase64 != null && avatarBase64!.isNotEmpty) {
      try {
        photoBytes = base64Decode(avatarBase64!);
      } catch (_) {}
    }

    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      padding: EdgeInsets.fromLTRB(12, topInset + 6, 12, 12),
      decoration: BoxDecoration(
        color: _kThreadSurface,
        border: const Border(bottom: BorderSide(color: _kThreadBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.arrowLeft, color: kMessagesText),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kAccent.withValues(alpha: 0.45)),
                  color: Colors.white,
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? Image.network(
                        avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            photoBytes != null
                            ? Image.memory(photoBytes, fit: BoxFit.cover)
                            : _HeaderInitial(title: title),
                      )
                    : photoBytes != null
                    ? Image.memory(photoBytes, fit: BoxFit.cover)
                    : _HeaderInitial(title: title),
              ),
              if (isAvailable)
                Positioned(
                  right: 0,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(color: _kThreadSurface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: kMessagesText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: kMessagesMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onMenuTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _kThreadBorder),
              ),
              child: const Icon(
                LucideIcons.moreVertical,
                color: kMessagesText,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemBanner extends StatelessWidget {
  const _SystemBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _kThreadBorder),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: kMessagesText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderInitial extends StatelessWidget {
  const _HeaderInitial({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          color: _kAccent,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _BubbleShell extends StatelessWidget {
  const _BubbleShell({
    required this.isMine,
    required this.color,
    required this.borderColor,
    required this.padding,
    required this.child,
  });

  final bool isMine;
  final Color color;
  final Color borderColor;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(isMine ? 22 : 8),
              bottomRight: Radius.circular(isMine ? 8 : 22),
            ),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
        Positioned(
          right: isMine ? 0 : null,
          left: isMine ? null : 0,
          bottom: 6,
          child: CustomPaint(
            size: const Size(14, 14),
            painter: _BubbleTailPainter(
              color: color,
              borderColor: borderColor,
              isMine: isMine,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({
    required this.color,
    required this.borderColor,
    required this.isMine,
  });

  final Color color;
  final Color borderColor;
  final bool isMine;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (isMine) {
      path
        ..moveTo(size.width, size.height)
        ..lineTo(2, size.height)
        ..quadraticBezierTo(size.width - 1, size.height - 1, size.width, 1)
        ..close();
    } else {
      path
        ..moveTo(0, 1)
        ..quadraticBezierTo(1, size.height - 1, size.width - 2, size.height)
        ..lineTo(0, size.height)
        ..close();
    }

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.isMine != isMine;
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.senderName,
    required this.messageId,
    required this.conversationId,
    required this.isMine,
    required this.text,
    required this.imageUrl,
    required this.imageBase64,
    required this.audioUrl,
    required this.audioDurationMs,
    required this.audioWaveform,
    required this.videoUrl,
    required this.videoDurationMs,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.fileIds,
    required this.deliveredTo,
    required this.seenBy,
    required this.reaction,
    required this.reactionByUserId,
    required this.createdAt,
    required this.isSelected,
    required this.isSelectMode,
    required this.onDelete,
    required this.onReact,
    required this.onLongPress,
    required this.onSelectToggle,
  });

  final String senderName;
  final String messageId;
  final String conversationId;
  final bool isMine;
  final String text;
  final String? imageUrl;
  final String? imageBase64;
  final String? audioUrl;
  final int? audioDurationMs;
  final List<int> audioWaveform;
  final String? videoUrl;
  final int? videoDurationMs;
  final String? address;
  final double? latitude;
  final double? longitude;
  final List<String> fileIds;
  final List<String> deliveredTo;
  final List<String> seenBy;
  final String? reaction;
  final String? reactionByUserId;
  final DateTime? createdAt;
  final bool isSelected;
  final bool isSelectMode;
  final Future<void> Function(List<String> fileIds) onDelete;
  final Future<void> Function(String reaction) onReact;
  final VoidCallback onLongPress;
  final VoidCallback onSelectToggle;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isPreparingAudio = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _cachedAudioPath;
  bool _showReactionPop = false;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
    _player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
    if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty) {
      unawaited(_warmAudioCache());
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<String?> _ensureLocalAudioPath() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return null;
    if (_cachedAudioPath != null && await File(_cachedAudioPath!).exists()) {
      return _cachedAudioPath;
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('audio download failed');
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/chat_audio_${widget.messageId}_${widget.createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}.m4a';
    await File(path).writeAsBytes(response.bodyBytes, flush: true);
    _cachedAudioPath = path;
    return path;
  }

  Future<void> _warmAudioCache() async {
    if (_cachedAudioPath != null || _isPreparingAudio) return;
    try {
      if (mounted) {
        setState(() => _isPreparingAudio = true);
      } else {
        _isPreparingAudio = true;
      }
      await _ensureLocalAudioPath();
    } catch (_) {
    } finally {
      if (!mounted) {
        _isPreparingAudio = false;
      } else {
        setState(() => _isPreparingAudio = false);
      }
    }
  }

  Future<void> _toggleAudio() async {
    final url = widget.audioUrl;
    if (url == null || url.isEmpty) return;
    if (_isPreparingAudio) return;

    if (_isPlaying) {
      await _player.stop();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
      return;
    }

    try {
      setState(() => _isPreparingAudio = true);
      final localPath = await _ensureLocalAudioPath();
      if (localPath == null) return;
      await _player.play(
        DeviceFileSource(localPath),
        mode: PlayerMode.mediaPlayer,
        volume: 1.0,
      );
      if (mounted) {
        setState(() {
          _isPlaying = true;
          _isPreparingAudio = false;
          _duration = widget.audioDurationMs != null
              ? Duration(milliseconds: widget.audioDurationMs!)
              : _duration;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isPreparingAudio = false);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de lire ce vocal pour le moment.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    }
  }

  Future<void> _seekAudio(double fraction) async {
    final totalMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : (widget.audioDurationMs ?? 0);
    if (totalMs <= 0) return;
    final targetMs = (totalMs * fraction.clamp(0.0, 1.0)).round();
    try {
      if (!_isPlaying && _duration == Duration.zero) {
        final url = widget.audioUrl;
        if (url == null || url.isEmpty) return;
        try {
          await _player.setSource(UrlSource(url));
        } catch (_) {
          final localPath = await _ensureLocalAudioPath();
          if (localPath == null) return;
          await _player.setSource(DeviceFileSource(localPath));
        }
      }
    } catch (_) {
      return;
    }
    await _player.seek(Duration(milliseconds: targetMs));
    if (!_isPlaying) {
      try {
        await _player.resume();
      } catch (_) {
        await _toggleAudio();
      }
    }
  }

  Future<void> _handleQuickReaction() async {
    setState(() => _showReactionPop = true);
    Future<void>.delayed(const Duration(milliseconds: 760), () {
      if (!mounted) return;
      setState(() => _showReactionPop = false);
    });
    await widget.onReact('heart');
  }

  Future<void> _showReactionTray(LongPressStartDetails details) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final origin = renderBox.localToGlobal(Offset.zero);
    final rect = origin & renderBox.size;
    final reaction = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Reactions',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _StayFixReactionOverlay(
          targetRect: rect,
          selectedReaction: widget.reaction,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (reaction != null && reaction.isNotEmpty) {
      await widget.onReact(reaction);
    }
  }

  static String _formatVideoDuration(int ms) {
    if (ms <= 0) return '0:00';
    final totalSeconds = (ms / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? imageBytes;
    if (widget.imageBase64 != null && widget.imageBase64!.isNotEmpty) {
      try {
        imageBytes = base64Decode(widget.imageBase64!);
      } catch (_) {}
    }

    final background = widget.isMine ? _kAccent : _kThreadPeerBubble;
    final foreground = widget.isMine ? Colors.white : kMessagesText;
    final hasText = widget.text.isNotEmpty;
    final hasAddress = widget.address != null && widget.address!.isNotEmpty;
    final hasAudio = widget.audioUrl != null && widget.audioUrl!.isNotEmpty;
    final hasVideo = widget.videoUrl != null && widget.videoUrl!.isNotEmpty;
    final hasImage =
        (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) ||
        imageBytes != null;
    final imageOnly = hasImage && !hasText && !hasAudio && !hasAddress;
    final videoOnly = hasVideo && !hasText && !hasAudio && !hasAddress;
    final bubbleColor = imageOnly ? Colors.transparent : background;
    final isSeenByOther = widget.seenBy.length > 1;
    final isDeliveredToOther = widget.deliveredTo.length > 1;

    final reaction = widget.reaction;

    Widget bubbleContent = Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onDoubleTap: widget.isSelectMode ? null : _handleQuickReaction,
        onLongPressStart: widget.isSelectMode
            ? null
            : (details) {
                widget.onLongPress();
                _showReactionTray(details);
              },
        onTap: widget.isSelectMode ? widget.onSelectToggle : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: IntrinsicWidth(
            child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
              minWidth: 0,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: reaction != null && reaction.isNotEmpty ? 10 : 0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: widget.isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      // Video message
                      if (hasVideo) ...[
                        GestureDetector(
                          onTap: widget.isSelectMode
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => _VideoPlayerPage(
                                        url: widget.videoUrl!,
                                      ),
                                    ),
                                  );
                                },
                          child: Container(
                            width: 200,
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    color: const Color(0xFF1A1A2E),
                                  ),
                                ),
                                const Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 48,
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Text(
                                    _formatVideoDuration(
                                      widget.videoDurationMs ?? 0,
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (videoOnly)
                          _MessageStatusOverlay(
                            isMine: widget.isMine,
                            createdAt: widget.createdAt,
                            isSeenByOther: isSeenByOther,
                            isDeliveredToOther: isDeliveredToOther,
                          ),
                      ],
                      if (hasImage && !hasVideo) ...[
                        _MessageImage(
                          imageUrl: widget.imageUrl,
                          imageBytes: imageBytes,
                          isMine: widget.isMine,
                          createdAt: widget.createdAt,
                          onOpen: () => _openImagePreview(imageBytes),
                        ),
                        if (hasText || hasAudio || hasAddress)
                          const SizedBox(height: 6),
                      ],
                      if (!hasVideo && (hasText || hasAudio || hasAddress))
                        _BubbleShell(
                          isMine: widget.isMine,
                          color: bubbleColor,
                          borderColor: widget.isMine
                              ? _kAccent.withValues(alpha: 0.60)
                              : Colors.white.withValues(alpha: 0.08),
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hasAddress)
                                _AddressCard(
                                  widget: widget,
                                  foreground: foreground,
                                ),
                              if (hasAddress &&
                                  (hasImage || hasText || hasAudio))
                                const SizedBox(height: 10),
                              if (hasAudio)
                                _AudioBubbleRow(
                                  isMine: widget.isMine,
                                  foreground: foreground,
                                  isPlaying: _isPlaying,
                                  isPreparing: _isPreparingAudio,
                                  durationMs: widget.audioDurationMs,
                                  waveform: widget.audioWaveform,
                                  progressMs: _position.inMilliseconds,
                                  activeDurationMs: _duration.inMilliseconds > 0
                                      ? _duration.inMilliseconds
                                      : widget.audioDurationMs,
                                  onTap: widget.isSelectMode ? null : _toggleAudio,
                                  onSeek: widget.isSelectMode ? null : _seekAudio,
                                ),
                              if (hasAudio && hasText)
                                const SizedBox(height: 8),
                              if (hasText)
                                Text(
                                  widget.text,
                                  style: GoogleFonts.inter(
                                    color: foreground,
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatTime(widget.createdAt),
                                      style: GoogleFonts.inter(
                                        color: foreground.withValues(
                                          alpha: 0.70,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (widget.isMine) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        isSeenByOther
                                            ? Icons.done_all_rounded
                                            : isDeliveredToOther
                                            ? Icons.done_all_rounded
                                            : Icons.done_rounded,
                                        size: 15,
                                        color: isSeenByOther
                                            ? const Color(0xFF8FD3FF)
                                            : foreground.withValues(
                                                alpha: 0.72,
                                              ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (imageOnly)
                        _MessageStatusOverlay(
                          isMine: widget.isMine,
                          createdAt: widget.createdAt,
                          isSeenByOther: isSeenByOther,
                          isDeliveredToOther: isDeliveredToOther,
                        ),
                    ],
                  ),
                ),
                if (reaction != null && reaction.isNotEmpty)
                  Positioned(
                    top: 0,
                    right: widget.isMine ? 12 : null,
                    left: widget.isMine ? null : 12,
                    child: StayFixReactionBadge(
                      reaction: reaction,
                      highlighted: _showReactionPop && reaction == 'heart',
                    ),
                  ),
                if (_showReactionPop)
                  Positioned(
                    top: 18,
                    right: widget.isMine ? -10 : null,
                    left: widget.isMine ? null : -10,
                    child: IgnorePointer(
                      child: AnimatedScale(
                        scale: _showReactionPop ? 1 : 0.6,
                        duration: const Duration(milliseconds: 180),
                        child: const _StayFixHeartBurst(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ),
        ),
      ),
    );

    // Selection overlay
    if (widget.isSelectMode) {
      return Stack(
        children: [
          if (widget.isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: kMessagesBlue.withValues(alpha: 0.08),
                  border: const Border(
                    left: BorderSide(color: kMessagesBlue, width: 3),
                  ),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!widget.isMine) ...[
                GestureDetector(
                  onTap: widget.onSelectToggle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      widget.isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: kMessagesBlue,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(child: bubbleContent),
              if (widget.isMine) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onSelectToggle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      widget.isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: kMessagesBlue,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return bubbleContent;
  }

  Future<void> _openImagePreview(Uint8List? imageBytes) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ImagePreviewScreen(
            senderName: widget.senderName,
            timeLabel: _formatTime(widget.createdAt),
            imageUrl: widget.imageUrl,
            imageBytes: imageBytes,
            onDelete: () => widget.onDelete(widget.fileIds),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime? value) {
    if (value == null) return '';
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.widget, required this.foreground});

  final _MessageBubble widget;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final card = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: widget.isMine
                ? Colors.black.withValues(alpha: 0.10)
                : _kAccent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            LucideIcons.mapPin,
            color: widget.isMine ? Colors.white : _kAccent,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adresse partagee',
                style: GoogleFonts.inter(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.address!,
                style: GoogleFonts.inter(
                  color: foreground.withValues(alpha: 0.86),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              if (widget.latitude != null && widget.longitude != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}',
                  style: GoogleFonts.inter(
                    color: foreground.withValues(alpha: 0.60),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(LucideIcons.externalLink, size: 12, color: kMessagesBlue),
                    const SizedBox(width: 4),
                    Text(
                      'Ouvrir dans Maps',
                      style: TextStyle(
                        color: kMessagesBlue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (widget.latitude != null && widget.longitude != null) {
      return GestureDetector(
        onTap: () async {
          final uri = Uri.parse(
            'https://maps.google.com/?q=${widget.latitude},${widget.longitude}',
          );
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: card,
      );
    }
    return card;
  }
}

class _AudioBubbleRow extends StatelessWidget {
  const _AudioBubbleRow({
    required this.isMine,
    required this.foreground,
    required this.isPlaying,
    required this.isPreparing,
    required this.durationMs,
    required this.waveform,
    required this.progressMs,
    required this.activeDurationMs,
    required this.onTap,
    required this.onSeek,
  });

  final bool isMine;
  final Color foreground;
  final bool isPlaying;
  final bool isPreparing;
  final int? durationMs;
  final List<int> waveform;
  final int progressMs;
  final int? activeDurationMs;
  final VoidCallback? onTap;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final totalMs = (activeDurationMs != null && activeDurationMs! > 0)
        ? activeDurationMs!
        : (durationMs ?? 0);
    final progress = totalMs <= 0
        ? 0.0
        : (progressMs.clamp(0, totalMs) / totalMs).clamp(0.0, 1.0);
    final bars = waveform.isNotEmpty ? waveform : _waveBars(totalMs);

    final accent = isMine ? Colors.white : _kAccent;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: isMine
                ? Colors.black.withValues(alpha: 0.12)
                : _kAccent.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(
              color: isMine
                  ? Colors.black.withValues(alpha: 0.14)
                  : _kAccent.withValues(alpha: 0.34),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Center(
                child: isPreparing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      )
                    : Icon(
                        isPlaying ? LucideIcons.pause : LucideIcons.play,
                        color: accent,
                        size: 18,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 160,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: onSeek == null
                ? null
                : (details) {
                    const width = 160.0;
                    onSeek!(details.localPosition.dx / width);
                  },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      for (var i = 0; i < bars.length; i++) ...[
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 3.0,
                              height: bars[i].toDouble().clamp(8, 28),
                              decoration: BoxDecoration(
                                color: (i / bars.length) <= progress
                                    ? accent
                                    : foreground.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        if (i != bars.length - 1) const SizedBox(width: 2),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatDuration(progressMs > 0 ? progressMs : durationMs),
              style: GoogleFonts.inter(
                color: foreground.withValues(alpha: 0.92),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDuration(totalMs),
              style: GoogleFonts.inter(
                color: foreground.withValues(alpha: 0.56),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static List<int> _waveBars(int totalMs) {
    final seed = totalMs <= 0 ? 17 : totalMs;
    return List<int>.generate(28, (index) {
      final base = ((seed ~/ (index + 3)) + index * 7) % 17;
      return 8 + base;
    });
  }

  static String _formatDuration(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return '0:00';
    final totalSeconds = (durationMs / 1000).round();
    final minutes = (totalSeconds ~/ 60).toString();
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _MessageStatusOverlay extends StatelessWidget {
  const _MessageStatusOverlay({
    required this.isMine,
    required this.createdAt,
    required this.isSeenByOther,
    required this.isDeliveredToOther,
  });

  final bool isMine;
  final DateTime? createdAt;
  final bool isSeenByOther;
  final bool isDeliveredToOther;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.only(top: 6, right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _MessageBubbleState._formatTime(createdAt),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isMine) ...[
              const SizedBox(width: 4),
              Icon(
                isSeenByOther
                    ? Icons.done_all_rounded
                    : isDeliveredToOther
                    ? Icons.done_all_rounded
                    : Icons.done_rounded,
                size: 15,
                color: isSeenByOther
                    ? const Color(0xFF8FD3FF)
                    : Colors.white.withValues(alpha: 0.82),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageImage extends StatelessWidget {
  const _MessageImage({
    required this.imageUrl,
    required this.imageBytes,
    required this.isMine,
    required this.createdAt,
    required this.onOpen,
  });

  final String? imageUrl;
  final Uint8List? imageBytes;
  final bool isMine;
  final DateTime? createdAt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Container(
              constraints: const BoxConstraints(
                minHeight: 160,
                maxHeight: 340,
                minWidth: 180,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isMine
                      ? _kAccent.withValues(alpha: 0.20)
                      : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? InteractiveViewer(
                      child: Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return _MediaPlaceholder(
                            label: 'Chargement photo...',
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: _kAccent,
                              value: progress.expectedTotalBytes == null
                                  ? null
                                  : progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const _MediaPlaceholder(
                            label: 'Impossible de charger cette photo',
                            child: Icon(
                              LucideIcons.imageOff,
                              color: Colors.white70,
                              size: 28,
                            ),
                          );
                        },
                      ),
                    )
                  : imageBytes != null
                  ? InteractiveViewer(
                      child: Image.memory(
                        imageBytes!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    )
                  : const _MediaPlaceholder(
                      label: 'Aucune image disponible',
                      child: Icon(
                        LucideIcons.imageOff,
                        color: Colors.white70,
                        size: 28,
                      ),
                    ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _MessageBubbleState._formatTime(createdAt),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewScreen extends StatefulWidget {
  const _ImagePreviewScreen({
    required this.senderName,
    required this.timeLabel,
    required this.imageUrl,
    required this.imageBytes,
    required this.onDelete,
  });

  final String senderName;
  final String timeLabel;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final Future<void> Function() onDelete;

  @override
  State<_ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<_ImagePreviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _downloadImage() async {
    try {
      Uint8List bytes;
      if (widget.imageBytes != null) {
        bytes = widget.imageBytes!;
      } else if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) {
        final response = await http.get(Uri.parse(widget.imageUrl!));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('download failed');
        }
        bytes = response.bodyBytes;
      } else {
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/stayfix_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image enregistree dans $path',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de telecharger cette image.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A1A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.96),
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                  ? Image.network(
                      widget.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const _MediaPlaceholder(
                          label: 'Impossible de charger cette photo',
                          child: Icon(
                            LucideIcons.imageOff,
                            color: Colors.white70,
                            size: 36,
                          ),
                        );
                      },
                    )
                  : widget.imageBytes != null
                  ? Image.memory(widget.imageBytes!, fit: BoxFit.contain)
                  : const _MediaPlaceholder(
                      label: 'Image indisponible',
                      child: Icon(
                        LucideIcons.imageOff,
                        color: Colors.white70,
                        size: 36,
                      ),
                    ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final animation = CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOutCubic,
              );
              return Transform.translate(
                offset: Offset(0, -42 * (1 - animation.value)),
                child: Opacity(opacity: animation.value, child: child),
              );
            },
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.senderName,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.timeLabel,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      color: Colors.white,
                      icon: const Icon(
                        LucideIcons.moreVertical,
                        color: Colors.white,
                      ),
                      onSelected: (value) async {
                        if (value == 'delete') {
                          final navigator = Navigator.of(context);
                          await widget.onDelete();
                          if (!mounted) return;
                          navigator.pop();
                        } else if (value == 'download') {
                          await _downloadImage();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'download',
                          child: Text('Download'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadComposer extends StatefulWidget {
  const _ThreadComposer({
    required this.controller,
    required this.isSending,
    required this.isRecording,
    required this.isRecordLocked,
    required this.isRecordPaused,
    required this.showRecordComposer,
    required this.recordingElapsed,
    required this.recordingWaveform,
    required this.holdDx,
    required this.holdDy,
    required this.onChanged,
    required this.onAttachTap,
    required this.onCameraTap,
    required this.onCameraLongPress,
    required this.onCameraLongPressEnd,
    required this.onSendTap,
    required this.onMicTap,
    required this.onMicPressStart,
    required this.onMicPressMove,
    required this.onMicPressEnd,
    required this.onRecordDelete,
    required this.onRecordPauseResume,
    required this.onRecordSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isRecording;
  final bool isRecordLocked;
  final bool isRecordPaused;
  final bool showRecordComposer;
  final Duration recordingElapsed;
  final List<int> recordingWaveform;
  final double holdDx;
  final double holdDy;
  final VoidCallback onChanged;
  final VoidCallback onAttachTap;
  final VoidCallback onCameraTap;
  final VoidCallback onCameraLongPress;
  final void Function(LongPressEndDetails) onCameraLongPressEnd;
  final VoidCallback onSendTap;
  final VoidCallback onMicTap;
  final VoidCallback onMicPressStart;
  final void Function(double dx, double dy) onMicPressMove;
  final VoidCallback onMicPressEnd;
  final VoidCallback onRecordDelete;
  final VoidCallback onRecordPauseResume;
  final VoidCallback onRecordSend;

  @override
  State<_ThreadComposer> createState() => _ThreadComposerState();
}

class _ThreadComposerState extends State<_ThreadComposer> {
  final FocusNode _focusNode = FocusNode();
  bool _isComposerActive = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isComposerActive) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _isComposerActive) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString();
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    final recordBars = widget.recordingWaveform.isEmpty
        ? List<int>.filled(26, 10)
        : widget.recordingWaveform;

    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 14 + bottomInset),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.isRecording && !widget.isRecordLocked)
            Positioned(
              right: 8,
              bottom: 72,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _kThreadBorder),
                ),
                child: Column(
                  children: [
                    Icon(
                      widget.holdDy < -80
                          ? LucideIcons.lock
                          : LucideIcons.unlock,
                      color: widget.holdDy < -80 ? _kAccent : kMessagesText,
                      size: 16,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lock',
                      style: GoogleFonts.inter(
                        color: kMessagesText.withValues(alpha: 0.72),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: widget.showRecordComposer
                      ? Container(
                          key: const ValueKey('recording'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _kThreadSurface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: _kThreadBorder),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: widget.onRecordDelete,
                                child: Icon(
                                  LucideIcons.trash2,
                                  color: kMessagesText.withValues(alpha: 0.78),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (!widget.isRecordLocked) ...[
                                Expanded(
                                  child: Text(
                                    widget.holdDx < -60
                                        ? 'Relachez pour annuler'
                                        : widget.holdDy < -50
                                        ? 'Verrouillage en cours...'
                                        : '<  Slide to cancel',
                                    style: GoogleFonts.inter(
                                      color: kMessagesText.withValues(
                                        alpha: 0.74,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                GestureDetector(
                                  onTap: widget.onRecordPauseResume,
                                  child: Icon(
                                    widget.isRecordPaused
                                        ? LucideIcons.mic
                                        : LucideIcons.pause,
                                    color: const Color(0xFFFF6678),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        child: Row(
                                          children: [
                                            for (
                                              var i = 0;
                                              i < recordBars.length;
                                              i++
                                            ) ...[
                                              Expanded(
                                                child: Align(
                                                  alignment: Alignment.center,
                                                  child: Container(
                                                    width: 2.4,
                                                    height: recordBars[i]
                                                        .toDouble(),
                                                    decoration: BoxDecoration(
                                                      color: kMessagesText
                                                          .withValues(
                                                            alpha: 0.84,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (i != recordBars.length - 1)
                                                const SizedBox(width: 2),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDuration(
                                          widget.recordingElapsed,
                                        ),
                                        style: GoogleFonts.inter(
                                          color: kMessagesText.withValues(
                                            alpha: 0.84,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : Row(
                          key: const ValueKey('composer'),
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: widget.isSending
                                  ? null
                                  : widget.onAttachTap,
                              icon: Icon(
                                LucideIcons.paperclip,
                                color: kMessagesText.withValues(alpha: 0.78),
                                size: 20,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _kThreadSurface,
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: _kThreadBorder),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: widget.controller,
                                        focusNode: _focusNode,
                                        onChanged: (_) => widget.onChanged(),
                                        onTap: () => setState(
                                          () => _isComposerActive = true,
                                        ),
                                        minLines: 1,
                                        maxLines: 5,
                                        style: GoogleFonts.inter(
                                          color: kMessagesText,
                                          fontSize: 14,
                                        ),
                                        cursorColor: _kAccent,
                                        decoration: InputDecoration(
                                          hintText: 'Message',
                                          hintStyle: GoogleFonts.inter(
                                            color: kMessagesText.withValues(
                                              alpha: 0.38,
                                            ),
                                            fontSize: 14,
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    GestureDetector(
                                      onTap: widget.isSending
                                          ? null
                                          : widget.onCameraTap,
                                      onLongPress: widget.isSending
                                          ? null
                                          : widget.onCameraLongPress,
                                      onLongPressEnd: widget.isSending
                                          ? null
                                          : widget.onCameraLongPressEnd,
                                      child: Icon(
                                        LucideIcons.camera,
                                        color: kMessagesText.withValues(
                                          alpha: 0.78,
                                        ),
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: widget.isSending
                    ? null
                    : (widget.showRecordComposer
                          ? () {
                              setState(() => _isComposerActive = false);
                              widget.onRecordSend();
                            }
                          : (hasText
                                ? () {
                                    setState(() => _isComposerActive = false);
                                    widget.onSendTap();
                                  }
                                : widget.onMicTap)),
                onLongPressStart: hasText
                    ? null
                    : (_) {
                        widget.onMicPressStart();
                      },
                onLongPressMoveUpdate: hasText
                    ? null
                    : (details) {
                        widget.onMicPressMove(
                          details.offsetFromOrigin.dx,
                          details.offsetFromOrigin.dy,
                        );
                      },
                onLongPressEnd: hasText
                    ? null
                    : (_) {
                        widget.onMicPressEnd();
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: widget.isRecording
                        ? const Color(0xFFFF6678)
                        : _kAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (widget.isRecording
                                    ? const Color(0xFFFF6678)
                                    : _kAccent)
                                .withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: widget.isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            widget.showRecordComposer
                                ? LucideIcons.send
                                : hasText
                                ? LucideIcons.send
                                : LucideIcons.mic,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StayFixReactionOverlay extends StatelessWidget {
  const _StayFixReactionOverlay({
    required this.targetRect,
    required this.selectedReaction,
  });

  final Rect targetRect;
  final String? selectedReaction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const trayWidth = 332.0;
    final left = (targetRect.center.dx - (trayWidth / 2)).clamp(
      14.0,
      size.width - trayWidth - 14.0,
    );
    final top = (targetRect.top - 88).clamp(
      MediaQuery.paddingOf(context).top + 6.0,
      size.height - 180.0,
    );
    final pointerLeft = (targetRect.center.dx - left - 10).clamp(
      18.0,
      trayWidth - 32.0,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: StayFixReactionTray(
              pointerLeft: pointerLeft,
              selectedReaction: selectedReaction,
              onSelected: (reaction) => Navigator.pop(context, reaction),
            ),
          ),
        ],
      ),
    );
  }
}

class StayFixReactionTray extends StatelessWidget {
  const StayFixReactionTray({
    super.key,
    required this.pointerLeft,
    required this.selectedReaction,
    required this.onSelected,
  });

  final double pointerLeft;
  final String? selectedReaction;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xCC1B2431),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _kReactionIcons.keys.map((reaction) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: StayFixReactionButton(
                      reaction: reaction,
                      selected: reaction == selectedReaction,
                      onTap: () => onSelected(reaction),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(pointerLeft, -1),
          child: CustomPaint(
            size: const Size(20, 10),
            painter: _ReactionPointerPainter(),
          ),
        ),
      ],
    );
  }
}

class StayFixReactionButton extends StatefulWidget {
  const StayFixReactionButton({
    super.key,
    required this.reaction,
    required this.selected,
    required this.onTap,
  });

  final String reaction;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<StayFixReactionButton> createState() => _StayFixReactionButtonState();
}

class _StayFixReactionButtonState extends State<StayFixReactionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = _kReactionColors[widget.reaction] ?? Colors.white;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        scale: _pressed ? 0.92 : 1,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: widget.selected ? 0.95 : 0.52),
                const Color(0xFF1F2A37),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.24),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            _kReactionIcons[widget.reaction],
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class StayFixReactionBadge extends StatelessWidget {
  const StayFixReactionBadge({
    super.key,
    required this.reaction,
    this.highlighted = false,
  });

  final String reaction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final accent = _kReactionColors[reaction] ?? _kAccent;
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: highlighted ? 1.08 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.withValues(alpha: 0.96), const Color(0xFF314B76)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(_kReactionIcons[reaction], color: Colors.white, size: 14),
      ),
    );
  }
}

class _StayFixHeartBurst extends StatelessWidget {
  const _StayFixHeartBurst();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD6A85A), Color(0xFF406ACF)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD6A85A).withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(LucideIcons.heart, color: Colors.white, size: 16),
    );
  }
}

class _ReactionPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xCC1B2431));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChatContactInfoScreen extends StatelessWidget {
  const _ChatContactInfoScreen({
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.avatarBase64,
    required this.avatarUrl,
  });

  final String conversationId;
  final String title;
  final String subtitle;
  final String? avatarBase64;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    Uint8List? photoBytes;
    if (avatarBase64 != null && avatarBase64!.isNotEmpty) {
      try {
        photoBytes = base64Decode(avatarBase64!);
      } catch (_) {}
    }

    final conversationRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: kMessagesPageBg,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: conversationRef.snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? const <String, dynamic>{};
          final mutedBy = ((data['mutedBy'] as List?) ?? const [])
              .map((e) => '$e')
              .toSet();
          final notificationsEnabled = !mutedBy.contains(uid);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                elevation: 0,
                backgroundColor: kMessagesPageBg,
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.arrowLeft, color: kMessagesText),
                ),
                title: Text(
                  'Contact info',
                  style: GoogleFonts.inter(
                    color: kMessagesText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kMessagesBlue, kMessagesDeepBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F2563EB),
                              blurRadius: 28,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 92,
                              height: 92,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: ClipOval(
                                child:
                                    avatarUrl != null && avatarUrl!.isNotEmpty
                                    ? Image.network(
                                        avatarUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                photoBytes != null
                                                ? Image.memory(
                                                    photoBytes,
                                                    fit: BoxFit.cover,
                                                  )
                                                : _ContactInfoInitial(
                                                    title: title,
                                                  ),
                                      )
                                    : photoBytes != null
                                    ? Image.memory(
                                        photoBytes,
                                        fit: BoxFit.cover,
                                      )
                                    : _ContactInfoInitial(title: title),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Intervenant / manager',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    title,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      height: 1.08,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: GoogleFonts.inter(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      fontSize: 13.5,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _ContactInfoPanel(
                        title: 'Conversation settings',
                        child: Column(
                          children: [
                            _ContactInfoTile(
                              icon: LucideIcons.bell,
                              title: 'Notifications',
                              subtitle: notificationsEnabled
                                  ? 'Enabled for this chat'
                                  : 'Muted for this chat',
                              trailing: Switch(
                                value: notificationsEnabled,
                                onChanged: (enabled) {
                                  final op = enabled
                                      ? FieldValue.arrayRemove([uid])
                                      : FieldValue.arrayUnion([uid]);
                                  conversationRef.set({
                                    'mutedBy': op,
                                  }, SetOptions(merge: true));
                                },
                              ),
                            ),
                            const _ContactInfoTile(
                              icon: LucideIcons.server,
                              title: 'Stockage des médias',
                              subtitle:
                                  'Vos photos et messages vocaux sont stockés avec soin et en toute sécurité.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ContactInfoPanel(
                        title: 'Actions',
                        child: Column(
                          children: [
                            _ContactInfoTile(
                              icon: LucideIcons.trash2,
                              title: 'Clear chat',
                              subtitle:
                                  'Remove all messages from this conversation.',
                              destructive: true,
                              onTap: () async {
                                await _clearConversationHistoryById(
                                  conversationId,
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ContactInfoPanel extends StatelessWidget {
  const _ContactInfoPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kMessagesBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120B2A66),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: kMessagesText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ContactInfoInitial extends StatelessWidget {
  const _ContactInfoInitial({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFDCEBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: GoogleFonts.inter(
          color: _kAccent,
          fontSize: 34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ContactInfoTile extends StatelessWidget {
  const _ContactInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? kMessagesDanger : kMessagesText;
    final trailingWidgets = trailing == null
        ? const <Widget>[]
        : <Widget>[trailing!];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: destructive
                    ? const Color(0xFFFEE2E2)
                    : kMessagesSoftBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: titleColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: kMessagesBody,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            ...trailingWidgets,
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  const _AttachmentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE7FA)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _kAccent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: kMessagesText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: kMessagesText.withValues(alpha: 0.55),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              LucideIcons.chevronRight,
              color: Colors.white.withValues(alpha: 0.34),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatOptionTile extends StatelessWidget {
  const _ChatOptionTile({
    required this.icon,
    required this.title,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFD64B4B) : Colors.black87;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: trailing,
    );
  }
}

class _VideoPlayerPage extends StatefulWidget {
  const _VideoPlayerPage({required this.url});

  final String url;

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _initialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(color: kMessagesBlue),
      ),
      floatingActionButton: _initialized
          ? FloatingActionButton(
              backgroundColor: kMessagesBlue,
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}
