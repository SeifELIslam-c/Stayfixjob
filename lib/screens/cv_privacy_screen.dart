import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const kCvBlue = Color(0xFF0F63FF);
const kCvDeepBlue = Color(0xFF2563EB);
const kCvDarkBlue = Color(0xFF0047D8);
const kCvPageBg = Color(0xFFF7FAFF);
const kCvText = Color(0xFF0F172A);
const kCvBody = Color(0xFF475569);
const kCvMuted = Color(0xFF64748B);
const kCvBorder = Color(0xFFE2E8F0);
const kCvLightBlue = Color(0xFFEFF6FF);
const kCvSuccess = Color(0xFF22C55E);
const kCvError = Color(0xFFEF4444);

class CvPrivacyScreen extends StatefulWidget {
  final VoidCallback onUploadComplete;

  const CvPrivacyScreen({super.key, required this.onUploadComplete});

  @override
  State<CvPrivacyScreen> createState() => _CvPrivacyScreenState();
}

class _CvPrivacyScreenState extends State<CvPrivacyScreen> {
  XFile? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;
  bool? _reviewAuthorizationAccepted;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingCvState();
  }

  Future<void> _loadExistingCvState() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .get();

      if (!doc.exists || !mounted) return;

      final data = doc.data()!;
      final questionnaire = data['cvQuestionnaire'];
      final cvReviewAuthorization = data['cvReviewAuthorization'];

      setState(() {
        _selectedFileName = data['cvFileName'] as String?;
        _reviewAuthorizationAccepted = cvReviewAuthorization is bool
            ? cvReviewAuthorization
            : questionnaire is Map<String, dynamic>
            ? questionnaire['privacyAccepted'] as bool?
            : null;
      });
    } catch (e) {
      debugPrint('Erreur chargement etat CV: $e');
    }
  }

  Future<void> _selectPdf() async {
    final typeGroup = XTypeGroup(label: 'PDF', extensions: const ['pdf']);
    final xFile = await openFile(acceptedTypeGroups: [typeGroup]);

    if (xFile == null) return;

    final size = await xFile.length();

    if (!xFile.name.toLowerCase().endsWith('.pdf')) {
      _snack('Seuls les fichiers PDF sont acceptes.', isError: true);
      return;
    }

    if (size > 2 * 1024 * 1024) {
      _snack('Le fichier est trop volumineux (max 2 Mo).', isError: true);
      return;
    }

    setState(() {
      _selectedFile = xFile;
      _selectedFileName = xFile.name;
      _selectedFileSize = size;
    });
  }

  void _onBack() {
    Navigator.pop(context);
  }

  bool _canSubmit() {
    return _selectedFile != null && _reviewAuthorizationAccepted != null;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  }

  Future<void> _submitCV() async {
    if (_selectedFile == null) {
      _snack('Veuillez selectionner un fichier PDF.', isError: true);
      return;
    }
    if (_reviewAuthorizationAccepted == null) {
      _snack(
        'Veuillez choisir Accepter ou Refuser avant de soumettre.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fileSize = await _selectedFile!.length();
      if (fileSize > 2 * 1024 * 1024) {
        _snack('Le fichier est trop volumineux (max 2 Mo).', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      final bytes = await _selectedFile!.readAsBytes();
      final base64String = base64Encode(bytes);
      final user = FirebaseAuth.instance.currentUser!;
      final profileRef = FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid);
      final existingDoc = await profileRef.get();
      final existingData = existingDoc.data() ?? <String, dynamic>{};
      final existingQuestionnaire =
          (existingData['cvQuestionnaire'] as Map<String, dynamic>?) ?? {};

      await profileRef.set({
        'cvBase64': base64String,
        'cvFileName':
            _selectedFileName ??
            _selectedFile!.name,
        'cvReviewAuthorization': _reviewAuthorizationAccepted,
        'cvQuestionnaire': {
          ...existingQuestionnaire,
          'privacyAccepted': _reviewAuthorizationAccepted,
          'submittedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF18181B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: kCvSuccess.withValues(alpha: 0.5)),
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          content: const Row(
            children: [
              Icon(LucideIcons.checkCircle, color: kCvSuccess),
              SizedBox(width: 12),
              Text(
                'CV televerse avec succes !',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      widget.onUploadComplete();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _snack("Erreur lors de l'envoi: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  BoxDecoration _whiteCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(34),
      border: Border.all(color: kCvBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x140F63FF),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    );
  }

  Widget _heroButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('lib/assets/monprofileimghero.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xD90F63FF),
                  Color(0xD92563EB),
                  Color(0xD90047D8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            right: -34,
            top: 0,
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            left: -26,
            bottom: -16,
            child: Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      _heroButton(icon: LucideIcons.arrowLeft, onTap: _onBack),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: const Icon(
                      LucideIcons.fileText,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 64,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Televersement du CV',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ajoutez votre CV pour completer votre candidature',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadBox() {
    final hasFile = _selectedFileName != null;

    return InkWell(
      onTap: _selectPdf,
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
        decoration: BoxDecoration(
          color: kCvLightBlue,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: hasFile ? kCvBlue : kCvBlue.withValues(alpha: 0.65),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              child: Icon(
                hasFile ? LucideIcons.fileCheck2 : LucideIcons.uploadCloud,
                color: hasFile ? kCvSuccess : kCvBlue,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            if (hasFile) ...[
              Text(
                _selectedFileName!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kCvText,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_selectedFileSize != null) ...[
                const SizedBox(height: 6),
                Text(
                  _formatBytes(_selectedFileSize!),
                  style: const TextStyle(
                    color: kCvMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.refreshCcw, color: kCvBlue, size: 15),
                    SizedBox(width: 8),
                    Text(
                      'Remplacer le fichier',
                      style: TextStyle(
                        color: kCvBlue,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Text(
                'Appuyer pour selectionner un PDF',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kCvBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorizationOption({
    required String label,
    required bool value,
  }) {
    final isSelected = _reviewAuthorizationAccepted == value;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _reviewAuthorizationAccepted = value),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: isSelected ? kCvLightBlue : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected ? kCvBlue : kCvBorder,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? kCvBlue : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? kCvBlue : const Color(0xFF94A3B8),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? kCvBlue : kCvText,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons() {
    final canSubmit = _canSubmit() && !_isLoading;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _onBack,
            icon: const Icon(LucideIcons.arrowLeft, size: 18),
            label: const Text('Precedent'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kCvBlue,
              side: const BorderSide(color: kCvBlue),
              minimumSize: const Size.fromHeight(58),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              textStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: canSubmit
                  ? const LinearGradient(
                      colors: [kCvBlue, kCvDeepBlue],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFFDCE8FF), Color(0xFFD6E3FB)],
                    ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: canSubmit
                  ? const [
                      BoxShadow(
                        color: Color(0x260F63FF),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : const [],
            ),
            child: ElevatedButton.icon(
              onPressed: canSubmit ? _submitCV : null,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 18),
              label: const Text('Soumettre mon CV'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                disabledForegroundColor: const Color(0xFF8CA0C4),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainCard() {
    return Container(
      decoration: _whiteCardDecoration(),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ajoutez votre CV',
            style: TextStyle(
              color: kCvText,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Format PDF uniquement - taille maximale 2 Mo.',
            style: TextStyle(
              color: kCvMuted,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          _buildUploadBox(),
          const SizedBox(height: 22),
          const Divider(color: kCvBorder, height: 1),
          const SizedBox(height: 22),
          const Text(
            'Autorisation de revision',
            style: TextStyle(
              color: kCvText,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Acceptez-vous que votre CV soit examine par les responsables ?',
            style: TextStyle(
              color: kCvMuted,
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildAuthorizationOption(label: 'Accepter', value: true),
              const SizedBox(width: 12),
              _buildAuthorizationOption(label: 'Refuser', value: false),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: kCvLightBlue,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD6E5FF)),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.info, color: kCvBlue, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cette autorisation est necessaire pour soumettre votre CV.',
                    style: TextStyle(
                      color: kCvBody,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCvPageBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHero(),
            Transform.translate(
              offset: const Offset(0, -46),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: _buildMainCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
