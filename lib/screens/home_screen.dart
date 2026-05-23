// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:math' show pi;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'absence_screen.dart';
import 'auth_screen.dart';
import 'availability_screen.dart';
import 'calendar_screen.dart';
import 'clock_screen.dart';
import 'messages_screen.dart';
import 'offers_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import '../models/manager_offer.dart';
import '../services/offers_service.dart';
import '../services/story_service.dart';
import '../services/vps_media_service.dart';
import 'add_worker_story_screen.dart';

const kHomeBlue = Color(0xFF0F63FF);
const kHomeDeepBlue = Color(0xFF0047D8);
const kHomeDarkBlue = Color(0xFF0036B5);
const kHomePageBg = Color(0xFFF7FAFF);
const kHomeText = Color(0xFF0F172A);
const kHomeMuted = Color(0xFF64748B);
const kHomeBorder = Color(0xFFE6EEFF);
const kHomeLightBlue = Color(0xFFEFF6FF);
const kHomeSuccess = Color(0xFF22C55E);
const kHomeUndefinedValue = 'Non défini';

class HomeScreen extends StatefulWidget {
  final bool requireAuth;

  const HomeScreen({super.key, this.requireAuth = true});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const String _undefinedDisplay = 'Non d\u00e9fini';

  bool _isAuthenticated = false;
  String _username = 'Chargement...';
  String _department = '';
  List<String> _specialties = [];
  String? _userPhotoBase64;
  String? _userPhotoUrl;
  bool _isAvailable = false;
  // ── Offers carousel ───────────────────────────────────────────────────────
  final OffersService _offersService = OffersService();
  List<ManagerOffer> _homeOffers = [];
  int _homeOfferPage = 0;
  final PageController _homeOffersController = PageController();

  final _storyService = StoryService();

  @override
  void initState() {
    super.initState();
    _loadUserDataFromFirebase();
    _storyService.cleanupExpiredStories();
    _isAuthenticated = true;
  }

  @override
  void dispose() {
    _homeOffersController.dispose();
    super.dispose();
  }

  String _displayDepartment() {
    if (_department.trim().isEmpty || _department == 'Non dÃ©fini') {
      return _undefinedDisplay;
    }
    return _normalizeLegacyFrenchText(_department);
  }

  // ignore: unused_element
  String _displayPrimarySpecialty() {
    if (_specialties.isNotEmpty) return _specialties.first;
    return 'Aucune compÃ©tence sÃ©lectionnÃ©e';
  }

  String _normalizeLegacyFrenchText(String value) {
    return value
        .replaceAll('Non dÃƒÆ’Ã‚Â©fini', 'Non défini')
        .replaceAll('Non dÃƒÂ©fini', 'Non défini')
        .replaceAll('Non dÃ©fini', 'Non défini')
        .replaceAll('Non dÂ©fini', 'Non défini')
        .replaceAll('MÃƒÆ’Ã‚Â©nage', 'Ménage')
        .replaceAll('MÃƒÂ©nage', 'Ménage')
        .replaceAll('MÃ©nage', 'Ménage')
        .replaceAll(
          'Aucune compÃƒÆ’Ã‚Â©tence sÃƒÆ’Ã‚Â©lectionnÃƒÆ’Ã‚Â©e',
          'Aucune compétence sélectionnée',
        )
        .replaceAll(
          'Aucune compÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©tence sÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©lectionnÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©e',
          'Aucune compétence sélectionnée',
        )
        .replaceAll(
          'Aucune compÃ©tence sÃ©lectionnÃ©e',
          'Aucune compétence sélectionnée',
        )
        .replaceAll('ComplÃƒÆ’Ã‚Â©tez', 'Complétez')
        .replaceAll('ComplÃƒÂ©tez', 'Complétez')
        .replaceAll('ComplÃ©tez', 'Complétez')
        .replaceAll('ComplÃƒÆ’Ã‚Â©ter', 'Compléter')
        .replaceAll('ComplÃ©ter', 'Compléter')
        .replaceAll('dÃƒÆ’Ã‚Â©tails', 'détails')
        .replaceAll('dÃƒÂ©tails', 'détails')
        .replaceAll('dÃ©tails', 'détails')
        .replaceAll('dÃƒÆ’Ã‚Â©partement', 'département')
        .replaceAll('dÃƒÂ©partement', 'département')
        .replaceAll('dÃ©partement', 'département')
        .replaceAll('disponibilitÃƒÆ’Ã‚Â©', 'disponibilité')
        .replaceAll('disponibilitÃƒÂ©', 'disponibilité')
        .replaceAll('disponibilitÃ©', 'disponibilité')
        .replaceAll('rÃƒÆ’Ã‚Â´le', 'rôle')
        .replaceAll('rÃƒÂ´le', 'rôle')
        .replaceAll('rÃ´le', 'rôle')
        .replaceAll('ParamÃ¨tres', 'Paramètres')
        .replaceAll('DisponibilitÃ©', 'Disponibilité')
        .replaceAll('DisponibilitÃƒÂ©', 'Disponibilité')
        .replaceAll('SYSTÃˆME', 'SYSTÈME')
        .replaceAll('Date de dÃ©but', 'Date de début')
        .replaceAll('â€™', "'")
        .replaceAll('ðŸ‘‹', '')
        .replaceAll('Ã©', 'é')
        .replaceAll('Ã¨', 'è')
        .replaceAll('Ãª', 'ê')
        .replaceAll('Ã ', 'à')
        .replaceAll('Ã§', 'ç')
        .replaceAll('Â©', 'é');
  }

