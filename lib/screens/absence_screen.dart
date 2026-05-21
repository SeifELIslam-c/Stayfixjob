import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'home_screen.dart';

const kAbsenceBlue = Color(0xFF0F63FF);
const kAbsenceDeepBlue = Color(0xFF2563EB);
const kAbsenceDarkBlue = Color(0xFF0047D8);
const kAbsencePageBg = Color(0xFFF7FAFF);
const kAbsenceText = Color(0xFF0F172A);
const kAbsenceMuted = Color(0xFF64748B);
const kAbsenceBorder = Color(0xFFE2E8F0);
const kAbsenceLightBlue = Color(0xFFEFF6FF);
const kAbsenceLightGreen = Color(0xFFECFDF3);
const kAbsenceGreen = Color(0xFF22C55E);
const kAbsenceOrange = Color(0xFFF97316);

class AbsenceScreen extends StatefulWidget {
  const AbsenceScreen({super.key});

  @override
  State<AbsenceScreen> createState() => _AbsenceScreenState();
}

class _AbsenceScreenState extends State<AbsenceScreen> {
  bool? _isAvailable;
  bool _isSaving = false;

  Future<void> _handleBack() async {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance
        .collection('profiles')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get()
        .then((doc) {
          if (!mounted) return;
          setState(() {
            _isAvailable = doc.exists && doc.data()!.containsKey('isAvailable')
                ? doc.data()!['isAvailable'] == true
                : true;
          });
        });
  }

  Future<void> _toggle() async {
    if (_isAvailable == null || _isSaving) return;
    final previous = _isAvailable!;
    final next = !previous;

    setState(() {
      _isAvailable = next;
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'isAvailable': next});
    } catch (e) {
      if (mounted) {
        setState(() => _isAvailable = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _available => _isAvailable ?? true;

  BoxDecoration _whiteCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: kAbsenceBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120F63FF),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  Widget _buildHero() {
    return SizedBox(
      height: 288,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('lib/assets/absenceheroimg.png', fit: BoxFit.cover),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 66),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _handleBack,
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.26),
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.arrowLeft,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Absence',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Repos et voyage',
                    style: TextStyle(
                      color: Colors.white,
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

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kAbsenceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segmentOption(
              selected: _available,
              icon: LucideIcons.briefcase,
              label: 'Disponible',
              selectedBg: kAbsenceLightGreen,
              selectedColor: const Color(0xFF15803D),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _segmentOption(
              selected: !_available,
              icon: LucideIcons.planeTakeoff,
              label: 'En conge / voyage',
              selectedBg: const Color(0xFFFFF4EB),
              selectedColor: kAbsenceOrange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentOption({
    required bool selected,
    required IconData icon,
    required String label,
    required Color selectedBg,
    required Color selectedColor,
  }) {
    return InkWell(
      onTap: _isSaving ? null : (selected ? null : _toggle),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? selectedColor.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? selectedColor : kAbsenceMuted,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? selectedColor : kAbsenceMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusVisual() {
    final accent = _available ? kAbsenceGreen : kAbsenceOrange;
    final bg = _available ? kAbsenceLightGreen : const Color(0xFFFFF4EB);

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(
            _available ? LucideIcons.shieldCheck : LucideIcons.luggage,
            color: accent,
            size: 52,
          ),
          Positioned(
            right: 18,
            bottom: 16,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Icon(
                _available ? LucideIcons.briefcase : LucideIcons.planeTakeoff,
                color: accent,
                size: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: _whiteCardDecoration(),
      child: Column(
        children: [
          _buildSegmentedControl(),
          const SizedBox(height: 24),
          _buildStatusVisual(),
          const SizedBox(height: 22),
          Text(
            _available ? 'Vous etes disponible' : 'Vous etes en conge / voyage',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kAbsenceText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _available
                ? 'Vous pouvez signaler une absence temporaire a tout moment.'
                : 'Votre profil est temporairement indisponible jusqu a votre retour.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kAbsenceMuted,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kAbsenceDeepBlue, kAbsenceBlue],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x240F63FF),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isSaving ? null : _toggle,
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _available
                            ? LucideIcons.briefcase
                            : LucideIcons.rotateCcw,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isSaving
                            ? 'Enregistrement...'
                            : (_available ? 'Signaler absence' : 'Revenir'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        LucideIcons.arrowRight,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: kAbsenceLightBlue,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD6E5FF)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.info, color: kAbsenceBlue, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _available
                        ? 'Votre statut passera en conge jusqu a votre retour.'
                        : 'Reactivez votre disponibilite lorsque vous etes pret a reprendre.',
                    style: const TextStyle(
                      color: kAbsenceText,
                      fontSize: 12.8,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
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

  Widget _buildOverviewRow({
    required IconData icon,
    required String label,
    required Widget value,
    bool divider = true,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: kAbsenceLightBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: kAbsenceBlue, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: kAbsenceText,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            value,
          ],
        ),
        if (divider) ...[
          const SizedBox(height: 14),
          const Divider(color: kAbsenceBorder, height: 1),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildStatusOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apercu du statut',
            style: TextStyle(
              color: kAbsenceText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          _buildOverviewRow(
            icon: LucideIcons.badgeCheck,
            label: 'Statut actuel',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _available ? kAbsenceGreen : kAbsenceOrange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _available ? 'Disponible' : 'En conge / voyage',
                  style: TextStyle(
                    color: _available
                        ? const Color(0xFF15803D)
                        : kAbsenceOrange,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _buildOverviewRow(
            icon: LucideIcons.calendarDays,
            label: 'Retour prevu',
            value: const Text(
              'Non defini',
              style: TextStyle(
                color: kAbsenceMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _buildOverviewRow(
            icon: LucideIcons.bell,
            label: 'Notifications',
            divider: false,
            value: const Text(
              'Desactivees',
              style: TextStyle(
                color: kAbsenceMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAbsencePageBg,
      body: _isAvailable == null
          ? const Center(child: CircularProgressIndicator(color: kAbsenceBlue))
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildHero(),
                  Transform.translate(
                    offset: const Offset(0, -14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Column(
                        children: [
                          _buildStatusCard(),
                          const SizedBox(height: 10),
                          _buildStatusOverviewCard(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
