import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
  final _picker = ImagePicker();

  File? _selectedMedia;
  String _mediaType = '';
  double? _aspectRatio;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

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
    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(mediaSelected: true),
            _buildRightTools(),
            Expanded(child: _buildMediaWithCaption()),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaWithCaption() {
    final targetRatio = _isVertical ? (9.0 / 16.0) : (16.0 / 9.0);
    return Center(
      child: AspectRatio(
        aspectRatio: targetRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background layer: blurred fill for landscape, cover for portrait
              if (_mediaType == 'image')
                _isVertical
                    ? Image.file(_selectedMedia!, fit: BoxFit.cover)
                    : ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: Image.file(_selectedMedia!, fit: BoxFit.cover),
                      ),
              if (_mediaType == 'video' && _videoReady)
                _isVertical
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoCtrl!.value.size.width,
                          height: _videoCtrl!.value.size.height,
                          child: VideoPlayer(_videoCtrl!),
                        ),
                      )
                    : ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoCtrl!.value.size.width,
                            height: _videoCtrl!.value.size.height,
                            child: VideoPlayer(_videoCtrl!),
                          ),
                        ),
                      ),
              // Foreground centered media (landscape only)
              if (!_isVertical) _buildMediaForeground(),
              // Caption overlay at the bottom of the media
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                  child: TextField(
                    controller: _captionCtrl,
                    maxLength: 200,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ajouter une légende...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.60),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        LucideIcons.pencil,
                        color: Colors.white60,
                        size: 16,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      counterStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaForeground() {
    Widget media;
    if (_mediaType == 'image') {
      media = Image.file(_selectedMedia!, fit: BoxFit.contain);
    } else if (_mediaType == 'video' && _videoReady) {
      media = FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _videoCtrl!.value.size.width,
          height: _videoCtrl!.value.size.height,
          child: VideoPlayer(_videoCtrl!),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Center(child: media);
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
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _storyToolBtn(icon: LucideIcons.type, label: 'Texte', onTap: () {}),
            const SizedBox(height: 12),
            _storyToolBtn(
              icon: LucideIcons.crop,
              label: 'Recadrer',
              onTap: () {},
            ),
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
