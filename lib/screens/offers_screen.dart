import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons_flutter.dart';

import '../models/manager_offer.dart';
import '../services/offers_service.dart';
import 'create_worker_offer_screen.dart';
import 'home_screen.dart';
import 'messages_screen.dart';
import 'offer_detail_screen.dart';
import 'profile_screen.dart';

// ── Color palette (identical to original — constants keep same names) ──────────
const kOffersBlue = Color(0xFF0F63FF);
const kOffersDeepBlue = Color(0xFF0047D8);
const kOffersDarkBlue = Color(0xFF0036B5);
const kOffersPageBg = Color(0xFFF7FAFF);
const kOffersText = Color(0xFF0F172A);
const kOffersMuted = Color(0xFF64748B);
const kOffersBorder = Color(0xFFE6EEFF);
const kOffersLightBlue = Color(0xFFEFF6FF);
const kOffersSuccess = Color(0xFF16A34A);
const kOffersWarning = Color(0xFFF59E0B);

// ── Main screen ───────────────────────────────────────────────────────────────

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final OffersService _service = OffersService();
  final TextEditingController _searchController = TextEditingController();

  WorkerProfile? _profile;
  List<ManagerOffer> _allOffers = [];
  Set<String> _appliedIds = {};
  String? _errorMessage;
  bool _isLoading = true;

  // ── Tab state ─────────────────────────────────────────────────────────────
  int _activeTab = 0; // 0 = Offres disponibles, 1 = Mes offres
  List<ManagerOffer> _myOffers = [];
  List<WorkerOffer> _myPublishedOffers = [];
  bool _myOffersLoading = false;
  bool _nearMeOnly = false;

  String _activeChip = 'Toutes';
  int _carouselPage = 0;
  final PageController _carouselController = PageController();

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadMyOffers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _carouselController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final profile = await _service.loadWorkerProfile();
      if (profile == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Profil introuvable. Veuillez compléter votre profil.';
          });
        }
        return;
      }

      final results = await Future.wait([
        _service.loadOffersForWorker(
          profile.department,
          nearMeOnly: _nearMeOnly,
          originLatitude: profile.addressLatitude,
          originLongitude: profile.addressLongitude,
        ),
        _service.loadAppliedOfferIds(),
      ]);

      if (mounted) {
        setState(() {
          _profile = profile;
          _allOffers = results[0] as List<ManagerOffer>;
          _appliedIds = results[1] as Set<String>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erreur de chargement : $e';
        });
      }
    }
  }

  Future<void> _loadMyOffers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _myOffersLoading = true);
    try {
      final results = await Future.wait([
        _service.loadMyAssignedOffers(uid),
        _service.loadMyPublishedOffers(),
      ]);
      if (mounted) {
        setState(() {
          _myOffers = results[0] as List<ManagerOffer>;
          _myPublishedOffers = results[1] as List<WorkerOffer>;
          _myOffersLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _myOffersLoading = false);
    }
  }

  // ── Derived lists ─────────────────────────────────────────────────────────

  List<ManagerOffer> get _filteredOffers {
    final query = _searchController.text.trim().toLowerCase();
    final profile = _profile;

    return _allOffers.where((offer) {
      // Specialty chip filter
      final matchesChip =
          _activeChip == 'Toutes' ||
          offer.specialty.toLowerCase() == _activeChip.toLowerCase();

      // Client-side specialty filter — worker must hold this specialty
      final matchesWorkerSpecialty =
          profile == null ||
          profile.specialties.isEmpty ||
          profile.specialties.any(
            (s) => s.toLowerCase() == offer.specialty.toLowerCase(),
          );

      // Text search
      final matchesSearch =
          query.isEmpty ||
          offer.title.toLowerCase().contains(query) ||
          offer.condoName.toLowerCase().contains(query) ||
          (offer.condoAddress?.toLowerCase().contains(query) ?? false) ||
          offer.description.toLowerCase().contains(query) ||
          offer.specialty.toLowerCase().contains(query);

      return matchesChip && matchesWorkerSpecialty && matchesSearch;
    }).toList();
  }

  List<ManagerOffer> get _urgentOffers =>
      _filteredOffers.where((o) => o.isUrgent).toList();

  // ── Mes offres grouping ───────────────────────────────────────────────────

  /// Parses French date strings such as "20 Mai 2025", "Aujourd'hui", "Demain",
  /// or ISO "yyyy-MM-dd" into a DateTime. Returns null if unparseable.
  DateTime? _parseRequestedDate(String raw) {
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase().trim();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (lower == "aujourd'hui") return today;
    if (lower == 'demain') return today.add(const Duration(days: 1));
    try {
      return DateTime.parse(raw);
    } catch (_) {}
    try {
      return DateFormat('d MMM yyyy', 'fr').parse(raw);
    } catch (_) {}
    try {
      return DateFormat('dd MMM yyyy', 'fr').parse(raw);
    } catch (_) {}
    return null;
  }

  DateTime get _tomorrow {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 1);
  }

  List<ManagerOffer> get _enCours => _myOffers.where((o) {
    if (o.status != OfferStatus.assigned) return false;
    final d = _parseRequestedDate(o.requestedDate);
    if (d == null) return true;
    return d.isBefore(_tomorrow);
  }).toList();

  List<ManagerOffer> get _aVenir => _myOffers.where((o) {
    if (o.status != OfferStatus.assigned) return false;
    final d = _parseRequestedDate(o.requestedDate);
    if (d == null) return false;
    return !d.isBefore(_tomorrow);
  }).toList();

  List<ManagerOffer> get _terminees =>
      _myOffers.where((o) => o.status == OfferStatus.completed).toList();

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openHome() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
  );

  void _openMessages() => Navigator.of(
    context,
  ).pushReplacement(MaterialPageRoute(builder: (_) => const MessagesScreen()));

  void _openProfile() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));

  Future<void> _openCreateOffer() async {
    final profile = _profile;
    if (profile == null) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CreateWorkerOfferScreen(worker: profile, offersService: _service),
      ),
    );
    if (created == true) {
      _loadMyOffers();
    }
  }

  void _openDetail(ManagerOffer offer) => Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => OfferDetailScreen(
            offer: offer,
            worker: _profile!,
            offersService: _service,
            alreadyApplied: _appliedIds.contains(offer.id),
          ),
        ),
      )
      .then((_) => _loadAll()); // Refresh applied state on return

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOffersPageBg,
      bottomNavigationBar: _OffersBottomNav(
        onHomeTap: _openHome,
        onOffersTap: () {},
        onMessagesTap: _openMessages,
        onProfileTap: _openProfile,
      ),
      floatingActionButton: _activeTab == 1
          ? FloatingActionButton(
              onPressed: _openCreateOffer,
              backgroundColor: kOffersBlue,
              elevation: 4,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
          ? _buildErrorState(_errorMessage!)
          : _activeTab == 0
          ? _buildContent()
          : _buildMesOffres(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(child: CircularProgressIndicator(color: kOffersBlue));
  }

  Widget _buildErrorState(String message) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kOffersLightBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.wifiOff,
                color: kOffersBlue,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kOffersText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAll,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kOffersBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final profile = _profile!;
    final filtered = _filteredOffers;
    final urgent = _urgentOffers;

    return SafeArea(
      child: Column(
        children: [
          _buildHeader(profile),
          _buildTabBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                const SizedBox(height: 16),
                _buildSearchRow(),
                const SizedBox(height: 14),
                _buildProfileChips(profile),
                const SizedBox(height: 20),
                if (urgent.isNotEmpty) ...[
                  _buildSectionHeader(
                    title: 'Offres urgentes',
                    action: 'Voir toutes',
                    onAction: () => setState(() => _activeChip = 'Toutes'),
                  ),
                  const SizedBox(height: 12),
                  _buildUrgentCarousel(urgent),
                  const SizedBox(height: 24),
                ],
                _buildSectionHeader(
                  title: 'Toutes les offres',
                  action: 'Les plus récentes',
                  onAction: null,
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  _buildEmptyOffersState()
                else
                  ...filtered.map(
                    (offer) => _buildOfferCard(offer).animate().fadeIn(
                      duration: 220.ms,
                      delay: (filtered.indexOf(offer) * 40).ms,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(WorkerProfile profile) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Stack(
            children: [
              _workerAvatar(profile, size: 44),
              if (profile.isAvailable)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: kOffersSuccess,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activeTab == 0 ? 'Offres disponibles' : 'Mes offres',
                  style: const TextStyle(
                    color: kOffersText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _activeTab == 0
                      ? 'Trouvez des missions qui vous correspondent'
                      : 'Suivez vos missions acceptées',
                  style: const TextStyle(
                    color: kOffersMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _IconBtn(icon: LucideIcons.bell, onTap: () {}),
          const SizedBox(width: 6),
          _IconBtn(icon: LucideIcons.slidersHorizontal, onTap: () {}),
        ],
      ),
    );
  }

  Widget _workerAvatar(WorkerProfile profile, {double size = 44}) {
    if (profile.photoUrl?.isNotEmpty == true) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(profile.photoUrl!),
      );
    }
    if (profile.photoBase64?.isNotEmpty == true) {
      try {
        final bytes = base64Decode(profile.photoBase64!);
        return CircleAvatar(
          radius: size / 2,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: kOffersLightBlue,
      child: Text(
        profile.initials,
        style: TextStyle(
          color: kOffersBlue,
          fontSize: size * 0.35,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ── Segmented tab bar ─────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: kOffersLightBlue,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kOffersBorder),
        ),
        child: Row(
          children: [
            _tabButton(0, LucideIcons.search, 'Offres disponibles'),
            _tabButton(1, LucideIcons.briefcase, 'Mes offres'),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final active = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeTab = index);
          if (index == 1 && _myOffers.isEmpty && !_myOffersLoading) {
            _loadMyOffers();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? kOffersBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : kOffersMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : kOffersMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Search row ────────────────────────────────────────────────────────────

  Widget _buildSearchRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Rechercher une offre, un condo, un lieu...',
              hintStyle: const TextStyle(color: kOffersMuted, fontSize: 13.5),
              prefixIcon: const Icon(
                LucideIcons.search,
                color: kOffersMuted,
                size: 18,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(
                        LucideIcons.x,
                        color: kOffersMuted,
                        size: 18,
                      ),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: kOffersBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: kOffersBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: kOffersBlue, width: 1.2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            final profile = _profile;
            if (profile == null ||
                profile.addressLatitude == null ||
                profile.addressLongitude == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Ajoutez votre adresse dans votre profil pour utiliser ce filtre.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            setState(() => _nearMeOnly = !_nearMeOnly);
            _loadAll();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _nearMeOnly ? kOffersDarkBlue : kOffersBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(LucideIcons.mapPin, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'Près de moi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Profile chips ─────────────────────────────────────────────────────────

  Widget _buildProfileChips(WorkerProfile profile) {
    final chips = ['Toutes', ...profile.specialties];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: kOffersLightBlue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: const [
              Icon(LucideIcons.info, color: kOffersBlue, size: 15),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Offres adaptées à votre profil',
                  style: TextStyle(
                    color: kOffersBlue,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final chip = chips[index];
              final active = _activeChip == chip;
              return GestureDetector(
                onTap: () => setState(() => _activeChip = chip),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: active ? kOffersBlue : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: active ? kOffersBlue : kOffersBorder,
                    ),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(
                      color: active ? Colors.white : kOffersMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader({
    required String title,
    required String action,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: kOffersText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        if (onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              action,
              style: const TextStyle(
                color: kOffersBlue,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kOffersLightBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              action,
              style: const TextStyle(
                color: kOffersBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // ── Urgent carousel ───────────────────────────────────────────────────────

  Widget _buildUrgentCarousel(List<ManagerOffer> urgentOffers) {
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _carouselController,
            itemCount: urgentOffers.length,
            onPageChanged: (page) => setState(() => _carouselPage = page),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _buildCarouselCard(urgentOffers[index]),
              );
            },
          ),
        ),
        if (urgentOffers.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              urgentOffers.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _carouselPage ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _carouselPage ? kOffersBlue : kOffersBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCarouselCard(ManagerOffer offer) {
    final budgetFormatted = NumberFormat(
      '#,##0',
      'fr_FR',
    ).format(offer.budgetAmount.toInt());

    return GestureDetector(
      onTap: () => _openDetail(offer),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF3B30), Color(0xFFCC1A12)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28FF3B30),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
              child: SizedBox(
                width: 120,
                height: double.infinity,
                child: _carouselImage(offer),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.flame,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            offer.urgency == OfferUrgency.veryUrgent
                                ? 'Très urgent'
                                : 'Urgent',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      offer.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      offer.condoName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$budgetFormatted ${offer.budgetCurrency}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Voir les détails',
                        style: TextStyle(
                          color: Color(0xFFCC1A12),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
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
    );
  }

  Widget _carouselImage(ManagerOffer offer) {
    final base64 = offer.condoImageBase64?.isNotEmpty == true
        ? offer.condoImageBase64
        : (offer.managerPhotoBase64?.isNotEmpty == true
              ? offer.managerPhotoBase64
              : null);

    if (base64 != null) {
      try {
        return Image.memory(
          base64Decode(base64),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      } catch (_) {}
    }

    return Container(
      color: Colors.white.withValues(alpha: 0.15),
      child: const Center(
        child: Icon(LucideIcons.building2, color: Colors.white, size: 36),
      ),
    );
  }

  // ── Offer card ────────────────────────────────────────────────────────────

  Widget _buildOfferCard(ManagerOffer offer) {
    final budgetFormatted = NumberFormat(
      '#,##0',
      'fr_FR',
    ).format(offer.budgetAmount.toInt());
    final alreadyApplied = _appliedIds.contains(offer.id);

    return GestureDetector(
      onTap: () => _openDetail(offer),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kOffersBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0F63FF),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _offerCardAvatar(offer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    offer.title,
                    style: const TextStyle(
                      color: kOffersText,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    offer.condoName,
                    style: const TextStyle(
                      color: kOffersBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MetaPill(
                        icon: LucideIcons.calendarDays,
                        label: offer.requestedDate,
                      ),
                      _MetaPill(
                        icon: LucideIcons.clock3,
                        label: offer.requestedTime,
                      ),
                      _MetaPill(icon: LucideIcons.tag, label: offer.specialty),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _UrgencyBadge(offer.urgency),
                const SizedBox(height: 6),
                Text(
                  '$budgetFormatted\n${offer.budgetCurrency}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: kOffersText,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  offer.isNegotiable ? 'Négociable' : 'Fixe',
                  style: TextStyle(
                    color: offer.isNegotiable ? kOffersSuccess : kOffersMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (alreadyApplied)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kOffersSuccess.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Postulé',
                      style: TextStyle(
                        color: kOffersSuccess,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  const Icon(
                    LucideIcons.chevronRight,
                    color: kOffersMuted,
                    size: 18,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _offerCardAvatar(ManagerOffer offer) {
    const size = 52.0;
    // Priority: managerPhotoBase64 → condoImageBase64 → initials → building icon
    final base64 = offer.managerPhotoBase64?.isNotEmpty == true
        ? offer.managerPhotoBase64
        : (offer.condoImageBase64?.isNotEmpty == true
              ? offer.condoImageBase64
              : null);

    if (base64 != null) {
      try {
        final bytes = base64Decode(base64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }

    final initial = offer.condoName.isNotEmpty
        ? offer.condoName[0].toUpperCase()
        : null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kOffersLightBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: initial != null
          ? Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: kOffersBlue,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : const Icon(LucideIcons.building2, color: kOffersBlue, size: 24),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyOffersState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kOffersBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kOffersLightBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              LucideIcons.searchX,
              color: kOffersBlue,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune offre disponible',
            style: TextStyle(
              color: kOffersText,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aucune mission ne correspond à votre profil pour le moment. Essayez de changer le filtre ou revenez plus tard.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kOffersMuted,
              fontSize: 13.5,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mes offres tab ────────────────────────────────────────────────────────

  Widget _buildMesOffres() {
    final profile = _profile;

    if (_myOffersLoading) {
      return const Center(child: CircularProgressIndicator(color: kOffersBlue));
    }

    final enCours = _enCours;
    final aVenir = _aVenir;
    final terminees = _terminees;
    final hasAny =
        enCours.isNotEmpty || aVenir.isNotEmpty || terminees.isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          if (profile != null) _buildHeader(profile),
          _buildTabBar(),
          Expanded(
            child: hasAny
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    children: [
                      if (_myPublishedOffers.isNotEmpty)
                        _buildPublishedOffersSection(),
                      if (enCours.isNotEmpty)
                        _buildMySection(
                          icon: LucideIcons.clock,
                          title: 'En cours',
                          offers: enCours,
                          statusLabel: 'En cours',
                          statusColor: kOffersBlue,
                        ),
                      if (aVenir.isNotEmpty)
                        _buildMySection(
                          icon: LucideIcons.calendarDays,
                          title: 'À venir',
                          offers: aVenir,
                          statusLabel: 'Confirmée',
                          statusColor: kOffersSuccess,
                        ),
                      if (terminees.isNotEmpty)
                        _buildMySection(
                          icon: LucideIcons.checkCircle,
                          title: 'Terminées',
                          offers: terminees,
                          statusLabel: 'Terminée',
                          statusColor: kOffersMuted,
                        ),
                    ],
                  )
                : _buildMesOffresEmpty(),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishedOffersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(LucideIcons.badgeDollarSign, color: kOffersBlue, size: 18),
            SizedBox(width: 8),
            Text(
              'Mes offres publiées',
              style: TextStyle(
                color: kOffersText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._myPublishedOffers.map((offer) {
          final rate = offer.effectiveRate?.toStringAsFixed(0) ?? '--';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kOffersBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: kOffersLightBlue,
                    borderRadius: BorderRadius.circular(16),
                    image: offer.imageUrl?.isNotEmpty == true
                        ? DecorationImage(
                            image: NetworkImage(offer.imageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: offer.imageUrl?.isNotEmpty == true
                      ? null
                      : const Icon(LucideIcons.image, color: kOffersBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title.isEmpty ? 'Offre sans titre' : offer.title,
                        style: const TextStyle(
                          color: kOffersText,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        offer.selectedSpecialty,
                        style: const TextStyle(
                          color: kOffersBlue,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$rate ${offer.currency}/h · ${offer.viewCount} vue(s)',
                        style: const TextStyle(
                          color: kOffersMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: offer.isPromotion
                        ? const Color(0xFFFFF7ED)
                        : kOffersLightBlue,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    offer.isPromotion ? 'Promo' : 'Active',
                    style: TextStyle(
                      color: offer.isPromotion ? kOffersWarning : kOffersBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMySection({
    required IconData icon,
    required String title,
    required List<ManagerOffer> offers,
    required String statusLabel,
    required Color statusColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: statusColor == kOffersMuted
                    ? const Color(0xFFF1F5F9)
                    : statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: statusColor, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: kOffersText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                children: const [
                  Text(
                    'Voir toutes',
                    style: TextStyle(
                      color: kOffersBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(LucideIcons.chevronRight, color: kOffersBlue, size: 14),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...offers.map(
          (o) => _buildMyOfferCard(
            offer: o,
            statusLabel: statusLabel,
            statusColor: statusColor,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMyOfferCard({
    required ManagerOffer offer,
    required String statusLabel,
    required Color statusColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOffersBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07071A3D),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 90,
                    height: 90,
                    child: _myOfferThumbnail(offer),
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title.isNotEmpty
                            ? offer.title
                            : 'Offre sans titre',
                        style: const TextStyle(
                          color: kOffersText,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        offer.condoName.isNotEmpty
                            ? offer.condoName
                            : 'Condo non renseigné',
                        style: const TextStyle(
                          color: kOffersBlue,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (offer.requestedDate.isNotEmpty)
                            _myMeta(LucideIcons.calendar, offer.requestedDate),
                          if (offer.requestedTime.isNotEmpty)
                            _myMeta(LucideIcons.clock, offer.requestedTime),
                          if (offer.specialty.isNotEmpty)
                            _myMeta(
                              _specialtyIcon(offer.specialty),
                              offer.specialty,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      '${offer.budgetAmount.toStringAsFixed(0)} ',
                                  style: const TextStyle(
                                    color: kOffersBlue,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: '${offer.budgetCurrency}/h',
                                  style: const TextStyle(
                                    color: kOffersMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _statusPill(statusLabel, statusColor),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  LucideIcons.chevronRight,
                  color: kOffersMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _myOfferThumbnail(ManagerOffer offer) {
    if (offer.condoImageBase64?.isNotEmpty == true) {
      try {
        return Image.memory(
          base64Decode(offer.condoImageBase64!),
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }
    return Container(
      color: kOffersLightBlue,
      child: const Center(
        child: Icon(LucideIcons.building2, color: kOffersBlue, size: 32),
      ),
    );
  }

  Widget _myMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: kOffersMuted),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            color: kOffersMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  IconData _specialtyIcon(String specialty) {
    final s = specialty.toLowerCase();
    if (s.contains('plomb')) return LucideIcons.wrench;
    if (s.contains('élec') || s.contains('elec')) return LucideIcons.zap;
    if (s.contains('peinture')) return LucideIcons.paintbrush;
    if (s.contains('clim') || s.contains('hvac')) return LucideIcons.wind;
    if (s.contains('ménage') || s.contains('menage'))
      return LucideIcons.sparkles;
    return LucideIcons.briefcase;
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color == kOffersMuted
            ? const Color(0xFFF1F5F9)
            : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildMesOffresEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kOffersLightBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.briefcase,
                color: kOffersBlue,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aucune offre acceptée',
              style: TextStyle(
                color: kOffersText,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vos missions acceptées apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kOffersMuted,
                fontSize: 13.5,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => setState(() => _activeTab = 0),
              style: ElevatedButton.styleFrom(
                backgroundColor: kOffersBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Parcourir les offres',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: kOffersLightBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: kOffersBlue, size: 20),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kOffersBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kOffersBlue, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: kOffersText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgencyBadge extends StatelessWidget {
  const _UrgencyBadge(this.urgency);

  final OfferUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (urgency) {
      case OfferUrgency.veryUrgent:
        label = 'Très urgent';
        color = Colors.red;
        break;
      case OfferUrgency.urgent:
        label = 'Urgent';
        color = Colors.red;
        break;
      case OfferUrgency.high:
        label = 'Élevée';
        color = kOffersWarning;
        break;
      case OfferUrgency.normal:
        label = 'Normale';
        color = kOffersSuccess;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── BOTTOM NAV — DO NOT MODIFY — verbatim copy of original ───────────────────

class _OffersBottomNav extends StatelessWidget {
  final VoidCallback onHomeTap;
  final VoidCallback onOffersTap;
  final VoidCallback onMessagesTap;
  final VoidCallback onProfileTap;

  const _OffersBottomNav({
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
        border: Border(top: BorderSide(color: kOffersBorder)),
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
                  active: false,
                  onTap: onHomeTap,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.briefcase,
                  label: 'Offres',
                  active: true,
                  onTap: onOffersTap,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.messageCircle,
                  label: 'Messages',
                  active: false,
                  onTap: onMessagesTap,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
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
    final color = active ? kOffersBlue : kOffersMuted;

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
                color: kOffersBlue,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
