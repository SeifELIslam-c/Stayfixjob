// ignore_for_file: use_super_parameters

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

const _cvPreviewBlue = Color(0xFF0F63FF);
const _cvPreviewText = Color(0xFF0F172A);
const _cvPreviewMuted = Color(0xFF64748B);
const _cvPreviewBorder = Color(0xFFE2E8F0);
const _cvPreviewLightBlue = Color(0xFFEFF6FF);

class CvPreviewCarousel extends StatefulWidget {
  final String cvBase64;
  final String cvFileName;

  const CvPreviewCarousel({
    Key? key,
    required this.cvBase64,
    required this.cvFileName,
  }) : super(key: key);

  @override
  State<CvPreviewCarousel> createState() => _CvPreviewCarouselState();
}

class _CvPreviewCarouselState extends State<CvPreviewCarousel> {
  PdfDocument? _pdfDocument;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLoading = true;
  String? _errorMessage;
  File? _tempFile;

  // Cache of rendered pages: key = 1-based page number, value = decoded image bytes
  final Map<int, Uint8List> _pageCache = {};

  // Tracks whether a page render is in-progress to avoid duplicate renders
  bool _isRenderingPage = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      // Decode Base64 → bytes
      final Uint8List bytes;
      try {
        bytes = base64Decode(widget.cvBase64);
      } on FormatException catch (e) {
        _setError('Erreur d\'affichage du CV: ${e.message}');
        return;
      }

      // Write to temp file
      final tempDir = await getTemporaryDirectory();
      // Sanitise filename so it is safe for the filesystem
      final safeName = widget.cvFileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
      _tempFile = File('${tempDir.path}/$safeName');
      await _tempFile!.writeAsBytes(bytes);

      // Open PDF
      PdfDocument document;
      try {
        document = await PdfDocument.openFile(_tempFile!.path);
      } catch (_) {
        _setError('Impossible d\'ouvrir le fichier PDF');
        return;
      }
      _pdfDocument = document;
      _totalPages = document.pagesCount;

      if (_totalPages == 0) {
        _setError('Le fichier PDF ne contient aucune page');
        return;
      }

      // Pre-render the first page before showing UI
      await _renderPage(1);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _setError('Erreur: ${e.toString()}');
    }
  }

  /// Renders [pageNumber] (1-based) and stores bytes in [_pageCache].
  Future<void> _renderPage(int pageNumber) async {
    if (_pdfDocument == null) return;
    if (pageNumber < 1 || pageNumber > _totalPages) return;

    // Return immediately if already cached
    if (_pageCache.containsKey(pageNumber)) {
      if (mounted) setState(() => _currentPage = pageNumber);
      return;
    }

    if (_isRenderingPage) return;
    _isRenderingPage = true;

    try {
      final page = await _pdfDocument!.getPage(pageNumber);
      try {
        // Render at a higher resolution so text stays readable in the inline preview.
        final media = mounted ? MediaQuery.of(context) : null;
        final double previewWidth = media != null
            ? media.size.width - 72
            : 900.0;
        final double deviceScale = media?.devicePixelRatio ?? 2.0;
        final double renderWidth = previewWidth * deviceScale * 2;

        final PdfPageImage? pageImage = await page.render(
          width: renderWidth,
          height: renderWidth * page.height / page.width,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );

        if (pageImage != null && mounted) {
          setState(() {
            _pageCache[pageNumber] = pageImage.bytes;
            _currentPage = pageNumber;
          });
        }
      } finally {
        await page.close();
      }
    } catch (e) {
      debugPrint('CvPreviewCarousel: error rendering page $pageNumber: $e');
      // Keep _pageCache entry absent so the "Page indisponible" placeholder shows
      if (mounted) setState(() => _currentPage = pageNumber);
    } finally {
      _isRenderingPage = false;
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
    }
  }

  Future<void> _nextPage() async {
    if (_currentPage < _totalPages && !_isRenderingPage) {
      await _renderPage(_currentPage + 1);
    }
  }

  Future<void> _previousPage() async {
    if (_currentPage > 1 && !_isRenderingPage) {
      await _renderPage(_currentPage - 1);
    }
  }

  @override
  void dispose() {
    _pdfDocument?.close();
    try {
      if (_tempFile != null && _tempFile!.existsSync()) {
        _tempFile!.deleteSync();
      }
    } catch (e) {
      debugPrint('CvPreviewCarousel: could not delete temp file: $e');
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build helpers
  // ---------------------------------------------------------------------------

  Widget _buildLoading() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cvPreviewBorder),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: _cvPreviewBlue),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.alertCircle,
            color: Color(0xFFEF4444),
            size: 36,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(color: Color(0xFF991B1B), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPageImage() {
    final bytes = _pageCache[_currentPage];
    if (bytes == null) {
      return Container(
        height: 300,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _cvPreviewLightBlue,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.fileX, color: _cvPreviewMuted, size: 40),
            const SizedBox(height: 10),
            const Text(
              'Page indisponible',
              style: TextStyle(color: _cvPreviewMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        color: const Color(0xFFF8FBFF),
        padding: const EdgeInsets.all(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 420),
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            panEnabled: true,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              width: double.infinity,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 6,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(
          icon,
          color: enabled ? Colors.black : Colors.grey[400],
          size: 20,
        ),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.all(8),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Main build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoading();
    if (_errorMessage != null) return _buildError(_errorMessage!);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cvPreviewBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.fileUp, color: _cvPreviewText, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.cvFileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _cvPreviewText,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(
                LucideIcons.checkCircle2,
                color: _cvPreviewBlue,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ---- Page image or placeholder ----
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey<int>(_currentPage),
                  child:
                      _isRenderingPage && !_pageCache.containsKey(_currentPage)
                      ? const SizedBox(
                          height: 300,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: _cvPreviewBlue,
                            ),
                          ),
                        )
                      : _buildPageImage(),
                ),
              ),
              Positioned(
                left: 10,
                child: _buildNavButton(
                  icon: LucideIcons.arrowLeft,
                  enabled: _currentPage > 1,
                  onPressed: _previousPage,
                ),
              ),
              Positioned(
                right: 10,
                child: _buildNavButton(
                  icon: LucideIcons.arrowRight,
                  enabled: _currentPage < _totalPages,
                  onPressed: _nextPage,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- Page counter ----
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cvPreviewBorder),
            ),
            child: Text(
              '$_currentPage / $_totalPages',
              style: const TextStyle(
                color: _cvPreviewText,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, duration: 300.ms);
  }
}
