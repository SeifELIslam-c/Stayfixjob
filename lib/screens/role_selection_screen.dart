// ignore_for_file: prefer_final_fields

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'home_screen.dart';

const kPrimaryBlue = Color(0xFF2563EB);
const kBrightBlue = Color(0xFF0F63FF);
const kNavy = Color(0xFF0F172A);
const kBody = Color(0xFF475569);
const kSecondary = Color(0xFF64748B);
const kBorder = Color(0xFFE2E8F0);
const kLightBlue = Color(0xFFEFF6FF);
const kPanelBackground = Color(0xFFF7FAFF);

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  static const _singleSkillDepartment = "Main-d'\u0153uvre qualifi\u00e9e";

  String? _selectedDepartment;
  List<String> _selectedSpecialties = [];
  int? _departmentExperienceYears;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _departments = [
    {
      'name': 'Maintenance g\u00e9n\u00e9rale',
      'description': 'R\u00e9parations et maintenance des installations',
      'color': const Color(0xFF2563EB),
      'icon': LucideIcons.wrench,
      'specialties': [
        'Bricolage',
        'Aide g\u00e9n\u00e9rale',
        'Jardinage paysager',
      ],
    },
    {
      'name': "Main-d'\u0153uvre qualifi\u00e9e",
      'description': 'Travaux sp\u00e9cialis\u00e9s et experts',
      'color': const Color(0xFF8B5CF6),
      'icon': Icons.format_paint,
      'specialties': [
        'Plomberie professionnelle',
        '\u00c9lectricit\u00e9 avanc\u00e9e',
        'Climatisation & chauffage',
        'Ma\u00e7onnerie professionnelle',
        'Menuiserie g\u00e9n\u00e9rale',
        'Peinture d\u00e9corative',
        'Soudure industrielle',
      ],
    },
    {
      'name': 'Pr\u00e9pos\u00e9 aux chambres',
      'description': 'Entretien et pr\u00e9paration des chambres',
      'color': const Color(0xFFA855F7),
      'icon': LucideIcons.bedDouble,
      'specialties': [
        'Nettoyage des chambres',
        'Gestion du linge',
        'Remise en \u00e9tat des chambres',
      ],
    },
    {
      'name': 'Houseman',
      'description': 'Assistance g\u00e9n\u00e9rale et support',
      'color': const Color(0xFFF97316),
      'icon': LucideIcons.hardHat,
      'specialties': [
        'Transport bagages',
        'Entretien couloirs',
        'Soutien Housekeeping',
      ],
    },
    {
      'name': 'Concierge',
      'description': 'Accueil et services aux clients',
      'color': const Color(0xFF10B981),
      'icon': Icons.support_agent,
      'specialties': [
        'Accueil clients',
        'Service information',
        'Gestion des bagages',
        'R\u00e9servations & services',
        'Assistance VIP',
      ],
    },
    {
      'name': 'M\u00e9nage',
      'description': 'Nettoyage et entretien des espaces',
      'color': const Color(0xFF38B000),
      'icon': Icons.cleaning_services,
      'specialties': [
        'Nettoyage des chambres',
        'Nettoyage espaces communs',
        'Gestion du linge',
        'D\u00e9sinfection & hygi\u00e8ne',
        'Remise en \u00e9tat des chambres',
      ],
    },
  ];

  final Map<String, IconData> _skillIcons = const {
    'Plomberie professionnelle': LucideIcons.wrench,
    '\u00c9lectricit\u00e9 avanc\u00e9e': LucideIcons.zap,
    'Climatisation & chauffage': LucideIcons.snowflake,
    'Ma\u00e7onnerie professionnelle': Icons.grid_view_rounded,
    'Menuiserie g\u00e9n\u00e9rale': LucideIcons.ruler,
    'Peinture d\u00e9corative': Icons.format_paint,
    'Soudure industrielle': LucideIcons.sparkles,
    'Jardinage paysager': LucideIcons.leaf,
    'Aide g\u00e9n\u00e9rale': Icons.volunteer_activism_outlined,
    'Bricolage': LucideIcons.hammer,
    'Transport bagages': Icons.luggage_rounded,
    'Entretien couloirs': Icons.cleaning_services_outlined,
    'Soutien Housekeeping': Icons.house_outlined,
    'Nettoyage des chambres': LucideIcons.bedDouble,
    'Nettoyage espaces communs': LucideIcons.building2,
    'Gestion du linge': LucideIcons.shirt,
    'D\u00e9sinfection & hygi\u00e8ne': LucideIcons.shieldCheck,
    'Remise en \u00e9tat des chambres': LucideIcons.rotateCcw,
    'Accueil clients': Icons.front_hand_outlined,
    'Service information': LucideIcons.info,
    'Gestion des bagages': LucideIcons.luggage,
    'R\u00e9servations & services': LucideIcons.calendarCheck2,
    'Assistance VIP': LucideIcons.star,
  };

  Future<void> _saveSelection() async {
    if (_selectedDepartment == null) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .update({
              'department': _selectedDepartment,
              'specialties': _selectedSpecialties,
              'departmentExperienceYears': _departmentExperienceYears ?? 0,
              'specialtyExperienceYears': {},
            });

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const HomeScreen(requireAuth: false),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSkillsSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<int?> _showExperienceYearsSheet(
    String roleLabel, {
    int? initialYears,
  }) async {
    int selectedYears = initialYears ?? 1;

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7E4FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: kLightBlue,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        LucideIcons.badgeCheck,
                        color: kBrightBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Annees d experience',
                      style: TextStyle(
                        color: kNavy,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Indiquez votre experience pour $roleLabel.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: kBody,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kBorder),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$selectedYears ${selectedYears > 1 ? 'ans' : 'an'}',
                            style: const TextStyle(
                              color: kBrightBlue,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Slider(
                            value: selectedYears.toDouble(),
                            min: 1,
                            max: 30,
                            divisions: 29,
                            activeColor: kBrightBlue,
                            inactiveColor: const Color(0xFFDCE8F8),
                            onChanged: (value) {
                              setModalState(() {
                                selectedYears = value.round();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kBrightBlue,
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
                            onPressed: () =>
                                Navigator.pop(context, selectedYears),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrightBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Confirmer'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickDepartmentExperience() async {
    final department = _selectedDepartment;
    if (department == null) return;

    final years = await _showExperienceYearsSheet(
      department,
      initialYears: _departmentExperienceYears,
    );
    if (years == null || !mounted) return;

    setState(() {
      _departmentExperienceYears = years;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedDepartmentData = _selectedDepartment == null
        ? null
        : _departments.firstWhere(
            (department) => department['name'] == _selectedDepartment,
          );
    final currentSpecialties = selectedDepartmentData == null
        ? <String>[]
        : List<String>.from(
            selectedDepartmentData['specialties'] as List<dynamic>,
          );
    final progressStep = _selectedDepartment == null
        ? 1
        : _departmentExperienceYears == null || _departmentExperienceYears == 0
        ? 2
        : 3;
    final canContinue =
        _selectedDepartment != null &&
        (_departmentExperienceYears ?? 0) > 0 &&
        currentSpecialties.isNotEmpty &&
        _selectedSpecialties.isNotEmpty &&
        !_isLoading;

    return Scaffold(
      backgroundColor: kPanelBackground,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHero(progressStep),
              const Expanded(child: ColoredBox(color: kPanelBackground)),
            ],
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 244),
                        Transform.translate(
                          offset: const Offset(0, -24),
                          child: _buildContentPanel(currentSpecialties),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildBottomBar(canContinue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(int progressStep) {
    return SizedBox(
      height: 304,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'lib/assets/selectionheroimg.png',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0A69FF).withValues(alpha: 0.92),
                  const Color(0xFF1459E8).withValues(alpha: 0.84),
                  const Color(0xFF2563EB).withValues(alpha: 0.78),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.transparent,
                    const Color(0xFF0F43D8).withValues(alpha: 0.18),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0, 0.48, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: _ProgressBar(activeStep: progressStep)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Text(
                      '\u00c9TAPE 2 SUR 3',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(
                    width: 250,
                    child: Text(
                      'Personnalisez votre profil',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        letterSpacing: -0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const SizedBox(
                    width: 250,
                    child: Text(
                      'S\u00e9lectionnez votre d\u00e9partement principal et vos comp\u00e9tences',
                      style: TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 15.5,
                        height: 1.48,
                        fontWeight: FontWeight.w500,
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

  Widget _buildContentPanel(List<String> currentSpecialties) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
        boxShadow: [
          BoxShadow(
            color: Color(0x160F63FF),
            blurRadius: 28,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.work_outline_rounded,
              title: 'S\u00e9lectionnez votre d\u00e9partement',
              subtitle: 'Choisissez votre domaine principal',
            ),
            const SizedBox(height: 14),
            GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _departments.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.84,
                  ),
                  itemBuilder: (context, index) {
                    final department = _departments[index];
                    final isSelected =
                        _selectedDepartment == department['name'];

                    return _DepartmentCard(
                      name: department['name'] as String,
                      description: department['description'] as String,
                      icon: department['icon'] as IconData,
                      color: department['color'] as Color,
                      selected: isSelected,
                      onTap: () {
                        final selectingNewDepartment =
                            _selectedDepartment != department['name'];
                        setState(() {
                          if (_selectedDepartment == department['name']) {
                            _selectedDepartment = null;
                            _selectedSpecialties.clear();
                            _departmentExperienceYears = null;
                          } else {
                            _selectedDepartment = department['name'] as String;
                            _selectedSpecialties.clear();
                            _departmentExperienceYears = null;
                          }
                        });
                        if (selectingNewDepartment) {
                          _scrollToSkillsSection();
                          _pickDepartmentExperience();
                        }
                      },
                    );
                  },
                )
                .animate()
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.035, duration: 260.ms),
            if (_selectedDepartment != null) ...[
              const SizedBox(height: 20),
              _ExperienceSummaryCard(
                label: _selectedDepartment!,
                years: _departmentExperienceYears,
                onTap: _pickDepartmentExperience,
              ),
              const SizedBox(height: 18),
              const _SectionHeader(
                icon: LucideIcons.badgeCheck,
                title: 'Vos comp\u00e9tences sp\u00e9cifiques',
                subtitle: 'S\u00e9lectionnez une ou plusieurs comp\u00e9tences',
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 620 ? 3 : 2;
                      final aspectRatio = width >= 620
                          ? 2.6
                          : width >= 390
                          ? 2.25
                          : 2.0;

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: currentSpecialties.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: aspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          final skill = currentSpecialties[index];
                          final isSelected = _selectedSpecialties.contains(
                            skill,
                          );

                          return _SkillChipCard(
                            label: skill,
                            icon: _skillIcons[skill] ?? LucideIcons.sparkles,
                            selected: isSelected,
                            onTap: () {
                              if (isSelected) {
                                setState(() {
                                  _selectedSpecialties.remove(skill);
                                });
                                return;
                              }

                              setState(() {
                                if (_selectedDepartment ==
                                    _singleSkillDepartment) {
                                  _selectedSpecialties
                                    ..clear()
                                    ..add(skill);
                                } else {
                                  _selectedSpecialties.add(skill);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  )
                  .animate()
                  .fadeIn(duration: 220.ms)
                  .slideY(begin: 0.03, duration: 220.ms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool canContinue) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EEF8))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 62,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: canContinue
                  ? const LinearGradient(
                      colors: [kPrimaryBlue, kBrightBlue],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: canContinue ? null : const Color(0xFFDDE7FA),
              borderRadius: BorderRadius.circular(24),
              boxShadow: canContinue
                  ? const [
                      BoxShadow(
                        color: Color(0x330F63FF),
                        blurRadius: 22,
                        offset: Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canContinue ? _saveSelection : null,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.arrowRight,
                          color: canContinue
                              ? kPrimaryBlue
                              : const Color(0xFF96A6C8),
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Continuer',
                              style: TextStyle(
                                color: canContinue
                                    ? Colors.white
                                    : const Color(0xFF96A6C8),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.35,
                              ),
                            ),
                      const Spacer(),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExperienceSummaryCard extends StatelessWidget {
  final String label;
  final int? years;
  final VoidCallback onTap;

  const _ExperienceSummaryCard({
    required this.label,
    required this.years,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = (years ?? 0) > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: kLightBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                LucideIcons.badgeCheck,
                color: kBrightBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Annees d'experience du departement",
                    style: TextStyle(
                      color: kBody,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasValue
                        ? '$label • $years ${years! > 1 ? 'ans' : 'an'}'
                        : 'Choisissez vos annees pour $label',
                    style: const TextStyle(
                      color: kNavy,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.pencil, color: kSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int activeStep;

  const _ProgressBar({required this.activeStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (index) => Container(
          width: 68,
          height: 8,
          margin: EdgeInsets.only(right: index == 2 ? 0 : 16),
          decoration: BoxDecoration(
            color: index < activeStep
                ? Colors.white
                : Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
            border: index < activeStep
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: index < activeStep
                ? const [
                    BoxShadow(
                      color: Color(0x1AFFFFFF),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: kLightBlue,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: kPrimaryBlue, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: kNavy,
                  fontSize: 18.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: kSecondary,
                  fontSize: 14,
                  height: 1.48,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _DepartmentCard({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF4F8FF) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? kBrightBlue : kBorder,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? const Color(0x170F63FF)
                    : const Color(0x100F172A),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const Spacer(),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: selected ? kBrightBlue : Colors.transparent,
                      shape: BoxShape.circle,
                      border: selected
                          ? null
                          : Border.all(
                              color: const Color(0xFFD0D9E8),
                              width: 1.4,
                            ),
                    ),
                    child: selected
                        ? const Icon(
                            LucideIcons.check,
                            color: Colors.white,
                            size: 16,
                          )
                        : null,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                name,
                style: const TextStyle(
                  color: kNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: const TextStyle(
                  color: kBody,
                  fontSize: 14,
                  height: 1.46,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillChipCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SkillChipCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF4F8FF) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? kBrightBlue : kBorder,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? kBrightBlue : kSecondary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? kPrimaryBlue : kNavy,
                    fontSize: 13.5,
                    height: 1.32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: kBrightBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.check,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
