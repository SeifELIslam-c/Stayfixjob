import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'home_screen.dart';

const kAvailabilityBlue = Color(0xFF0F63FF);
const kAvailabilityDeepBlue = Color(0xFF2563EB);
const kAvailabilityPageBg = Color(0xFFF7FAFF);
const kAvailabilityText = Color(0xFF0F172A);
const kAvailabilityMuted = Color(0xFF64748B);
const kAvailabilityBorder = Color(0xFFE2E8F0);
const kAvailabilityLightBlue = Color(0xFFEFF6FF);
const kAvailabilityLightGreen = Color(0xFFECFDF3);
const kAvailabilityGreen = Color(0xFF22C55E);

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _availableDaysKey = GlobalKey();
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _configKey = GlobalKey();
  final GlobalKey _addButtonKey = GlobalKey();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _didInitialScroll = false;

  List<int> _availableWeekDays = [];
  List<_AvailabilitySlot> _availabilitySlots = [];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null).then((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .get();

        if (doc.exists && mounted) {
          final data = doc.data()!;
          final rawSlots = data['availabilitySlots'];

          setState(() {
            final storedAvailableDays = List<int>.from(
              data['availableWeekDays'] ?? const <int>[],
            )..sort();
            final storedWorkDays = List<int>.from(
              data['permanentWorkDays'] ?? const <int>[],
            )..sort();
            _availableWeekDays =
                storedAvailableDays.isNotEmpty
                      ? storedAvailableDays
                      : storedWorkDays.isNotEmpty
                      ? List<int>.generate(
                          7,
                          (index) => index + 1,
                        ).where((day) => !storedWorkDays.contains(day)).toList()
                      : <int>[]
                  ..sort();
            _availabilitySlots = rawSlots is List
                ? rawSlots
                      .whereType<Map>()
                      .map(
                        (slot) => _AvailabilitySlot.fromMap(
                          Map<String, dynamic>.from(slot),
                        ),
                      )
                      .cast<_AvailabilitySlot>()
                      .toList()
                : [];
          });

          _sortSlots();
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement disponibilite: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToAvailabilityDaysOnOpen();
        });
      }
    }
  }

  Future<void> _scrollToAvailabilityDaysOnOpen() async {
    if (!mounted || _didInitialScroll) return;
    _didInitialScroll = true;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    await _scrollToKey(_availableDaysKey, alignment: 0.12);
  }

  Future<void> _saveProfileFields(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid)
        .update(data);
  }

  _AvailabilitySlot? _slotForWeekday(int weekday) {
    for (final slot in _availabilitySlots) {
      if (slot.weekday == weekday) return slot;
    }
    return null;
  }

  Future<void> _toggleAvailableDay(int weekday) async {
    setState(() {
      if (_availableWeekDays.contains(weekday)) {
        _availableWeekDays.remove(weekday);
        _availabilitySlots.removeWhere((slot) => slot.weekday == weekday);
      } else {
        _availableWeekDays.add(weekday);
        _availableWeekDays.sort();
      }
    });

    try {
      await _saveProfileFields({
        'availableWeekDays': _availableWeekDays,
        'availabilitySlots': _availabilitySlots
            .map((slot) => slot.toMap())
            .toList(),
      });
    } catch (e) {
      debugPrint('Erreur sauvegarde jours de disponibilite: $e');
    }
  }

  void _sortSlots() {
    _availabilitySlots.sort((a, b) {
      return a.weekday.compareTo(b.weekday);
    });
  }

  Future<void> _addAvailabilitySlot() async {
    if (_availableWeekDays.isEmpty) return;

    final selection = await _showBatchAvailabilitySheet();
    if (selection == null || selection.weekdays.isEmpty) return;

    final slots = selection.weekdays
        .map(
          (weekday) => selection.isAllDay
              ? _AvailabilitySlot.allDay(weekday: weekday)
              : _AvailabilitySlot.fromRange(
                  weekday: weekday,
                  from: selection.from!,
                  to: selection.to!,
                ),
        )
        .toList();

    setState(() {
      final selectedDays = selection.weekdays.toSet();
      _availabilitySlots.removeWhere(
        (existing) => selectedDays.contains(existing.weekday),
      );
      _availabilitySlots.addAll(slots);
      _sortSlots();
      _isSaving = true;
    });

    try {
      await _saveProfileFields({
        'availableWeekDays': _availableWeekDays,
        'availabilitySlots': _availabilitySlots
            .map((slot) => slot.toMap())
            .toList(),
      });
    } catch (e) {
      debugPrint('Erreur sauvegarde creneau: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<_BatchAvailabilitySelection?> _showBatchAvailabilitySheet() async {
    final defaults = _availableWeekDays.take(1).toSet();
    var selectedDays = <int>{...defaults};
    var allDay = true;
    var from = const _TimeValue(hour12: 8, minute: 0, period: 'AM');
    var to = const _TimeValue(hour12: 4, minute: 0, period: 'PM');

    return showModalBottomSheet<_BatchAvailabilitySelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final preview = allDay
                ? 'Toujours disponible'
                : '${from.label} - ${to.label}';

            Future<void> pickRange() async {
              final picked = await _showTimeRangePickerSheet(
                initialFrom: from,
                initialTo: to,
              );
              if (picked == null || !context.mounted) return;
              setModalState(() {
                from = picked.from;
                to = picked.to;
              });
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 54,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Configurer plusieurs jours',
                      style: TextStyle(
                        color: kAvailabilityText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Selectionnez un ou plusieurs jours, puis appliquez le meme mode a tous.',
                      style: TextStyle(
                        color: kAvailabilityMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableWeekDays.map((day) {
                        final isSelected = selectedDays.contains(day);
                        final existingSlot = _slotForWeekday(day);
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              if (isSelected) {
                                selectedDays.remove(day);
                              } else {
                                selectedDays.add(day);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 102,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? kAvailabilityBlue
                                  : const Color(0xFFF8FBFF),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFFD9E7FF),
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _weekdayShort(day),
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : kAvailabilityText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  existingSlot?.displayLabel ?? 'A regler',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.92)
                                        : kAvailabilityMuted,
                                    fontSize: 11.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _modeCard(
                            selected: allDay,
                            title: 'Toujours disponible',
                            body: 'Le meme statut sera applique partout.',
                            icon: LucideIcons.sunMedium,
                            onTap: () => setModalState(() => allDay = true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _modeCard(
                            selected: !allDay,
                            title: 'Avec horaires',
                            body:
                                'Une seule plage horaire pour tous les jours.',
                            icon: LucideIcons.clock3,
                            onTap: () => setModalState(() => allDay = false),
                          ),
                        ),
                      ],
                    ),
                    if (!allDay) ...[
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: pickRange,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FBFF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFD9E7FF)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  LucideIcons.clock3,
                                  color: kAvailabilityBlue,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Horaire commun',
                                      style: TextStyle(
                                        color: kAvailabilityMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      preview,
                                      style: const TextStyle(
                                        color: kAvailabilityText,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                LucideIcons.chevronRight,
                                color: kAvailabilityMuted,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kAvailabilityBlue,
                              side: const BorderSide(color: kAvailabilityBlue),
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
                            onPressed: selectedDays.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(
                                      context,
                                      _BatchAvailabilitySelection(
                                        weekdays: selectedDays.toList()..sort(),
                                        isAllDay: allDay,
                                        from: allDay ? null : from,
                                        to: allDay ? null : to,
                                      ),
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kAvailabilityBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Appliquer'),
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

  Future<void> _removeAvailabilityDay(int weekday) async {
    setState(() {
      _availableWeekDays.remove(weekday);
      _availabilitySlots.removeWhere((existing) => existing.weekday == weekday);
      _isSaving = true;
    });

    try {
      await _saveProfileFields({
        'availableWeekDays': _availableWeekDays,
        'availabilitySlots': _availabilitySlots
            .map((item) => item.toMap())
            .toList(),
      });
    } catch (e) {
      debugPrint('Erreur suppression disponibilite: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
      return;
    }
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
      (route) => false,
    );
  }

  String _weekdayShort(int weekday) {
    const labels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return labels[weekday - 1];
  }

  String _weekdayLong(int weekday) {
    const labels = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return labels[weekday - 1];
  }

  String _slotCountLabel() {
    if (_availabilitySlots.isEmpty) return 'Aucune plage';
    return '${_availabilitySlots.length} regle(s)';
  }

  // ignore: unused_element
  String _nextSlotLabel() {
    if (_availabilitySlots.isEmpty) return 'Aucun jour configure';
    final next = _availabilitySlots.first;
    return '${_weekdayShort(next.weekday)} - ${next.displayLabel}';
  }

  String _freeDaysSummary() {
    if (_availableWeekDays.isEmpty) return 'Aucun jour disponible choisi';
    return _availableWeekDays.map(_weekdayShort).join(' - ');
  }

  String _workRhythmSummary() {
    if (_availableWeekDays.isEmpty) return 'Aucun jour disponible choisi';
    return _availableWeekDays.map(_weekdayShort).join(' - ');
  }

  // ignore: unused_element
  Future<int?> _showAvailableDayPickerSheet() async {
    int? selectedDay = _availableWeekDays.isEmpty
        ? null
        : _availableWeekDays.first;

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Choisissez un jour disponible',
                      style: TextStyle(
                        color: kAvailabilityText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choisissez un jour ou vous etes libre pour recevoir des clients.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kAvailabilityMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableWeekDays.map((day) {
                        final isSelected = selectedDay == day;
                        final existingSlot = _slotForWeekday(day);
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedDay = day),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 100,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? kAvailabilityBlue
                                  : const Color(0xFFF8FBFF),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFFD9E7FF),
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _weekdayShort(day),
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : kAvailabilityText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  existingSlot == null
                                      ? 'A regler'
                                      : existingSlot.isAllDay
                                      ? 'Toujours'
                                      : existingSlot.rangeLabel,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white.withValues(alpha: 0.92)
                                        : kAvailabilityMuted,
                                    fontSize: 11.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kAvailabilityBlue,
                              side: const BorderSide(color: kAvailabilityBlue),
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
                            onPressed: selectedDay == null
                                ? null
                                : () => Navigator.pop(context, selectedDay),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kAvailabilityBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Continuer'),
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

  // ignore: unused_element
  Future<_AvailabilitySlot?> _showAvailabilityConfigSheet({
    required int weekday,
  }) async {
    final existing = _slotForWeekday(weekday);
    var allDay = existing?.isAllDay ?? false;

    return showModalBottomSheet<_AvailabilitySlot>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Disponibilite du ${_weekdayLong(weekday).toLowerCase()}',
                      style: const TextStyle(
                        color: kAvailabilityText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choisissez si vous etes disponible toute la journee ou sur une plage horaire precise.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: kAvailabilityMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _modeCard(
                            selected: allDay,
                            title: 'Toujours disponible',
                            body:
                                'Les clients verront ce jour comme libre toute la journee.',
                            icon: LucideIcons.sunMedium,
                            onTap: () => setModalState(() => allDay = true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _modeCard(
                            selected: !allDay,
                            title: 'Avec horaires',
                            body:
                                'Ajoutez une heure de debut et une heure de fin.',
                            icon: LucideIcons.clock3,
                            onTap: () => setModalState(() => allDay = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kAvailabilityBlue,
                              side: const BorderSide(color: kAvailabilityBlue),
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Retour'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (allDay) {
                                Navigator.pop(
                                  context,
                                  _AvailabilitySlot.allDay(weekday: weekday),
                                );
                                return;
                              }

                              final range = await _showTimeRangePickerSheet(
                                initialFrom: existing?.from,
                                initialTo: existing?.to,
                              );
                              if (!context.mounted || range == null) return;

                              Navigator.pop(
                                context,
                                _AvailabilitySlot.fromRange(
                                  weekday: weekday,
                                  from: range.from,
                                  to: range.to,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kAvailabilityBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              allDay ? 'Enregistrer' : 'Choisir l heure',
                            ),
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

  Future<_PickedRange?> _showTimeRangePickerSheet({
    _TimeValue? initialFrom,
    _TimeValue? initialTo,
  }) async {
    return showModalBottomSheet<_PickedRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _TimeRangeSheet(initialFrom: initialFrom, initialTo: initialTo);
      },
    );
  }

  Future<void> _scrollToKey(GlobalKey key, {double alignment = 0.18}) async {
    final context = key.currentContext;
    if (context == null) return;

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
      alignment: alignment,
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

  BoxDecoration _whiteCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: kAvailabilityBorder),
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
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('lib/assets/disponibiliteheroimg.png', fit: BoxFit.cover),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 82),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroButton(icon: LucideIcons.arrowLeft, onTap: _handleBack),
                  const Spacer(),
                  const Text(
                    'Disponibilite',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(
                    width: 200,
                    child: Text(
                      'Choisissez vos jours disponibles et reglez les horaires clients',
                      maxLines: 3,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.2,
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

  Widget _buildOverviewCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Vue d'ensemble",
          style: TextStyle(
            color: kAvailabilityText,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _overviewStat(
                icon: LucideIcons.calendarCheck2,
                value: '${_availableWeekDays.length}',
                label: 'Jours dispo',
                iconColor: kAvailabilityBlue,
                iconBackground: kAvailabilityLightBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _overviewStat(
                icon: LucideIcons.badgeCheck,
                value: '${_availabilitySlots.length}',
                label: 'Jours regles',
                iconColor: kAvailabilityGreen,
                iconBackground: kAvailabilityLightGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _overviewStat(
                icon: LucideIcons.clock3,
                value: _slotCountLabel(),
                label: 'Statut',
                iconColor: kAvailabilityBlue,
                iconBackground: kAvailabilityLightBlue,
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _overviewStat({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
    required Color iconBackground,
    bool compact = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kAvailabilityBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F63FF),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kAvailabilityText,
              fontSize: compact ? 18 : 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kAvailabilityMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityTableCard() {
    return Container(
      key: _tableKey,
      padding: const EdgeInsets.all(18),
      decoration: _whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tableau des disponibilites',
            style: TextStyle(
              color: kAvailabilityText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD9E7FF)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Row(
                    children: const [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Jour',
                          style: TextStyle(
                            color: kAvailabilityMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'De',
                          style: TextStyle(
                            color: kAvailabilityMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: kAvailabilityMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: 44),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFD9E7FF)),
                if (_availableWeekDays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Choisissez d abord au moins un jour de disponibilite pour remplir votre tableau.',
                      style: TextStyle(
                        color: kAvailabilityMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  ..._availableWeekDays.map((day) {
                    final slot = _slotForWeekday(day);
                    final hasHours = slot != null && !slot.isAllDay;

                    return Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFD9E7FF)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _weekdayLong(day),
                                  style: const TextStyle(
                                    color: kAvailabilityText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  slot == null
                                      ? 'A regler'
                                      : slot.isAllDay
                                      ? 'Toujours disponible'
                                      : 'Plage horaire definie',
                                  style: TextStyle(
                                    color: slot == null
                                        ? kAvailabilityBlue
                                        : const Color(0xFF15803D),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              slot == null
                                  ? '--:--'
                                  : slot.isAllDay
                                  ? 'Toujours'
                                  : slot.fromLabel,
                              style: const TextStyle(
                                color: kAvailabilityText,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              slot == null
                                  ? '--:--'
                                  : slot.isAllDay
                                  ? 'Disponible'
                                  : slot.toLabel,
                              style: TextStyle(
                                color: kAvailabilityText,
                                fontSize: hasHours ? 13.5 : 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: IconButton(
                              onPressed: () => _removeAvailabilityDay(day),
                              tooltip: 'Supprimer ce jour',
                              icon: const Icon(
                                LucideIcons.trash2,
                                color: kAvailabilityMuted,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityDaysCard() {
    const dayLabels = [
      {'id': 1, 'label': 'Lun'},
      {'id': 2, 'label': 'Mar'},
      {'id': 3, 'label': 'Mer'},
      {'id': 4, 'label': 'Jeu'},
      {'id': 5, 'label': 'Ven'},
      {'id': 6, 'label': 'Sam'},
      {'id': 7, 'label': 'Dim'},
    ];

    return Container(
      key: _availableDaysKey,
      padding: const EdgeInsets.all(18),
      decoration: _whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Jours de disponibilite',
            style: TextStyle(
              color: kAvailabilityText,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choisissez les jours ou vous etes libre pour les clients. Vous pouvez toucher un jour maintenant et en ajouter d autres plus tard.',
            style: TextStyle(
              color: kAvailabilityMuted,
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: dayLabels.map((day) {
              final id = day['id'] as int;
              final label = day['label'] as String;
              final isSelected = _availableWeekDays.contains(id);
              return InkWell(
                onTap: () => _toggleAvailableDay(id),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? kAvailabilityLightBlue : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF9EC3FF)
                          : kAvailabilityBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? kAvailabilityBlue
                              : kAvailabilityText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          LucideIcons.checkCircle2,
                          color: kAvailabilityBlue,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD9E7FF)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kAvailabilityLightBlue,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    LucideIcons.refreshCw,
                    color: kAvailabilityBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Disponibilites choisies',
                        style: TextStyle(
                          color: kAvailabilityMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _workRhythmSummary(),
                        style: const TextStyle(
                          color: kAvailabilityText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotsCard() {
    return Container(
      key: _configKey,
      padding: const EdgeInsets.all(18),
      decoration: _whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configuration des jours',
                      style: TextStyle(
                        color: kAvailabilityText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _freeDaysSummary(),
                      style: const TextStyle(
                        color: kAvailabilityMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: kAvailabilityBlue,
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF8FBFF), Color(0xFFEFF6FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD9E7FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        LucideIcons.sparkles,
                        color: kAvailabilityBlue,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Configuration rapide',
                            style: TextStyle(
                              color: kAvailabilityMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Choisissez vos jours puis appliquez "toujours disponible" ou le meme horaire.',
                            style: const TextStyle(
                              color: kAvailabilityText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: _addButtonKey,
                    onPressed: _availableWeekDays.isEmpty
                        ? null
                        : _addAvailabilitySlot,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: const Text('Configurer des jours disponibles'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAvailabilityBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_availabilitySlots.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kAvailabilityBorder),
              ),
              child: const Text(
                'Aucun jour n est encore regle. Utilisez le bouton pour choisir un ou plusieurs jours et leur appliquer rapidement un mode de disponibilite.',
                style: TextStyle(
                  color: kAvailabilityMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            )
          else
            Column(
              children: _availabilitySlots.map((slot) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: kAvailabilityBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F63FF),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kAvailabilityBlue, kAvailabilityDeepBlue],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdayShort(slot.weekday).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Icon(
                              LucideIcons.calendarClock,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _weekdayLong(slot.weekday),
                              style: const TextStyle(
                                color: kAvailabilityText,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _timeBox(
                                    label: 'De',
                                    value: slot.isAllDay
                                        ? 'Toujours'
                                        : slot.fromLabel,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _timeBox(
                                    label: 'A',
                                    value: slot.isAllDay
                                        ? 'Disponible'
                                        : slot.toLabel,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _slotInfoPill(
                                  icon: LucideIcons.clock3,
                                  label: slot.displayLabel,
                                ),
                                _slotInfoPill(
                                  icon: LucideIcons.badgeCheck,
                                  label: 'Visible client',
                                  success: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeAvailabilityDay(slot.weekday),
                        tooltip: 'Supprimer ce jour',
                        icon: const Icon(
                          LucideIcons.trash2,
                          color: kAvailabilityMuted,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _timeBox({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: kAvailabilityMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  color: kAvailabilityText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotInfoPill({
    required IconData icon,
    required String label,
    bool success = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: success ? kAvailabilityLightGreen : kAvailabilityLightBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: success ? const Color(0xFF15803D) : kAvailabilityBlue,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: success ? const Color(0xFF15803D) : kAvailabilityBlue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeCard({
    required bool selected,
    required String title,
    required String body,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? kAvailabilityLightBlue : const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? kAvailabilityBlue : const Color(0xFFD9E7FF),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: kAvailabilityBlue, size: 18),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: kAvailabilityText,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                color: kAvailabilityMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      decoration: const BoxDecoration(
        color: kAvailabilityPageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewCard(),
          const SizedBox(height: 14),
          _buildAvailabilityTableCard(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAvailabilityPageBg,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: kAvailabilityBlue),
            )
          : SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHero(),
                  Transform.translate(
                    offset: const Offset(0, -14),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: _buildContentPanel(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TimeValue {
  final int hour12;
  final int minute;
  final String period;

  const _TimeValue({
    required this.hour12,
    required this.minute,
    required this.period,
  });

  int get hour24 {
    if (period == 'PM') return hour12 == 12 ? 12 : hour12 + 12;
    return hour12 == 12 ? 0 : hour12;
  }

  String get label => '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

class _PickedRange {
  final _TimeValue from;
  final _TimeValue to;

  const _PickedRange({required this.from, required this.to});
}

class _BatchAvailabilitySelection {
  final List<int> weekdays;
  final bool isAllDay;
  final _TimeValue? from;
  final _TimeValue? to;

  const _BatchAvailabilitySelection({
    required this.weekdays,
    required this.isAllDay,
    this.from,
    this.to,
  });
}

class _AvailabilitySlot {
  final int weekday;
  final bool isAllDay;
  final _TimeValue? from;
  final _TimeValue? to;

  const _AvailabilitySlot({
    required this.weekday,
    required this.isAllDay,
    this.from,
    this.to,
  });

  factory _AvailabilitySlot.allDay({required int weekday}) {
    return _AvailabilitySlot(weekday: weekday, isAllDay: true);
  }

  factory _AvailabilitySlot.fromRange({
    required int weekday,
    required _TimeValue from,
    required _TimeValue to,
  }) {
    return _AvailabilitySlot(
      weekday: weekday,
      isAllDay: false,
      from: from,
      to: to,
    );
  }

  factory _AvailabilitySlot.fromMap(Map<String, dynamic> map) {
    final startsAtValue = map['startsAt'];
    final dateValue = map['date'];
    final startsAt = startsAtValue is Timestamp ? startsAtValue.toDate() : null;
    final date = dateValue is Timestamp ? dateValue.toDate() : null;
    final weekday =
        (map['weekday'] as num?)?.toInt() ??
        date?.weekday ??
        startsAt?.weekday ??
        1;
    final isAllDay = map['allDay'] == true;

    final from = _TimeValue(
      hour12:
          (map['fromHour'] as num?)?.toInt() ??
          (map['hour'] as num?)?.toInt() ??
          8,
      minute:
          (map['fromMinute'] as num?)?.toInt() ??
          (map['minute'] as num?)?.toInt() ??
          0,
      period:
          (map['fromPeriod'] as String?) ?? (map['period'] as String?) ?? 'PM',
    );
    final to = _TimeValue(
      hour12: (map['toHour'] as num?)?.toInt() ?? 10,
      minute: (map['toMinute'] as num?)?.toInt() ?? 0,
      period: (map['toPeriod'] as String?) ?? 'PM',
    );

    return _AvailabilitySlot(
      weekday: weekday,
      isAllDay: isAllDay,
      from: isAllDay ? null : from,
      to: isAllDay ? null : to,
    );
  }

  String get fromLabel => from?.label ?? 'Toujours';
  String get toLabel => to?.label ?? 'Disponible';
  String get rangeLabel =>
      isAllDay ? 'Toujours disponible' : '$fromLabel - $toLabel';
  String get displayLabel => isAllDay ? 'Toujours disponible' : rangeLabel;

  Map<String, dynamic> toMap() {
    return {
      'weekday': weekday,
      'day': _weekdayNameFromNumber(weekday),
      'allDay': isAllDay,
      if (from != null) 'fromHour': from!.hour12,
      if (from != null) 'fromMinute': from!.minute,
      if (from != null) 'fromPeriod': from!.period,
      if (to != null) 'toHour': to!.hour12,
      if (to != null) 'toMinute': to!.minute,
      if (to != null) 'toPeriod': to!.period,
      'label': displayLabel,
    };
  }

  static String _weekdayNameFromNumber(int weekday) {
    const labels = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return labels[weekday - 1];
  }
}

class _TimeRangeSheet extends StatefulWidget {
  final _TimeValue? initialFrom;
  final _TimeValue? initialTo;

  const _TimeRangeSheet({this.initialFrom, this.initialTo});

  @override
  State<_TimeRangeSheet> createState() => _TimeRangeSheetState();
}

class _TimeRangeSheetState extends State<_TimeRangeSheet> {
  late int _fromHour;
  late int _fromMinute;
  late int _toHour;
  late int _toMinute;
  late String _fromPeriod;
  late String _toPeriod;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final initialFrom = widget.initialFrom;
    final initialTo = widget.initialTo;
    _fromHour = initialFrom?.hour12 ?? 8;
    _fromMinute = initialFrom?.minute ?? 0;
    _toHour = initialTo?.hour12 ?? 4;
    _toMinute = initialTo?.minute ?? 0;
    _fromPeriod = initialFrom?.period ?? 'AM';
    _toPeriod = initialTo?.period ?? 'PM';
  }

  int _minutesOfDay(_TimeValue value) => (value.hour24 * 60) + value.minute;

  Future<void> _save() async {
    final from = _TimeValue(
      hour12: _fromHour,
      minute: _fromMinute,
      period: _fromPeriod,
    );
    final to = _TimeValue(
      hour12: _toHour,
      minute: _toMinute,
      period: _toPeriod,
    );

    if (_minutesOfDay(to) <= _minutesOfDay(from)) {
      setState(() {
        _errorText = "L'heure de fin doit etre apres l'heure de debut.";
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, _PickedRange(from: from, to: to));
  }

  @override
  Widget build(BuildContext context) {
    final fromPreview = _TimeValue(
      hour12: _fromHour,
      minute: _fromMinute,
      period: _fromPeriod,
    );
    final toPreview = _TimeValue(
      hour12: _toHour,
      minute: _toMinute,
      period: _toPeriod,
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Choisissez une plage horaire',
                style: TextStyle(
                  color: kAvailabilityText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${fromPreview.label} - ${toPreview.label}',
                style: const TextStyle(
                  color: kAvailabilityBlue,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 18),
              _editorCard(
                title: 'De',
                period: _fromPeriod,
                onPeriodChanged: (value) => setState(() => _fromPeriod = value),
                selectedHour: _fromHour,
                selectedMinute: _fromMinute,
                onHourChanged: (value) => setState(() => _fromHour = value),
                onMinuteChanged: (value) => setState(() => _fromMinute = value),
              ),
              const SizedBox(height: 12),
              _editorCard(
                title: 'A',
                period: _toPeriod,
                onPeriodChanged: (value) => setState(() => _toPeriod = value),
                selectedHour: _toHour,
                selectedMinute: _toMinute,
                onHourChanged: (value) => setState(() => _toHour = value),
                onMinuteChanged: (value) => setState(() => _toMinute = value),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Text(
                    _errorText!,
                    style: const TextStyle(
                      color: Color(0xFFBE123C),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAvailabilityBlue,
                        side: const BorderSide(color: kAvailabilityBlue),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Retour'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAvailabilityBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editorCard({
    required String title,
    required String period,
    required ValueChanged<String> onPeriodChanged,
    required int selectedHour,
    required int selectedMinute,
    required ValueChanged<int> onHourChanged,
    required ValueChanged<int> onMinuteChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: kAvailabilityText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEF8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: ['AM', 'PM'].map((item) {
                final selected = item == period;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onPeriodChanged(item),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? kAvailabilityBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        item,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : kAvailabilityMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _wheelPicker(
                  title: 'Heure',
                  selectedValue: selectedHour,
                  values: List<int>.generate(12, (index) => index + 1),
                  onChanged: onHourChanged,
                  formatter: (value) => value.toString().padLeft(2, '0'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _wheelPicker(
                  title: 'Minute',
                  selectedValue: selectedMinute,
                  values: List<int>.generate(60, (index) => index),
                  onChanged: onMinuteChanged,
                  formatter: (value) => value.toString().padLeft(2, '0'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wheelPicker({
    required String title,
    required int selectedValue,
    required List<int> values,
    required ValueChanged<int> onChanged,
    required String Function(int value) formatter,
  }) {
    final selectedIndex = values
        .indexOf(selectedValue)
        .clamp(0, values.length - 1);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: kAvailabilityMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                initialItem: selectedIndex,
              ),
              itemExtent: 38,
              useMagnifier: true,
              magnification: 1.08,
              selectionOverlay: Container(
                decoration: BoxDecoration(
                  color: kAvailabilityLightBlue.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onSelectedItemChanged: (index) => onChanged(values[index]),
              children: values
                  .map(
                    (value) => Center(
                      child: Text(
                        formatter(value),
                        style: const TextStyle(
                          color: kAvailabilityText,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
