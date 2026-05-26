import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../services/offers_service.dart' show WorkerProfile;
import '../services/story_service.dart';
import '../services/vps_media_service.dart';

const _kBlue = Color(0xFF0F63FF);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFDCE8FF);

const _kVisibilityOptions = <_StoryVisibilityOption>[
  _StoryVisibilityOption(
    key: 'nearby_subscribers',
    label: 'Les abonnes proches de moi',
  ),
  _StoryVisibilityOption(key: 'public', label: 'Tout le monde'),
];

final _kOverlayFonts = <TextStyle Function(double, Color)>[
  (size, color) => TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
  (size, color) => GoogleFonts.bebasNeue(
        color: color,
        fontSize: size + 6,
        letterSpacing: 0.4,
      ),
  (size, color) => GoogleFonts.playfairDisplay(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.12,
      ),
  (size, color) => GoogleFonts.oswald(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
      ),
];

class AddWorkerStoryScreen extends StatefulWidget {
  const AddWorkerStoryScreen({super.key, required this.profile});

  final WorkerProfile profile;

  @override
  State<AddWorkerStoryScreen> createState() => _AddWorkerStoryScreenState();
}

class _AddWorkerStoryScreenState extends State<AddWorkerStoryScreen> {
  final _storyService = StoryService();
  final _captionCtrl = TextEditingController();
  final _overlayTextCtrl = TextEditingController();
  final _overlayTextFocusNode = FocusNode();
  final _picker = ImagePicker();

