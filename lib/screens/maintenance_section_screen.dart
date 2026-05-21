import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

const kMaintenanceBlue = Color(0xFF0F63FF);
const kMaintenanceDeepBlue = Color(0xFF0047D8);
const kMaintenanceDarkBlue = Color(0xFF0036B5);
const kMaintenancePageBg = Color(0xFFF7FAFF);
const kMaintenanceText = Color(0xFF0F172A);
const kMaintenanceMuted = Color(0xFF64748B);
const kMaintenanceBorder = Color(0xFFE6EEFF);
const kMaintenanceLightBlue = Color(0xFFEFF6FF);

enum MaintenanceTab { offers, messages }

class MaintenanceSectionScreen extends StatelessWidget {
  final String title;
  final String eyebrow;
  final String description;
  final IconData heroIcon;
  final MaintenanceTab activeTab;
  final VoidCallback onHomeTap;
  final VoidCallback onOffersTap;
  final VoidCallback onMessagesTap;
  final VoidCallback onProfileTap;

  const MaintenanceSectionScreen({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.description,
    required this.heroIcon,
    required this.activeTab,
    required this.onHomeTap,
    required this.onOffersTap,
    required this.onMessagesTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kMaintenancePageBg,
      bottomNavigationBar: _MaintenanceBottomNav(
        activeTab: activeTab,
        onHomeTap: onHomeTap,
        onOffersTap: onOffersTap,
        onMessagesTap: onMessagesTap,
        onProfileTap: onProfileTap,
      ),
      body: Stack(
        children: [
          Container(
            height: 286,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kMaintenanceBlue,
                  kMaintenanceDeepBlue,
                  kMaintenanceDarkBlue,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            left: -28,
            top: 72,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),
          Positioned(
            right: -36,
            top: 24,
            child: Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _HeaderButton(onTap: onHomeTap),
                      const Expanded(
                        child: Text(
                          'STAYFIX JOB',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(34),
                          topRight: Radius.circular(34),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x140F63FF),
                            blurRadius: 24,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  kMaintenanceBlue,
                                  kMaintenanceDeepBlue,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x220F63FF),
                                  blurRadius: 18,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(
                              heroIcon,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: kMaintenanceLightBlue,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              eyebrow,
                              style: const TextStyle(
                                color: kMaintenanceBlue,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: kMaintenanceText,
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: kMaintenanceMuted,
                              fontSize: 14.5,
                              height: 1.55,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FBFF),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: kMaintenanceBorder),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoIcon(),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Cette section sera disponible bientot. Nous preparons une experience simple, propre et rapide pour StayFix Job.',
                                    style: TextStyle(
                                      color: Color(0xFF475569),
                                      fontSize: 13.5,
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    kMaintenanceBlue,
                                    kMaintenanceDeepBlue,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x220F63FF),
                                    blurRadius: 18,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: onHomeTap,
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Retour a l accueil',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
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
                        ],
                      ),
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
}

class _HeaderButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HeaderButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
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
          child: const Icon(
            LucideIcons.chevronLeft,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _InfoIcon extends StatelessWidget {
  const _InfoIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: kMaintenanceLightBlue,
        shape: BoxShape.circle,
      ),
      child: const Icon(LucideIcons.info, color: kMaintenanceBlue, size: 16),
    );
  }
}

class _MaintenanceBottomNav extends StatelessWidget {
  final MaintenanceTab activeTab;
  final VoidCallback onHomeTap;
  final VoidCallback onOffersTap;
  final VoidCallback onMessagesTap;
  final VoidCallback onProfileTap;

  const _MaintenanceBottomNav({
    required this.activeTab,
    required this.onHomeTap,
    required this.onOffersTap,
    required this.onMessagesTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kMaintenanceBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x08071A3D),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: _MaintenanceNavItem(
                  icon: LucideIcons.home,
                  label: 'Accueil',
                  active: false,
                  onTap: onHomeTap,
                ),
              ),
              Expanded(
                child: _MaintenanceNavItem(
                  icon: LucideIcons.briefcase,
                  label: 'Offres',
                  active: activeTab == MaintenanceTab.offers,
                  onTap: onOffersTap,
                ),
              ),
              Expanded(
                child: _MaintenanceNavItem(
                  icon: LucideIcons.messageCircle,
                  label: 'Messages',
                  active: activeTab == MaintenanceTab.messages,
                  onTap: onMessagesTap,
                ),
              ),
              Expanded(
                child: _MaintenanceNavItem(
                  icon: LucideIcons.user,
                  label: 'Profil',
                  active: false,
                  onTap: onProfileTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _MaintenanceNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? kMaintenanceBlue : kMaintenanceMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: active ? 26 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: kMaintenanceBlue,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
