import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdfx/pdfx.dart';

class AppPdfViewerPage extends StatefulWidget {
  const AppPdfViewerPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    this.backgroundColor = Colors.white,
    this.appBarColor = Colors.white,
    this.iconColor = const Color(0xFF0F63FF),
    this.titleColor = const Color(0xFF0F172A),
    this.shadowColor = const Color(0x140F63FF),
  });

  final Uint8List pdfBytes;
  final String fileName;
  final Color backgroundColor;
  final Color appBarColor;
  final Color iconColor;
  final Color titleColor;
  final Color shadowColor;

  @override
  State<AppPdfViewerPage> createState() => _AppPdfViewerPageState();
}

class _AppPdfViewerPageState extends State<AppPdfViewerPage> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.pdfBytes),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.backgroundColor,
      appBar: AppBar(
        backgroundColor: widget.appBarColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: widget.iconColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: widget.titleColor,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: widget.shadowColor,
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: PdfViewPinch(
              controller: _controller,
              backgroundDecoration: const BoxDecoration(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
