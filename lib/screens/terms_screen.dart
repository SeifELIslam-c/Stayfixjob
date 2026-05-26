import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_screen.dart';
import 'home_screen.dart';
import 'role_selection_screen.dart';

const String _tcFrench = '''STAYFIX JOB — CONDITIONS D'UTILISATION

1. Accord aux conditions
En accédant ou en utilisant Stayfix Job ("la Plateforme"), vous acceptez ces conditions d'utilisation. Si vous ne les acceptez pas, vous ne pouvez pas utiliser la Plateforme.

2. Rôle de la Plateforme (Clause importante)
Stayfix Job est une plateforme technologique qui facilite les connexions entre demandeurs d'emploi et employeurs.
- Nous ne sommes pas un employeur
- Nous ne sommes pas une agence de recrutement
- Nous ne participons pas aux décisions d'embauche
- Nous ne garantissons pas l'emploi, les entretiens ou les offres d'emploi
Toutes les relations d'emploi sont strictement entre les utilisateurs et les employeurs.

3. Comptes utilisateur
Les utilisateurs doivent :
- Fournir des informations exactes, complètes et vérifiables
- Maintenir la confidentialité de leurs identifiants de connexion
- Être responsables de toute activité sous leur compte
Nous nous réservons le droit de suspendre ou de résilier les comptes suspects de fraude ou d'abus.

4. Responsabilités et conduite des utilisateurs
Les utilisateurs acceptent de ne pas :
- Falsifier identité, qualifications ou expérience
- Utiliser la Plateforme à des fins illégales, trompeuses ou abusives
- Harceler, spammer ou contacter les employeurs en dehors du cadre professionnel
- Contourner ou perturber les systèmes de la Plateforme

5. Contenu des employeurs et avis de non-responsabilité
Les offres d'emploi et le contenu des employeurs sont fournis par des tiers.
Stayfix Job ne :
- Garantit pas l'exactitude des offres d'emploi
- Vérifie pas toutes les affirmations des employeurs
- Assume pas la responsabilité des salaires, contrats ou conditions de travail
Les utilisateurs doivent évaluer indépendamment les opportunités.

6. Aucune garantie d'emploi
Stayfix Job ne garantit pas :
- Le placement d'emploi
- Les invitations à entretien
- Les réponses des employeurs
- Les résultats d'embauche

7. Partage de données et confidentialité
Certaines données de profil peuvent être partagées avec les employeurs à des fins de recrutement.
Nous traitons les données conformément aux lois applicables sur la protection des données.
Nous ne vendons pas les données personnelles.

8. Propriété intellectuelle
Tous les contenus, marques et logiciels de la Plateforme sont la propriété de Stayfix Job et protégés par les lois sur la propriété intellectuelle. Les utilisateurs ne peuvent pas copier, distribuer ou modifier le contenu de la Plateforme sans autorisation.

9. Suspension et résiliation
Nous pouvons suspendre ou résilier définitivement l'accès à la Plateforme à notre seule discrétion, notamment en cas de :
- Violation de ces conditions
- Comportement frauduleux ou abusif
- Risques de sécurité ou exigences de conformité légale

10. Limitation de responsabilité (clause de style Uber)
Dans la mesure maximale autorisée par la loi :
- Stayfix Job n'est pas responsable des dommages indirects, accessoires ou consécutifs
- Nous ne sommes pas responsables des différends entre utilisateurs et employeurs
- L'utilisation de la Plateforme se fait à vos risques et périls

11. Modifications
Nous pouvons mettre à jour ces conditions à tout moment. L'utilisation continue de la Plateforme constitue une acceptation des conditions révisées.

12. Droit applicable
Ces conditions sont régies par les lois applicables de la juridiction dans laquelle la Plateforme opère, sauf disposition légale contraire.''';

const String _tcEnglish = '''STAYFIX JOB — TERMS OF USE

1. Agreement to Terms
By accessing or using Stayfix Job ("the Platform"), you enter into a legally binding agreement with Stayfix Job. If you do not agree to these Terms, you may not use the Platform.

2. Platform Role (Important Clause)
Stayfix Job is a technology platform that facilitates connections between job seekers and employers.
- We do not act as an employer
- We do not act as a recruitment agency
- We do not participate in hiring decisions
- We do not guarantee employment, interviews, or job offers
All employment relationships are strictly between users and employers.

3. User Accounts
Users must:
- Provide accurate, complete, and verifiable information
- Maintain the confidentiality of login credentials
- Be responsible for all activity under their account
We reserve the right to suspend or terminate accounts suspected of fraud or misuse.

4. User Responsibilities & Conduct
Users agree not to:
- Misrepresent identity, qualifications, or experience
- Use the Platform for illegal, deceptive, or abusive purposes
- Harass, spam, or contact employers outside professional intent
- Attempt to bypass or disrupt Platform systems

5. Employer Content & Listings Disclaimer
Job postings and employer content are provided by third parties.
Stayfix Job does not:
- Guarantee the accuracy of job listings
- Verify all employer claims
- Assume responsibility for wages, contracts, or working conditions
Users must independently evaluate opportunities.

6. No Employment Guarantee
Stayfix Job does not guarantee:
- Job placement
- Interview invitations
- Employer responses
- Hiring outcomes

7. Data Sharing & Privacy
Certain profile data may be shared with employers for recruitment purposes
We process data in accordance with applicable privacy laws
We do not sell personal data

8. Intellectual Property
All Platform content, branding, and software are owned by Stayfix Job and protected by intellectual property laws. Users may not copy, distribute, or modify Platform content without authorization.

9. Suspension and Termination
We may suspend or permanently terminate access to the Platform at our sole discretion, including for:
- Violation of these Terms
- Fraudulent or abusive behavior
- Security risks or legal compliance requirements

10. Limitation of Liability (Uber-style clause)
To the maximum extent permitted by law:
- Stayfix Job is not liable for any indirect, incidental, or consequential damages
- We are not responsible for disputes between users and employers
- Use of the Platform is at your own risk

11. Modifications
We may update these Terms at any time. Continued use of the Platform constitutes acceptance of the revised Terms.

12. Governing Law
These Terms shall be governed by applicable laws of the jurisdiction in which the Platform operates, unless otherwise required.''';