  String _resolvedDepartmentLabel() {
    final department = _normalizeLegacyFrenchText(_department).trim();
    if (department.isEmpty || department == _undefinedDisplay) {
      return _undefinedDisplay;
    }
    return department;
  }

  List<String> _uniqueSpecialties(Iterable<dynamic> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final specialty = value.toString().trim();
      if (specialty.isEmpty || !seen.add(specialty)) continue;
      result.add(specialty);
    }
    return result;
  }

  List<String> _displaySpecialties() {
    final specialties = _specialties
        .map(_normalizeLegacyFrenchText)
        .where((specialty) => specialty.trim().isNotEmpty)
        .toList();
    if (specialties.isEmpty) return ['Aucune compétence sélectionnée'];
    return specialties;
  }

  Future<void> _loadUserDataFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docSnapshot = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .get();
        if (docSnapshot.exists) {
          final data = docSnapshot.data()!;
          if (mounted) {
            setState(() {
              _username = data['username'] ?? 'Utilisateur';
              _department = _normalizeLegacyFrenchText(
                data['department'] ?? _undefinedDisplay,
              );
              _specialties = _uniqueSpecialties(
                data['specialties'] ?? [],
              ).map(_normalizeLegacyFrenchText).toList();
              _userPhotoBase64 = data['photoBase64'];
              _userPhotoUrl = VpsMediaService.resolveProfileImageUrl(data);
              _isAvailable = data['isAvailable'] == true;
            });
          }
        }
      }
      // Load carousel offers once department is known
      if (_department.isNotEmpty) _loadHomeOffers();
    } catch (e) {
      debugPrint('Erreur chargement Home: $e');
    }
  }

  Future<void> _loadHomeOffers() async {
    try {
      final offers = await _offersService.loadOffersForWorker(_department);
      if (mounted) {
        setState(() => _homeOffers = offers.take(8).toList());
      }
    } catch (e) {
      debugPrint('Erreur chargement offres home: $e');
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    ).then((_) => _loadUserDataFromFirebase());
  }

  void _openCompletionProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(completionMode: true),
      ),
    ).then((_) => _loadUserDataFromFirebase());
  }

  void _openOffers() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OffersScreen()),
    );
  }

  void _openMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MessagesScreen()),
    );
  }

  ImageProvider? _buildAvatarImage() {
    if (_userPhotoUrl?.isNotEmpty == true) {
      return NetworkImage(_userPhotoUrl!);
    }
    if (_userPhotoBase64 == null || _userPhotoBase64!.isEmpty) return null;
    return MemoryImage(base64Decode(_userPhotoBase64!));
  }

  Widget _buildAvatar({double radius = 34}) {
    final image = _buildAvatarImage();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x804BC0FF), width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x220E5CFF),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: Colors.white.withValues(alpha: 0.16),
            backgroundImage: image,
            child: image == null
                ? Icon(
                    Icons.engineering_rounded,
                    color: Colors.white,
                    size: radius,
                  )
                : null,
          ),
        ),
        Positioned(
          right: 2,
          bottom: 4,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: kHomeSuccess,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.2),
            ),
          ),
        ),
      ],
    );
  }

  // ── Offers carousel ───────────────────────────────────────────────────────

  Widget _buildOffersCarousel() {
    if (_homeOffers.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kHomeBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140B2A66),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.briefcase, color: kHomeLightBlue, size: 28),
              SizedBox(height: 8),
              Text(
                'Aucune offre disponible',
                style: TextStyle(
                  color: kHomeMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _homeOffersController,
            itemCount: _homeOffers.length,
            onPageChanged: (i) => setState(() => _homeOfferPage = i),
            itemBuilder: (ctx, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _buildHomeOfferCard(_homeOffers[i]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildCarouselDots(_homeOffers.length),
      ],
    );
  }

  Widget _buildHomeOfferCard(ManagerOffer offer) {
    final hasImage = offer.condoImageBase64?.isNotEmpty == true;
    ImageProvider? bgImage;
    if (hasImage) {
      try {
        bgImage = MemoryImage(base64Decode(offer.condoImageBase64!));
      } catch (_) {}
    }

    final urgencyLabel = switch (offer.urgency) {
      OfferUrgency.veryUrgent => 'Très urgent',
      OfferUrgency.urgent => 'Urgent',
      OfferUrgency.high => 'Prioritaire',
      OfferUrgency.normal => null,
    };

    return GestureDetector(
      onTap: _openOffers,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x280B2A66),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background image or gradient
              if (bgImage != null)
                Image(image: bgImage, fit: BoxFit.cover)
              else
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kHomeBlue, kHomeDeepBlue, kHomeDarkBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              // Gradient overlay
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                    stops: [0.35, 1.0],
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Urgency badge top-right
                    if (urgencyLabel != null)
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            urgencyLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    // Title
                    Text(
                      offer.title.isNotEmpty ? offer.title : 'Offre sans titre',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Condo name
                    Text(
                      offer.condoName.isNotEmpty
                          ? offer.condoName
                          : 'Condo non renseigné',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Meta row
                    Row(
                      children: [
                        if (offer.condoAddress?.isNotEmpty == true)
                          _offerChip(
                            LucideIcons.mapPin,
                            offer.condoAddress!.split(',').first,
                          ),
                        if (offer.condoAddress?.isNotEmpty == true)
                          const SizedBox(width: 6),
                        _offerChip(LucideIcons.wrench, offer.specialty),
                        const Spacer(),
                        // Price
                        Text(
                          '${offer.budgetAmount.toStringAsFixed(0)} ${offer.budgetCurrency}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _offerChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselDots(int count) {
    final dots = count.clamp(0, 5);
    if (dots <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(dots, (i) {
        final active = i == _homeOfferPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? kHomeBlue : kHomeBorder,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  // ── Story entry ───────────────────────────────────────────────────────────

  void _openStoryEditor() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _specialties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complétez votre profil avant de publier une story.'),
        ),
      );
      return;
    }
    final profile = WorkerProfile(
      uid: uid,
      username: _username,
      department: _department,
      specialties: _specialties,
      isAvailable: _isAvailable,
      photoBase64: _userPhotoBase64,
      photoUrl: _userPhotoUrl,
      address: '',
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddWorkerStoryScreen(profile: profile)),
    );
  }

  Widget _buildStoryAddButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openStoryEditor,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(LucideIcons.camera, color: Colors.white, size: 20),
              Positioned(
                right: 9,
                top: 9,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: kHomeBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero header ───────────────────────────────────────────────────────────

  Widget _buildHeroHeader() {
    return SizedBox(
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/assets/homepageimghero.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kHomeBlue, kHomeDeepBlue, kHomeDarkBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -30,
            child: Container(
              width: 180,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(120),
              ),
            ),
          ),
          Positioned(
            right: -32,
            bottom: 10,
            child: Container(
              width: 220,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(120),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _scaffoldKey.currentState?.openDrawer(),
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: const Icon(
                              LucideIcons.menu,
                              color: Colors.white,
                              size: 21,
                            ),
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'ACCUEIL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3.2,
                            ),
                          ),
                        ),
                      ),
                      _buildStoryAddButton(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      StreamBuilder<List<WorkerStory>>(
                        stream: _storyService.watchOwnActiveStories(),
                        builder: (ctx, snap) {
                          final stories = snap.data ?? [];
                          if (stories.isEmpty) {
                            return _buildAvatar()
                                .animate()
                                .fadeIn(duration: 350.ms)
                                .scale(begin: const Offset(0.9, 0.9));
                          }
                          final story = stories.first;
                          return GestureDetector(
                                onTap: () => Navigator.of(ctx).push(
                                  PageRouteBuilder(
                                    pageBuilder: (c, a1, a2) =>
                                        _WorkerStoryViewerScreen(
                                          story: story,
                                          storyService: _storyService,
                                        ),
                                    transitionsBuilder: (c, anim, a2, child) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: child,
                                        ),
                                    transitionDuration: const Duration(
                                      milliseconds: 220,
                                    ),
                                  ),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    _AnimatedStoryRing(
                                      child: CircleAvatar(
                                        radius: 34,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.16),
                                        backgroundImage: _buildAvatarImage(),
                                        child: _buildAvatarImage() == null
                                            ? const Icon(
                                                Icons.engineering_rounded,
                                                color: Colors.white,
                                                size: 34,
                                              )
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      right: 2,
                                      bottom: 4,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: kHomeSuccess,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .animate()
                              .fadeIn(duration: 350.ms)
                              .scale(begin: const Offset(0.9, 0.9));
                        },
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bonjour,',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.94),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                height: 1.12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Content de vous revoir !',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.76),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialtyCard() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kHomeLightBlue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  LucideIcons.wrench,
                  color: kHomeBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: kHomeLightBlue,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'VOTRE SPÉCIALITÉ',
                      style: TextStyle(
                        color: kHomeBlue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              _CircleActionButton(
                icon: LucideIcons.chevronRight,
                onTap: _openProfile,
                size: 38,
                iconSize: 17,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _resolvedDepartmentLabel(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kHomeText,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.35,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Align(
                alignment: Alignment.topLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _displaySpecialties().map((specialty) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: kHomeLightBlue,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        specialty,
                        style: const TextStyle(
                          color: kHomeBlue,
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCompleteProfileBannerLegacy() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kHomeBlue, kHomeDeepBlue],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240F63FF),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              LucideIcons.shieldCheck,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complétez votre profil',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Ajoutez plus de dÃ©tails pour augmenter vos chances d'obtenir des offres.",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _openProfile,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kHomeBlue,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Compléter',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                SizedBox(width: 6),
                Icon(LucideIcons.arrowRight, size: 15),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteProfileBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kHomeBlue, kHomeDeepBlue],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240F63FF),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              LucideIcons.shieldCheck,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complétez votre profil',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Modifiez votre département, votre rôle et votre disponibilité à tout moment.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _openCompletionProfile,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kHomeBlue,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Compléter',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                SizedBox(width: 6),
                Icon(LucideIcons.arrowRight, size: 15),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kHomeBorder)),
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
                child: _BottomNavItem(
                  icon: LucideIcons.home,
                  label: 'Accueil',
                  active: true,
                  onTap: () {},
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.briefcase,
                  label: 'Offres',
                  active: false,
                  onTap: _openOffers,
                ),
              ),
              Expanded(
                child: _HomeMessagesNavItem(
                  uid: uid,
                  onTap: _openMessages,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.user,
                  label: 'Profil',
                  active: false,
                  onTap: _openProfile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return const Scaffold(
        backgroundColor: kHomePageBg,
        body: Center(child: CircularProgressIndicator(color: kHomeBlue)),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kHomePageBg,
      drawer: _buildModernDrawer(context),
      bottomNavigationBar: _buildBottomNavBar(),
      body: Stack(
        children: [
          _buildHeroHeader(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 170, 20, 10),
              child: Column(
                children: [
                  _buildCompleteProfileBanner()
                      .animate()
                      .fadeIn(duration: 280.ms)
                      .slideY(begin: 0.04, duration: 280.ms),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _buildOffersCarousel()
                        .animate()
                        .fadeIn(delay: 100.ms, duration: 280.ms)
                        .slideY(begin: 0.04, duration: 280.ms),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 155,
                    child: _buildSpecialtyCard()
                        .animate()
                        .fadeIn(delay: 200.ms, duration: 280.ms)
                        .slideY(begin: 0.04, duration: 280.ms),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      width: 318,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x180F63FF),
              blurRadius: 30,
              offset: Offset(12, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kHomeBlue, kHomeDeepBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Menu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(14),
                            child: Ink(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(
                                LucideIcons.x,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _buildAvatar(radius: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _displayDepartment(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAFF),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kHomeBorder),
                      ),
                      child: Column(
                        children: [
                          _modernDrawerItem(
                            icon: LucideIcons.home,
                            title: 'Accueil',
                            isActive: true,
                            onTap: () => Navigator.pop(context),
                            delay: 80,
                          ),
                          _modernDrawerItem(
                            icon: LucideIcons.user,
                            title: 'Mon Profil',
                            delay: 110,
                            onTap: () {
                              Navigator.pop(context);
                              _openProfile();
                            },
                          ),
                          _modernDrawerItem(
                            icon: LucideIcons.calendarDays,
                            title: 'Calendrier',
                            delay: 140,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CalendarScreen(),
                                ),
                              );
                            },
                          ),
                          _modernDrawerItem(
                            icon: LucideIcons.plane,
                            title: 'Absence',
                            delay: 170,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AbsenceScreen(),
                                ),
                              );
                            },
                          ),
                          _modernDrawerItem(
                            icon: LucideIcons.clock,
                            title: 'Horloge',
                            delay: 200,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ClockScreen(),
                                ),
                              );
                            },
                          ),
                          _modernDrawerItem(
                            icon: LucideIcons.calendarCheck,
                            title: 'Disponibilité',
                            delay: 230,
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AvailabilityScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 8),
                      child: Text(
                        'SYSTÈME',
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 11,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _modernDrawerItem(
                      icon: LucideIcons.settings,
                      title: 'Paramètres',
                      delay: 260,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFED7D7)),
                      ),
                      child: _modernDrawerItem(
                        icon: LucideIcons.logOut,
                        title: 'Fermeture de session',
                        isDestructive: true,
                        delay: 290,
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          await FirebaseAuth.instance.signOut();
                          if (context.mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AuthScreen(),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modernDrawerItem({
    required IconData icon,
    required String title,
    bool isActive = false,
    bool isDestructive = false,
    VoidCallback? onTap,
    required int delay,
  }) {
    final textColor = isDestructive
        ? const Color(0xFFEF4444)
        : isActive
        ? kHomeBlue
        : kHomeText;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: isActive ? kHomeLightBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : const Color(0xFFF3F7FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: textColor, size: 19),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: delay.ms).slideX(begin: -0.08, duration: 220.ms);
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kHomeBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B2A66),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WorkerStoryViewerScreen extends StatefulWidget {
  const _WorkerStoryViewerScreen({
    required this.story,
    required this.storyService,
  });

  final WorkerStory story;
  final StoryService storyService;

  @override
  State<_WorkerStoryViewerScreen> createState() =>
      _WorkerStoryViewerScreenState();
}

class _WorkerStoryViewerScreenState extends State<_WorkerStoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..forward();
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.pop(context);
      }
    });
    widget.storyService.recordStoryView(
      storyId: widget.story.id,
      ownerUid: widget.story.ownerUid,
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _showDeleteStorySheet() async {
    _progress.stop();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7E4FF),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  LucideIcons.trash2,
                  color: Color(0xFFDC2626),
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Supprimer la story ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kHomeText,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Cette story sera supprimee definitivement. Cette action est irreversible.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kHomeMuted,
                  height: 1.45,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kHomeBlue,
                        side: const BorderSide(color: Color(0xFFBDD5FF)),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Supprimer',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _progress.forward();
      return;
    }
    setState(() => _isDeleting = true);
    try {
      await widget.storyService.deleteStory(
        storyId: widget.story.id,
        fileId: widget.story.fileId,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ignore: unused_element
  Future<void> _confirmDelete() async {
    _progress.stop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Supprimer la story ?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: const Text(
          'Cette story sera supprimée définitivement. Cette action est irréversible.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Color(0xFFEF4444)),
            child: const Text(
              'Supprimer',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _progress.forward();
      return;
    }
    setState(() => _isDeleting = true);
    try {
      await widget.storyService.deleteStory(
        storyId: widget.story.id,
        fileId: widget.story.fileId,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (_) => _progress.stop(),
        onTapUp: (_) => _progress.forward(),
        onTapCancel: () => _progress.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Media ────────────────────────────────────────────────────────
            story.isVideo
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.playCircle,
                          color: Colors.white54,
                          size: 64,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Story vidéo',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                : Image.network(
                    story.mediaUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 2,
                            ),
                          ),
                    errorBuilder: (ctx, e, st) => const Center(
                      child: Icon(
                        LucideIcons.imageOff,
                        color: Colors.white30,
                        size: 52,
                      ),
                    ),
                  ),

            // ── Top gradient ─────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.70),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom gradient ──────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Top overlay: progress + user info + buttons ──────────────────
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (ctx, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _progress.value,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white,
                          ),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // User info row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF0F63FF), Color(0xFF6366F1)],
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.white24,
                            backgroundImage: story.ownerPhotoUrl.isNotEmpty
                                ? NetworkImage(story.ownerPhotoUrl)
                                : null,
                            child: story.ownerPhotoUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                story.ownerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (story.expiresAt != null)
                                Text(
                                  'Expire le ${DateFormat('dd/MM à HH:mm').format(story.expiresAt!.toLocal())}',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Delete button
                        _isDeleting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : GestureDetector(
                                onTap: _showDeleteStorySheet,
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    LucideIcons.trash2,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                ),
                              ),
                        const SizedBox(width: 8),
                        // Close button
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom overlay: views + caption ─────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.eye,
                            color: Colors.white70,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${story.viewCount} vue${story.viewCount != 1 ? 's' : ''}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (story.caption.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          story.caption,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
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

class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const _CircleActionButton({
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F8FF),
            shape: BoxShape.circle,
            border: Border.all(color: kHomeBorder),
          ),
          child: Icon(icon, color: kHomeBlue, size: iconSize),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? kHomeBlue : const Color(0xFF7A859E);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 26 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: kHomeBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeMessagesNavItem extends StatelessWidget {
  const _HomeMessagesNavItem({required this.uid, required this.onTap});

  final String uid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF7A859E);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: uid.isEmpty
                    ? const Stream.empty()
                    : FirebaseFirestore.instance
                          .collection('conversations')
                          .where('participants', arrayContains: uid)
                          .snapshots(),
                builder: (context, snapshot) {
                  bool hasUnread = false;
                  if (snapshot.hasData) {
                    hasUnread = snapshot.data!.docs.any((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final unreadBy =
                          data['unreadBy'] as Map<String, dynamic>? ?? {};
                      return (unreadBy[uid] ?? 0) > 0;
                    });
                  }
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        LucideIcons.messageCircle,
                        color: color,
                        size: 22,
                      ),
                      if (hasUnread)
                        Positioned(
                          top: -2,
                          right: -4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF3B30),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              const Text(
                'Messages',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 0,
                height: 3,
                decoration: const BoxDecoration(
                  color: kHomeBlue,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animated Instagram-style story ring ──────────────────────────────────────

class _AnimatedStoryRing extends StatefulWidget {
  const _AnimatedStoryRing({required this.child});
  final Widget child;

  @override
  State<_AnimatedStoryRing> createState() => _AnimatedStoryRingState();
}

class _AnimatedStoryRingState extends State<_AnimatedStoryRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, child) => CustomPaint(
        painter: _StoryRingPainter(rotation: _ctrl.value * 2 * pi),
        child: Padding(padding: const EdgeInsets.all(5), child: child),
      ),
      child: widget.child,
    );
  }
}

class _StoryRingPainter extends CustomPainter {
  const _StoryRingPainter({required this.rotation});
  final double rotation;

  static const _colors = [
    Color(0xFFF58529), // orange
    Color(0xFFDD2A7B), // hot pink
    Color(0xFF8134AF), // purple
    Color(0xFF515BD4), // blue
    Color(0xFFF58529), // seamless wrap
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2.5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = SweepGradient(
        colors: _colors,
        transform: GradientRotation(rotation),
      ).createShader(rect)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_StoryRingPainter old) => old.rotation != rotation;
}