  File? _selectedMedia;
  VpsUploadedMedia? _uploadedMedia;
  String _mediaType = '';
  double? _aspectRatio;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  late String _selectedSpecialty;
  _StoryVisibilityOption _selectedVisibility = _kVisibilityOptions.first;
  bool _isPublishing = false;
  bool _isUploadingMedia = false;
  bool _isEditingOverlayText = false;
  double _uploadProgress = 0;
  double _overlayTextX = 0.5;
  double _overlayTextY = 0.42;
  double _overlayTextScale = 1;
  double _overlayTextScaleStart = 1;
  int _overlayFontIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedSpecialty = widget.profile.specialties.isNotEmpty
        ? widget.profile.specialties.first
        : '';
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _overlayTextCtrl.dispose();
    _overlayTextFocusNode.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MediaPickerSheet(),
    );
    if (choice == null || !mounted) return;

    XFile? xfile;
    if (choice == 'photo') {
      xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 2160,
      );
    } else {
      xfile = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 15),
      );
    }
    if (xfile == null || !mounted) return;

    await _discardPendingUploadedMedia();
    await _videoCtrl?.dispose();
    _videoCtrl = null;

    final file = File(xfile.path);
    if (choice == 'photo') {
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      setState(() {
        _selectedMedia = file;
        _uploadedMedia = null;
        _mediaType = 'image';
        _aspectRatio = decoded.width / decoded.height;
        _videoReady = false;
        _isUploadingMedia = true;
        _uploadProgress = 0;
      });
      unawaited(_uploadSelectedMedia(file, mediaType: 'image'));
      return;
    }

    final ctrl = VideoPlayerController.file(file);
    await ctrl.initialize();
    ctrl
      ..setLooping(true)
      ..play();

    setState(() {
      _selectedMedia = file;
      _uploadedMedia = null;
      _mediaType = 'video';
      _aspectRatio = ctrl.value.aspectRatio;
      _videoCtrl = ctrl;
      _videoReady = true;
      _isUploadingMedia = true;
      _uploadProgress = 0;
    });
    unawaited(_uploadSelectedMedia(file, mediaType: 'video'));
  }

  Future<void> _cropImage() async {
    if (_selectedMedia == null || _mediaType != 'image') return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: _selectedMedia!.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recadrer',
          toolbarColor: _kBlue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Recadrer'),
      ],
    );
    if (cropped == null || !mounted) return;

    final file = File(cropped.path);
    final bytes = await file.readAsBytes();
    final decoded = await decodeImageFromList(bytes);
    setState(() {
      _selectedMedia = file;
      _uploadedMedia = null;
      _aspectRatio = decoded.width / decoded.height;
      _isUploadingMedia = true;
      _uploadProgress = 0;
    });
    unawaited(_uploadSelectedMedia(file, mediaType: 'image'));
  }

  void _editOverlayText() {
    setState(() {
      _isEditingOverlayText = true;
      if (_overlayTextCtrl.text.trim().isEmpty) {
        _overlayTextX = 0.5;
        _overlayTextY = 0.42;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _overlayTextFocusNode.requestFocus();
    });
  }

  void _finishOverlayTextEditing() {
    FocusScope.of(context).unfocus();
    setState(() {
      _overlayTextCtrl.text = _overlayTextCtrl.text.trim();
      _isEditingOverlayText = false;
    });
  }

  void _clearMedia() {
    unawaited(_discardPendingUploadedMedia());
    _videoCtrl?.dispose();
    setState(() {
      _selectedMedia = null;
      _uploadedMedia = null;
      _mediaType = '';
      _aspectRatio = null;
      _videoCtrl = null;
      _videoReady = false;
      _isUploadingMedia = false;
      _uploadProgress = 0;
      _overlayTextCtrl.clear();
      _isEditingOverlayText = false;
      _overlayTextX = 0.5;
      _overlayTextY = 0.42;
      _overlayTextScale = 1;
      _overlayFontIndex = 0;
    });
  }

  Future<void> _uploadSelectedMedia(
    File file, {
    required String mediaType,
  }) async {
    try {
      final category = mediaType == 'video' ? 'story-video' : 'story-image';
      final uploaded = await VpsMediaService.uploadFile(
        file: file,
        category: category,
        folder: 'stories/${widget.profile.uid}',
        onProgress: (progress) {
          if (!mounted || _selectedMedia?.path != file.path) return;
          setState(() => _uploadProgress = progress.clamp(0, 1));
        },
      );
      if (!mounted || _selectedMedia?.path != file.path) return;
      setState(() {
        _uploadedMedia = uploaded;
        _isUploadingMedia = false;
        _uploadProgress = 1;
      });
    } catch (_) {
      if (!mounted || _selectedMedia?.path != file.path) return;
      setState(() {
        _isUploadingMedia = false;
        _uploadProgress = 0;
      });
      _snack("Impossible d'envoyer le média pour le moment.");
    }
  }

  Future<void> _discardPendingUploadedMedia() async {
    final fileId = _uploadedMedia?.fileId.trim() ?? '';
    if (fileId.isEmpty) return;
    try {
      await VpsMediaService.deleteFiles([fileId]);
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (_selectedMedia == null) {
      _snack('Veuillez ajouter une photo ou une video.');
      return;
    }
    if (widget.profile.specialties.isEmpty) {
      _snack(
        'Ajoutez une specialite a votre profil avant de publier une story.',
      );
      return;
    }
    if (_captionCtrl.text.trim().length > 200) {
      _snack('La legende ne peut pas depasser 200 caracteres.');
      return;
    }
    if (_isUploadingMedia || _uploadedMedia == null) {
      _snack("Patientez pendant l'envoi du média.");
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await _videoCtrl?.pause();
      await _storyService.publishStory(
        workerName: widget.profile.username,
        workerDepartment: widget.profile.department,
        workerSpecialty: _selectedSpecialty,
        workerPhotoUrl: widget.profile.photoUrl,
        isAvailable: widget.profile.isAvailable,
        mediaFile: _selectedMedia!,
        mediaType: _mediaType,
        caption: _captionCtrl.text.trim(),
        visibility: _selectedVisibility.label,
        visibilityKey: _selectedVisibility.key,
        uploadedMedia: _uploadedMedia,
        overlayText: _overlayTextCtrl.text.trim(),
        overlayTextX: _overlayTextX,
        overlayTextY: _overlayTextY,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story publiee avec succes.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _snack('Echec de l envoi: $e');
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isPortraitStoryMedia => (_aspectRatio ?? 1) <= (9 / 16) + 0.02;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _selectedMedia == null ? _buildEmptyState() : _buildPreviewState(),
    );
  }

  Widget _buildEmptyState() {
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(mediaSelected: false),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _pickMedia,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 40,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _kBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F63FF),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          LucideIcons.imagePlus,
                          color: _kBlue,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Ajoutez une photo ou une video',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Les stories verticales prennent tout l ecran et les medias sont envoyes directement en fichier complet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _kMuted,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildPreviewState() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMediaBackdrop(),
        _buildMediaPreview(),
        if (_overlayTextCtrl.text.trim().isNotEmpty || _isEditingOverlayText)
          _buildDraggableOverlayText(),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.48),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.62),
                  ],
                  stops: const [0, 0.18, 0.65, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              _buildTopBar(mediaSelected: true),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_mediaType == 'image') ...[
                      _storyToolBtn(
                        icon: LucideIcons.crop,
                        label: 'Recadrer',
                        onTap: _cropImage,
                      ),
                      const SizedBox(width: 10),
                    ],
                    _storyToolBtn(
                      icon: _isEditingOverlayText
                          ? LucideIcons.check
                          : LucideIcons.type,
                      label: _isEditingOverlayText
                          ? 'Terminer'
                          : _overlayTextCtrl.text.trim().isEmpty
                          ? 'Texte'
                          : 'Modifier le texte',
                      onTap: _isEditingOverlayText
                          ? _finishOverlayTextEditing
                          : _editOverlayText,
                    ),
                    if (_overlayTextCtrl.text.trim().isNotEmpty ||
                        _isEditingOverlayText) ...[
                      const SizedBox(width: 10),
                      _storyToolBtn(
                        icon: LucideIcons.caseSensitive,
                        label: 'Police',
                        onTap: () {
                          setState(() {
                            _overlayFontIndex =
                                (_overlayFontIndex + 1) % _kOverlayFonts.length;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              _buildBottomControls(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaBackdrop() {
    if (_selectedMedia == null) return const SizedBox.shrink();
    final shouldBackdrop = !_isPortraitStoryMedia;
    if (!shouldBackdrop) {
      return Container(color: Colors.black);
    }

    if (_mediaType == 'image') {
      return Image.file(
        _selectedMedia!,
        fit: BoxFit.cover,
        color: Colors.black.withValues(alpha: 0.28),
        colorBlendMode: BlendMode.darken,
      );
    }

    if (_mediaType == 'video' && _videoReady && _videoCtrl != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoCtrl!.value.size.width,
          height: _videoCtrl!.value.size.height,
          child: Opacity(opacity: 0.28, child: VideoPlayer(_videoCtrl!)),
        ),
      );
    }

    return Container(color: Colors.black);
  }

  Widget _buildMediaPreview() {
    final fit = _isPortraitStoryMedia ? BoxFit.cover : BoxFit.contain;

    if (_mediaType == 'image') {
      return Image.file(_selectedMedia!, fit: fit);
    }

    if (_mediaType == 'video') {
      if (!_videoReady || _videoCtrl == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: _videoCtrl!.value.size.width,
            height: _videoCtrl!.value.size.height,
            child: VideoPlayer(_videoCtrl!),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDraggableOverlayText() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final safeLeft = 20.0;
        final safeTop = 110.0;
        final safeRight = constraints.maxWidth - 20;
        final safeBottom = constraints.maxHeight - 220;
        final left = _overlayTextX * constraints.maxWidth;
        final top = _overlayTextY * constraints.maxHeight;
        final clampedLeft = left.clamp(safeLeft, safeRight);
        final clampedTop = top.clamp(safeTop, safeBottom);

        return Positioned(
          left: clampedLeft - 110,
          top: clampedTop - 28,
          child: GestureDetector(
            onScaleStart: (_) {
              _overlayTextScaleStart = _overlayTextScale;
            },
            onScaleUpdate: (details) {
              final nextLeft = (clampedLeft + details.focalPointDelta.dx).clamp(
                safeLeft,
                safeRight,
              );
              final nextTop = (clampedTop + details.focalPointDelta.dy).clamp(
                safeTop,
                safeBottom,
              );
              setState(() {
                _overlayTextX = nextLeft / constraints.maxWidth;
                _overlayTextY = nextTop / constraints.maxHeight;
                _overlayTextScale = (_overlayTextScaleStart * details.scale)
                    .clamp(0.7, 2.8);
              });
            },
            onTap: _isEditingOverlayText ? null : _editOverlayText,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _isEditingOverlayText
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: TextField(
                        controller: _overlayTextCtrl,
                        focusNode: _overlayTextFocusNode,
                        maxLength: 120,
                        maxLines: 3,
                        textAlign: TextAlign.center,
                        cursorColor: Colors.white,
                        style: _overlayTextStyle(),
                        decoration: const InputDecoration(
                          hintText: 'Tapez votre texte',
                          hintStyle: TextStyle(
                            color: Colors.white70,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                          border: InputBorder.none,
                          counterText: '',
                          isCollapsed: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _finishOverlayTextEditing(),
                      ),
                    )
                  : Text(
                      _overlayTextCtrl.text.trim(),
                      textAlign: TextAlign.center,
                      style: _overlayTextStyle(),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar({required bool mediaSelected}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _storyIconBtn(
            icon: LucideIcons.arrowLeft,
            onTap: () => Navigator.pop(context),
          ),
          const Spacer(),
          _storyIconBtn(
            icon: LucideIcons.trash2,
            onTap: mediaSelected ? _clearMedia : null,
            disabled: !mediaSelected,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: _selectedMedia == null ? Colors.transparent : Colors.white,
        borderRadius: _selectedMedia == null
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedMedia != null) ...[
            if (_isUploadingMedia) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mediaType == 'video'
                          ? 'Envoi de la vidéo au VPS...'
                          : 'Envoi de la photo au VPS...',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: _uploadProgress <= 0 ? null : _uploadProgress,
                        backgroundColor: const Color(0xFFE5EEFF),
                        valueColor: const AlwaysStoppedAnimation<Color>(_kBlue),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kBorder),
              ),
              child: TextField(
                controller: _captionCtrl,
                maxLength: 200,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Ajouter une legende',
                  hintStyle: TextStyle(color: _kMuted),
                  prefixIcon: Icon(
                    LucideIcons.pencilLine,
                    color: _kBlue,
                    size: 18,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildSpecialtyChip()),
                const SizedBox(width: 10),
                Expanded(child: _buildVisibilityChip()),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isPublishing || _isUploadingMedia) ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kBlue.withValues(alpha: 0.6),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isPublishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Text(
                        'Publier la story',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecialtyChip() {
    final specs = widget.profile.specialties;
    if (specs.isEmpty) {
      return _dropdownChip(
        icon: LucideIcons.wrench,
        label: 'Aucune specialite',
        onTap: null,
      );
    }
    return _dropdownChip(
      icon: LucideIcons.wrench,
      label: _selectedSpecialty,
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _PickerSheet(
            title: 'Specialite',
            options: specs,
            selected: _selectedSpecialty,
          ),
        );
        if (picked != null && mounted) {
          setState(() => _selectedSpecialty = picked);
        }
      },
    );
  }

  Widget _buildVisibilityChip() {
    return _dropdownChip(
      icon: LucideIcons.users,
      label: _selectedVisibility.label,
      onTap: () async {
        final picked = await showModalBottomSheet<_StoryVisibilityOption>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _VisibilityPickerSheet(selected: _selectedVisibility),
        );
        if (picked != null && mounted) {
          setState(() => _selectedVisibility = picked);
        }
      },
    );
  }

  Widget _dropdownChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: _kBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronDown, size: 13, color: _kMuted),
          ],
        ),
      ),
    );
  }

  Widget _storyIconBtn({
    required IconData icon,
    required VoidCallback? onTap,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.72)
              : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: disabled ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
          size: 18,
        ),
      ),
    );
  }

  Widget _storyToolBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _kBlue, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _overlayTextStyle() {
    final style =
        _kOverlayFonts[_overlayFontIndex](24 * _overlayTextScale, Colors.white);
    return style.copyWith(
      shadows: const [
        Shadow(
          color: Colors.black54,
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    );
  }
}

class _MediaPickerSheet extends StatelessWidget {
  const _MediaPickerSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Ajouter un media',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 18),
          _sheetOption(
            context,
            icon: LucideIcons.image,
            label: 'Photo',
            value: 'photo',
          ),
          const SizedBox(height: 10),
          _sheetOption(
            context,
            icon: LucideIcons.video,
            label: 'Video (15 s max)',
            value: 'video',
          ),
        ],
      ),
    );
  }

  Widget _sheetOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _kBlue, size: 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),
          ...options.map((option) {
            final isSelected = option == selected;
            return GestureDetector(
              onTap: () => Navigator.pop(context, option),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isSelected ? _kBlue : _kBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          color: isSelected ? _kBlue : const Color(0xFF0F172A),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(LucideIcons.check, color: _kBlue, size: 16),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _VisibilityPickerSheet extends StatelessWidget {
  const _VisibilityPickerSheet({required this.selected});

  final _StoryVisibilityOption selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Visibilite',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),
          ..._kVisibilityOptions.map((option) {
            final isSelected = option.key == selected.key;
            return GestureDetector(
              onTap: () => Navigator.pop(context, option),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF7FAFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isSelected ? _kBlue : _kBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        style: TextStyle(
                          color: isSelected ? _kBlue : const Color(0xFF0F172A),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(LucideIcons.check, color: _kBlue, size: 16),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StoryVisibilityOption {
  const _StoryVisibilityOption({required this.key, required this.label});

  final String key;
  final String label;
}