class TermsScreen extends StatefulWidget {
  final bool isFirstTime;
  // When provided, navigate here after accepting instead of RoleSelectionScreen
  final Widget? nextScreen;

  const TermsScreen({super.key, this.isFirstTime = true, this.nextScreen});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  static const _primaryBlue = Color(0xFF2563EB);
  static const _brightBlue = Color(0xFF0F63FF);
  static const _cyan = Color(0xFF22D3EE);
  static const _navy = Color(0xFF0F172A);
  static const _body = Color(0xFF475569);
  static const _secondary = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  static const _lightBlue = Color(0xFFEAF2FF);

  bool _isFrench = true;
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToEnd = false;
  bool _isLoading = false;
  bool _acceptedBefore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAcceptanceStatus();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAcceptanceStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snapshot = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .get();
      final data = snapshot.data();
      if (!mounted || data == null) return;
      setState(() {
        _acceptedBefore = data['termsAccepted'] == true;
      });
      if (_acceptedBefore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _routeAfterAcceptance();
        });
      }
    } catch (_) {}
  }

  Future<void> _routeAfterAcceptance() async {
    if (!mounted) return;
    if (widget.nextScreen != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => widget.nextScreen!),
      );
      return;
    }
    if (!widget.isFirstTime) {
      Navigator.pop(context);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final userData = user == null
        ? null
        : (await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get())
              .data();
    if (!mounted) return;
    final isStayFixConcierge =
        userData?['accountType'] == 'concierge' &&
        userData?['appAccess'] == 'stayfix_job' &&
        userData?['status'] != 'deleted';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => isStayFixConcierge
            ? const HomeScreen(requireAuth: false)
            : const RoleSelectionScreen(),
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atEnd = position.pixels >= position.maxScrollExtent - 8.0;
    if (atEnd && !_hasScrolledToEnd) {
      setState(() => _hasScrolledToEnd = true);
    }
  }

  void _switchLanguage(bool toFrench) {
    if (_isFrench == toFrench) return;
    final currentOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    setState(() {
      _isFrench = toFrench;
      _hasScrolledToEnd = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(currentOffset.clamp(0.0, maxExtent));
      }
    });
  }

  Future<void> _handleAccept() async {
    if (!_hasScrolledToEnd || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .set({
              'termsAccepted': true,
              'termsAcceptedAt': FieldValue.serverTimestamp(),
              'termsAcceptedLanguage': _isFrench ? 'fr' : 'en',
            }, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() => _acceptedBefore = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Conditions acceptées. Bienvenue !'
                : 'Terms accepted. Welcome!',
          ),
          backgroundColor: const Color(0xFF0F9D58),
          duration: const Duration(seconds: 2),
        ),
      );

      await _routeAfterAcceptance();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleDecline() async {
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isLoggedIn');
      await prefs.remove('userId');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Vous devez accepter les conditions pour continuer.'
                : 'You must accept the terms to continue.',
          ),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final heroHeight = (size.height * 0.38).clamp(300.0, 340.0);
    final tcText = _isFrench ? _tcFrench : _tcEnglish;
    final sections = _parseTermsSections(tcText);
    final declineLabel = _isFrench ? 'Refuser' : 'Decline';
    final acceptLabel = _isFrench ? 'Accepter' : 'Accept';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHero(context, heroHeight),
              Expanded(child: Container(color: const Color(0xFFF8FBFF))),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: heroHeight - 26),
                      ),
                      SliverToBoxAdapter(
                        child: Transform.translate(
                          offset: const Offset(0, -34),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: _buildLanguageToggle(),
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: _buildInfoBanner(),
                              ),
                              const SizedBox(height: 14),
                              if (_acceptedBefore)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: _buildAcceptedBanner(),
                                ),
                              const SizedBox(height: 16),
                              _buildTermsCard(sections),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildBottomBar(declineLabel, acceptLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, double heroHeight) {
    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/assets/conditionheroimg.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.06),
                  _primaryBlue.withValues(alpha: 0.24),
                  _brightBlue.withValues(alpha: 0.28),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                const SizedBox(
                  width: 240,
                  child: Text(
                    "Conditions d’utilisation",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(
                  width: 290,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              "Veuillez lire attentivement nos conditions\navant d’utiliser ",
                        ),
                        TextSpan(
                          text: 'StayFix Job',
                          style: TextStyle(
                            color: _cyan,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(text: '.'),
                      ],
                    ),
                    style: TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 15,
                      height: 1.58,
                      fontWeight: FontWeight.w500,
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

  Widget _buildLanguageToggle() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0x332563EB),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              LucideIcons.globe2,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SegmentButton(
              label: 'FR',
              selected: _isFrench,
              onTap: () => _switchLanguage(true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SegmentButton(
              label: 'EN',
              selected: !_isFrench,
              onTap: () => _switchLanguage(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F63FF),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.info, color: _primaryBlue, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: const [
                  TextSpan(
                    text: "Faites défiler jusqu'en bas pour activer le bouton ",
                  ),
                  TextSpan(
                    text: 'Accepter',
                    style: TextStyle(
                      color: _brightBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(
                color: _navy,
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD6E7FF)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: _lightBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.badgeCheck,
              color: _brightBlue,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vous avez déjà accepté ces conditions.',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Votre choix est enregistré sur votre compte.',
                  style: TextStyle(
                    color: _secondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsCard(List<_TermsSection> sections) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
        boxShadow: [
          BoxShadow(
            color: Color(0x120F63FF),
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_brightBlue, _primaryBlue],
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.shieldCheck,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        height: 1.3,
                      ),
                      children: [
                        TextSpan(
                          text: 'STAYFIX JOB',
                          style: TextStyle(color: _primaryBlue),
                        ),
                        TextSpan(
                          text: ' — TERMS OF USE',
                          style: TextStyle(color: _navy),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            for (int i = 0; i < sections.length; i++) ...[
              _buildSection(sections[i]),
              if (i != sections.length - 1) ...[
                const SizedBox(height: 24),
                const Divider(color: _border, height: 1),
                const SizedBox(height: 24),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(_TermsSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _lightBlue,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                section.number,
                style: const TextStyle(
                  color: _primaryBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  section.title,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final line in section.lines) ...[
          if (line.startsWith('- '))
            _buildBullet(line.substring(2))
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                line,
                style: const TextStyle(
                  color: _body,
                  fontSize: 16,
                  height: 1.72,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.badgeCheck, color: _brightBlue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _body,
                fontSize: 15.5,
                height: 1.68,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(String declineLabel, String acceptLabel) {
    final acceptEnabled = _hasScrolledToEnd && !_isLoading;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _BottomActionButton(
                label: declineLabel,
                icon: LucideIcons.x,
                foregroundColor: const Color(0xFFEF4444),
                borderColor: const Color(0xFFCBD5E1),
                backgroundColor: Colors.white,
                onTap: _isLoading ? null : _handleDecline,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _BottomActionButton(
                label: acceptLabel,
                icon: _isLoading ? null : LucideIcons.checkCircle2,
                foregroundColor: acceptEnabled
                    ? Colors.white
                    : const Color(0xFF94A3B8),
                borderColor: acceptEnabled
                    ? Colors.transparent
                    : Colors.transparent,
                backgroundColor: acceptEnabled ? null : const Color(0xFFE7EEF9),
                gradient: acceptEnabled
                    ? const LinearGradient(colors: [_primaryBlue, _brightBlue])
                    : null,
                loading: _isLoading,
                onTap: acceptEnabled ? _handleAccept : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x140F63FF),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _TermsScreenState._primaryBlue : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BottomActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color foregroundColor;
  final Color borderColor;
  final Color? backgroundColor;
  final Gradient? gradient;
  final bool loading;
  final VoidCallback? onTap;

  const _BottomActionButton({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.borderColor,
    this.backgroundColor,
    this.gradient,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: foregroundColor, size: 19),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            color: foregroundColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsSection {
  final String number;
  final String title;
  final List<String> lines;

  const _TermsSection({
    required this.number,
    required this.title,
    required this.lines,
  });
}

List<_TermsSection> _parseTermsSections(String rawText) {
  final lines = rawText.split('\n');
  final regex = RegExp(r'^(\d+)\.\s+(.*)$');
  final sections = <_TermsSection>[];

  String? currentNumber;
  String? currentTitle;
  final currentLines = <String>[];

  for (final rawLine in lines.skip(1)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final match = regex.firstMatch(line);
    if (match != null) {
      if (currentNumber != null && currentTitle != null) {
        sections.add(
          _TermsSection(
            number: currentNumber,
            title: currentTitle,
            lines: List<String>.from(currentLines),
          ),
        );
      }
      currentNumber = match.group(1)!;
      currentTitle = match.group(2)!;
      currentLines.clear();
    } else {
      currentLines.add(line);
    }
  }

  if (currentNumber != null && currentTitle != null) {
    sections.add(
      _TermsSection(
        number: currentNumber,
        title: currentTitle,
        lines: List<String>.from(currentLines),
      ),
    );
  }

  return sections;
}
