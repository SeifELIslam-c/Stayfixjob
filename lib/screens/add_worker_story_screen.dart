import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../services/offers_service.dart' show WorkerProfile;
import '../services/story_service.dart';

// ── Colors ────────────────────────────────────────────────────────────────────
const _kBlue = Color(0xFF0F63FF);
const _kMuted = Color(0xFF64748B);

// ── Visibility options ────────────────────────────────────────────────────────
const _kVisibilityOptions = [
  'Les abonnés proches de moi',
  'Tout le monde',
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
  final _textController = TextEditingController();
  final _picker = ImagePicker();

  File? _selectedMedia;
  String _mediaType = '';
  double? _aspectRatio;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  String _overlayText = '';
  Offset _textOffset = const Offset(0.5, 0.4);
  bool _editingText = false;

  late String _selectedSpecialty;
  String _visibility = _kVisibilityOptions.first;
  bool _isPublishing = false;
  double _uploadProgress = 0.0;

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
    _textController.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  // ── Media picking ─────────────────────────────────────────────────────────

  Future<void> _pickMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MediaPickerSheet(),
    );
    if (choice == null || !mounted) return;

    XFile? xfile;
    if (choice == 'photo') {
      xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
    } else {
      xfile = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 15),
      );
    }
    if (xfile == null || !mounted) return;

    final file = File(xfile.path);
    await _videoCtrl?.dispose();
    _videoCtrl = null;

    if (choice == 'photo') {
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final ratio = decoded.width / decoded.height;
      setState(() {
        _selectedMedia = file;
        _mediaType = 'image';
        _aspectRatio = ratio;
        _videoReady = false;
      });
    } else {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      setState(() {
        _selectedMedia = file;
        _mediaType = 'video';
        _aspectRatio = ctrl.value.aspectRatio;
        _videoCtrl = ctrl;
        _videoReady = true;
      });
      ctrl.setLooping(true);
      ctrl.play();
    }
  }

  void _clearMedia() {
    _videoCtrl?.dispose();
    setState(() {
      _selectedMedia = null;
      _mediaType = '';
      _aspectRatio = null;
      _videoCtrl = null;
      _videoReady = false;
    });
  }

  // ── Publish ───────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (_selectedMedia == null) {
      _snack('Veuillez ajouter une photo ou une vidéo.');
      return;
    }
    if (widget.profile.specialties.isEmpty) {
      _snack(
        'Ajoutez une spécialité à votre profil avant de publier une story.',
      );
      return;
    }
    if (_captionCtrl.text.trim().length > 200) {
      _snack('La légende ne peut pas dépasser 200 caractères.');
      return;
    }

    setState(() {
      _isPublishing = true;
      _uploadProgress = 0.0;
    });
    try {
      await _storyService.publishStory(
        workerName: widget.profile.username,
        workerDepartment: widget.profile.department,
        workerSpecialty: _selectedSpecialty,
        workerPhotoUrl: widget.profile.photoUrl,
        isAvailable: widget.profile.isAvailable,
        mediaFile: _selectedMedia!,
        mediaType: _mediaType,
        caption: _captionCtrl.text,
        visibility: _visibility,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
        overlayText: _overlayText,
        overlayTextX: _textOffset.dx,
        overlayTextY: _textOffset.dy,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Story publiée avec succès.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Story publish UI error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de l\'envoi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Aspect ratio helpers ──────────────────────────────────────────────────

  bool get _isVertical => (_aspectRatio ?? 1.0) < 0.75;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _selectedMedia == null ? _buildEmptyState() : _buildPreviewState(),
    );
  }

  // ── State 1: Empty (no media) ─────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dark gradient background
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A0E1A), Color(0xFF0F1828)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              _buildTopBar(mediaSelected: false),
              _buildRightTools(),
              Expanded(child: _buildUploadBox()),
              _buildBottomControls(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUploadBox() {
    return Center(
      child: GestureDetector(
        onTap: _pickMedia,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBlue, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: CustomPaint(
              painter: _DashedBorderPainter(),
              child: Container(
                color: Colors.white.withValues(alpha: 0.04),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.imagePlus,
                        color: _kBlue,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Ajoutez une photo ou une vidéo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _kBlue,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Appuyez pour sélectionner dans la galerie\nou glissez-déposez ici',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── State 2: Media preview ────────────────────────────────────────────────

  Widget _buildPreviewState() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen media
          _buildFullScreenMedia(),
          // Overlaid controls
          SafeArea(
            child: Stack(
              children: [
                // Top bar
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: _buildTopBar(mediaSelected: true),
                ),
                // Right tools
                Positioned(
                  top: 60, right: 12,
                  child: _buildRightTools(),
                ),
                // Caption + bottom controls
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCaptionOverlay(),
                      _buildBottomControls(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Draggable overlay text
          if (_overlayText.isNotEmpty && !_editingText)
            Positioned(
              left: (_textOffset.dx * MediaQuery.of(context).size.width) - 50,
              top: (_textOffset.dy * MediaQuery.of(context).size.height) - 20,
              child: GestureDetector(
                onTap: () => setState(() {
                  _textController.text = _overlayText;
                  _editingText = true;
                }),
                onPanUpdate: (d) => setState(() {
                  final w = MediaQuery.of(context).size.width;
                  final h = MediaQuery.of(context).size.height;
                  _textOffset = Offset(
                    (_textOffset.dx + d.delta.dx / w).clamp(0.1, 0.9),
                    (_textOffset.dy + d.delta.dy / h).clamp(0.1, 0.9),
                  );
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _overlayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          // Text editor overlay
          if (_editingText)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: TextField(
                        controller: _textController,
                        autofocus: true,
                        maxLines: null,
                        textAlign: TextAlign.center,
                        cursorColor: Colors.white,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Tapez votre texte...',
                          hintStyle: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    right: 16,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _overlayText = _textController.text.trim();
                        _editingText = false;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F63FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Terminé',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullScreenMedia() {
    if (_mediaType == 'image') {
      return Image.file(
        _selectedMedia!,
        fit: _isVertical ? BoxFit.cover : BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (_mediaType == 'video') {
      if (!_videoReady) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }
      return FittedBox(
        fit: _isVertical ? BoxFit.cover : BoxFit.contain,
        child: SizedBox(
          width: _videoCtrl!.value.size.width,
          height: _videoCtrl!.value.size.height,
          child: VideoPlayer(_videoCtrl!),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCaptionOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 32, 12, 8),
      child: TextField(
        controller: _captionCtrl,
        maxLength: 200,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Ajouter une légende...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 14),
          prefixIcon: const Icon(LucideIcons.pencil, color: Colors.white60, size: 16),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          counterStyle: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
    );
  }


  // ── Shared UI pieces ──────────────────────────────────────────────────────

  Widget _buildTopBar({required bool mediaSelected}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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

  Widget _buildRightTools() {
    if (_selectedMedia == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _storyToolBtn(
              icon: LucideIcons.type,
              label: 'Texte',
              onTap: () => setState(() => _editingText = true),
            ),
            if (_mediaType == 'image') ...[
              const SizedBox(height: 12),
              _storyToolBtn(
                icon: LucideIcons.crop,
                label: 'Recadrer',
                onTap: () async {
                  if (_selectedMedia == null || _mediaType != 'image') return;
                  final cropped = await ImageCropper().cropImage(
                    sourcePath: _selectedMedia!.path,
                    uiSettings: [
                      AndroidUiSettings(
                        toolbarTitle: 'Recadrer',
                        toolbarColor: const Color(0xFF0F63FF),
                        toolbarWidgetColor: Colors.white,
                        initAspectRatio: CropAspectRatioPreset.original,
                        lockAspectRatio: false,
                      ),
                      IOSUiSettings(title: 'Recadrer'),
                    ],
                  );
                  if (cropped != null && mounted) {
                    setState(() => _selectedMedia = File(cropped.path));
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        20 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.88),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Specialty + visibility chips
          Row(
            children: [
              Expanded(child: _buildSpecialtyChip()),
              const SizedBox(width: 10),
              Expanded(child: _buildVisibilityChip()),
            ],
          ),
          const SizedBox(height: 14),
          // Upload progress indicator
          if (_isPublishing) ...[
            LinearProgressIndicator(
              value: _uploadProgress,
              color: _kBlue,
              backgroundColor: _kBlue.withValues(alpha: 0.15),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 6),
            Text(
              'Publication en cours… ${(_uploadProgress * 100).toInt()}%',
              style: const TextStyle(
                color: _kMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
          ],
          // Publish button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isPublishing ? null : _publish,
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
                        strokeWidth: 2.5,
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
      ),
    );
  }

  Widget _buildSpecialtyChip() {
    final specs = widget.profile.specialties;
    if (specs.isEmpty) {
      return _dropdownChip(
        icon: LucideIcons.wrench,
        label: 'Aucune spécialité',
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
            title: 'Spécialité',
            options: specs,
            selected: _selectedSpecialty,
          ),
        );
        if (picked != null) setState(() => _selectedSpecialty = picked);
      },
    );
  }

  Widget _buildVisibilityChip() {
    return _dropdownChip(
      icon: LucideIcons.users,
      label: _visibility,
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _PickerSheet(
            title: 'Visibilité',
            options: _kVisibilityOptions,
            selected: _visibility,
          ),
        );
        if (picked != null) setState(() => _visibility = picked);
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
          border: Border.all(color: const Color(0xFFE6EEFF)),
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
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.black.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Icon(
          icon,
          color: disabled ? Colors.white54 : const Color(0xFF0F172A),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF0F172A), size: 20),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Media picker bottom sheet ─────────────────────────────────────────────────

class _MediaPickerSheet extends StatelessWidget {
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
            'Ajouter un média',
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
            label: 'Vidéo (15 s max)',
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
          border: Border.all(color: const Color(0xFFE6EEFF)),
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

// ── Generic picker bottom sheet ───────────────────────────────────────────────

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
          ...options.map((opt) {
            final isSelected = opt == selected;
            return GestureDetector(
              onTap: () => Navigator.pop(context, opt),
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
                  border: Border.all(
                    color: isSelected ? _kBlue : const Color(0xFFE6EEFF),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        opt,
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

// ── Dashed border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kBlue.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashW = 8.0;
    const gapW = 6.0;
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(20),
    );
    final path = Path()..addRRect(rr);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dashW), paint);
        dist += dashW + gapW;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
