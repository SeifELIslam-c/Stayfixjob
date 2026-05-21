import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons_flutter.dart';

import 'home_screen.dart';

const kCalendarBlue = Color(0xFF0F63FF);
const kCalendarDeepBlue = Color(0xFF2563EB);
const kCalendarDarkBlue = Color(0xFF0047D8);
const kCalendarPageBg = Color(0xFFF7FAFF);
const kCalendarText = Color(0xFF0F172A);
const kCalendarBody = Color(0xFF475569);
const kCalendarMuted = Color(0xFF64748B);
const kCalendarBorder = Color(0xFFE2E8F0);
const kCalendarLightBlue = Color(0xFFEFF6FF);
const kCalendarSoftBlue = Color(0xFFDDEBFF);
const kCalendarGreen = Color(0xFF22C55E);
const kCalendarLightGreen = Color(0xFFECFDF3);
const kCalendarPending = Color(0xFFF59E0B);
const kCalendarLightPending = Color(0xFFFFF7E6);

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final DateTime _today = DateTime.now();

  List<DateTime> _libreDays = [];
  List<int> _availableWeekDays = [];
  List<Map<String, dynamic>> _availabilitySlots = [];
  bool? _planningApproved;
  bool _isLoading = true;

  late DateTime _startOfWeek;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _setWeekFromDate(_today, updateState: false);
    initializeDateFormatting('fr_FR', null).then((_) => _loadData());
  }

  DateTime _cleanDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _setWeekFromDate(DateTime targetDate, {bool updateState = true}) {
    final cleanDate = _cleanDate(targetDate);
    final dayOfWeek = cleanDate.weekday == DateTime.sunday
        ? 0
        : cleanDate.weekday;
    final startOfWeek = cleanDate.subtract(Duration(days: dayOfWeek));

    if (updateState) {
      setState(() {
        _startOfWeek = startOfWeek;
        _selectedDate = cleanDate;
      });
    } else {
      _startOfWeek = startOfWeek;
      _selectedDate = cleanDate;
    }
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
          final libreDaysRaw = data['libreDays'];
          final availabilitySlotsRaw = data['availabilitySlots'];

          setState(() {
            _libreDays = libreDaysRaw is List
                ? libreDaysRaw
                      .whereType<Timestamp>()
                      .map((ts) => _cleanDate(ts.toDate()))
                      .toList()
                : [];
            final storedAvailableDays = List<int>.from(
              data['availableWeekDays'] ?? const <int>[],
            )..sort();
            final storedWorkDays = List<int>.from(
              data['permanentWorkDays'] ?? const <int>[],
            )..sort();
            _availableWeekDays = storedAvailableDays.isNotEmpty
                ? storedAvailableDays
                : storedWorkDays.isNotEmpty
                ? List<int>.generate(
                    7,
                    (index) => index + 1,
                  ).where((day) => !storedWorkDays.contains(day)).toList()
                : <int>[];
            _availabilitySlots = availabilitySlotsRaw is List
                ? availabilitySlotsRaw
                      .whereType<Map>()
                      .map((slot) => Map<String, dynamic>.from(slot))
                      .toList()
                : [];
            _planningApproved = data['planningApproved'] as bool?;
          });

          _libreDays.sort((a, b) => a.compareTo(b));
          _availableWeekDays.sort();
        }
      }
    } catch (e) {
      debugPrint('Erreur chargement calendrier: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isLibreDay(DateTime date) {
    final cleanDate = _cleanDate(date);
    return _libreDays.any((d) => _isSameDate(d, cleanDate));
  }

  bool _isAvailableDay(DateTime date) {
    if (_availableWeekDays.isNotEmpty) {
      return _availableWeekDays.contains(date.weekday);
    }
    return _isLibreDay(date);
  }

  Map<String, dynamic>? _slotForWeekday(int weekday) {
    for (final slot in _availabilitySlots) {
      final slotWeekday = (slot['weekday'] as num?)?.toInt();
      if (slotWeekday == weekday) return slot;
    }
    return null;
  }

  bool _isConfiguredDay(DateTime date) {
    return _slotForWeekday(date.weekday) != null;
  }

  Future<void> _handleBack() async {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
      (route) => false,
    );
  }

  List<DateTime> _selectedWeekDates() {
    return List.generate(7, (index) => _startOfWeek.add(Duration(days: index)));
  }

  List<DateTime> _weekPlanDates() {
    return _selectedWeekDates().where((date) => _isAvailableDay(date)).toList();
  }

  int _availableDaysCount() {
    return _selectedWeekDates().where(_isAvailableDay).length;
  }

  int _configuredDaysCount() {
    return _selectedWeekDates().where(_isConfiguredDay).length;
  }

  String _weekRangeLabel() {
    final endOfWeek = _startOfWeek.add(const Duration(days: 6));
    final sameMonth = _startOfWeek.month == endOfWeek.month;
    final sameYear = _startOfWeek.year == endOfWeek.year;

    if (sameMonth && sameYear) {
      return '${_startOfWeek.day} ${DateFormat('MMMM', 'fr_FR').format(_startOfWeek)} - '
          '${endOfWeek.day} ${DateFormat('MMMM yyyy', 'fr_FR').format(endOfWeek)}';
    }

    return '${DateFormat('d MMM', 'fr_FR').format(_startOfWeek)} - '
        '${DateFormat('d MMM yyyy', 'fr_FR').format(endOfWeek)}';
  }

  String _approvalLabel() {
    if (_planningApproved == true) return 'Planning approuve';
    return 'Planning en attente';
  }

  Color _approvalBackground() {
    if (_planningApproved == true) return kCalendarLightGreen;
    return kCalendarLightPending;
  }

  Color _approvalForeground() {
    if (_planningApproved == true) return const Color(0xFF15803D);
    return const Color(0xFFB45309);
  }

  IconData _approvalIcon() {
    if (_planningApproved == true) return LucideIcons.checkCircle2;
    return LucideIcons.clock3;
  }

  String _statusSummary() {
    if (_planningApproved == true) return 'Approuve';
    return 'En attente';
  }

  String _dayTypeLabel(DateTime date) {
    final slot = _slotForWeekday(date.weekday);
    if (slot == null) return 'Disponible';
    if (slot['allDay'] == true) return 'Toujours disponible';

    final fromHour = (slot['fromHour'] as num?)?.toInt();
    final fromMinute = (slot['fromMinute'] as num?)?.toInt();
    final fromPeriod = slot['fromPeriod'] as String?;
    final toHour = (slot['toHour'] as num?)?.toInt();
    final toMinute = (slot['toMinute'] as num?)?.toInt();
    final toPeriod = slot['toPeriod'] as String?;

    if (fromHour != null &&
        fromMinute != null &&
        fromPeriod != null &&
        toHour != null &&
        toMinute != null &&
        toPeriod != null) {
      final fromText =
          '$fromHour:${fromMinute.toString().padLeft(2, '0')} $fromPeriod';
      final toText = '$toHour:${toMinute.toString().padLeft(2, '0')} $toPeriod';
      return '$fromText - $toText';
    }

    return (slot['label'] as String?) ?? 'Disponible';
  }

  String _weekdayLabel(DateTime date) {
    final label = DateFormat('EEEE', 'fr_FR').format(date);
    return '${label[0].toUpperCase()}${label.substring(1)}';
  }

  String _monthBadge(DateTime date) {
    return DateFormat('MMM', 'fr_FR').format(date).toUpperCase();
  }

  List<DateTime?> _monthCells(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final leadingEmpty = firstDay.weekday % 7;
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[];

    for (var i = 0; i < leadingEmpty; i++) {
      cells.add(null);
    }

    for (var day = 1; day <= totalDays; day++) {
      cells.add(DateTime(month.year, month.month, day));
    }

    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return cells;
  }

  bool _isInPickerWeek(DateTime date, DateTime pickerStart) {
    final start = _cleanDate(pickerStart);
    final end = start.add(const Duration(days: 6));
    return !date.isBefore(start) && !date.isAfter(end);
  }

  Future<void> _openWeekPicker() async {
    DateTime tempSelectedDate = _selectedDate;
    DateTime tempMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final tempStartOfWeek = _cleanDate(tempSelectedDate).subtract(
              Duration(
                days: tempSelectedDate.weekday == DateTime.sunday
                    ? 0
                    : tempSelectedDate.weekday,
              ),
            );
            final cells = _monthCells(tempMonth);

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
                      'Selectionnez une semaine',
                      style: TextStyle(
                        color: kCalendarText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _sheetArrowButton(
                          icon: LucideIcons.chevronLeft,
                          onTap: () {
                            setModalState(() {
                              tempMonth = DateTime(
                                tempMonth.year,
                                tempMonth.month - 1,
                                1,
                              );
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            _capitalizeMonth(
                              DateFormat(
                                'MMMM yyyy',
                                'fr_FR',
                              ).format(tempMonth),
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: kCalendarText,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _sheetArrowButton(
                          icon: LucideIcons.chevronRight,
                          onTap: () {
                            setModalState(() {
                              tempMonth = DateTime(
                                tempMonth.year,
                                tempMonth.month + 1,
                                1,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: const ['D', 'L', 'M', 'M', 'J', 'V', 'S']
                          .map(
                            (day) => Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: TextStyle(
                                    color: kCalendarMuted,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cells.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 2,
                            childAspectRatio: 1.06,
                          ),
                      itemBuilder: (context, index) {
                        final date = cells[index];
                        if (date == null) {
                          return const SizedBox.shrink();
                        }

                        final isToday = _isSameDate(date, _today);
                        final isStart = _isSameDate(date, tempStartOfWeek);
                        final isInRange = _isInPickerWeek(
                          date,
                          tempStartOfWeek,
                        );
                        final inCurrentMonth = date.month == tempMonth.month;

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              tempSelectedDate = date;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isInRange
                                  ? kCalendarLightBlue
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isStart ? kCalendarBlue : Colors.white,
                                  shape: BoxShape.circle,
                                  border: isToday
                                      ? Border.all(
                                          color: kCalendarBlue,
                                          width: 1.8,
                                        )
                                      : null,
                                  boxShadow: isStart
                                      ? const [
                                          BoxShadow(
                                            color: Color(0x220F63FF),
                                            blurRadius: 10,
                                            offset: Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      color: !inCurrentMonth
                                          ? const Color(0xFFCBD5E1)
                                          : isStart
                                          ? Colors.white
                                          : kCalendarText,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kCalendarBlue,
                              side: const BorderSide(color: kCalendarBlue),
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _setWeekFromDate(tempSelectedDate);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kCalendarBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(54),
                              elevation: 0,
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

  String _capitalizeMonth(String text) {
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
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

  Widget _sheetArrowButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCalendarBorder),
        ),
        child: Icon(icon, color: kCalendarBlue, size: 20),
      ),
    );
  }

  BoxDecoration _whiteCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: kCalendarBorder),
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
      height: 282,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('lib/assets/calendrierheroimg.png', fit: BoxFit.cover),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 70),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroButton(icon: LucideIcons.arrowLeft, onTap: _handleBack),
                  const Spacer(),
                  const Text(
                    'Calendrier',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(
                    width: 220,
                    child: Text(
                      'Vue hebdomadaire de votre planning',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
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

  Widget _buildWeekSelectorCard() {
    final weekDates = _selectedWeekDates();
    const labels = ['D', 'L', 'M', 'M', 'J', 'V', 'S'];

    return GestureDetector(
      onTap: _openWeekPicker,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: _whiteCardDecoration(),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: kCalendarLightBlue,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    LucideIcons.calendarDays,
                    color: kCalendarBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _capitalizeMonth(_weekRangeLabel()),
                    style: const TextStyle(
                      color: kCalendarText,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const Icon(
                  LucideIcons.chevronDown,
                  color: kCalendarMuted,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: List.generate(7, (index) {
                final date = weekDates[index];
                final isSelected = _isSameDate(date, _selectedDate);
                final isToday = _isSameDate(date, _today);
                final isAvailable = _isAvailableDay(date);
                final isConfigured = _isConfiguredDay(date);

                Color background = Colors.transparent;
                Color borderColor = Colors.transparent;
                Color textColor = kCalendarText;

                if (isAvailable) {
                  background = kCalendarLightBlue;
                  textColor = kCalendarBlue;
                }
                if (isSelected) {
                  background = kCalendarBlue;
                  textColor = Colors.white;
                }
                if (isToday && !isSelected) {
                  borderColor = kCalendarBlue;
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDate = date),
                    child: Column(
                      children: [
                        Text(
                          labels[index],
                          style: const TextStyle(
                            color: kCalendarMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: background,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: borderColor,
                              width: borderColor == Colors.transparent
                                  ? 0
                                  : 1.8,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 7,
                          height: 7,
                          child: isConfigured
                              ? const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: kCalendarGreen,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : isAvailable
                              ? const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: kCalendarBlue,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _approvalBackground(),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _approvalForeground().withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_approvalIcon(), color: _approvalForeground(), size: 18),
          const SizedBox(width: 8),
          Text(
            _approvalLabel(),
            style: TextStyle(
              color: _approvalForeground(),
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
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
            color: kCalendarText,
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
                iconColor: kCalendarBlue,
                iconBackground: kCalendarLightBlue,
                value: '${_availableDaysCount()}',
                label: 'Jours dispo',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _overviewStat(
                icon: LucideIcons.clock3,
                iconColor: kCalendarGreen,
                iconBackground: kCalendarLightGreen,
                value: '${_configuredDaysCount()}',
                label: 'Jours regles',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _overviewStat(
                icon: LucideIcons.shieldCheck,
                iconColor: kCalendarBlue,
                iconBackground: kCalendarLightBlue,
                value: _statusSummary(),
                label: 'Statut',
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
    required Color iconColor,
    required Color iconBackground,
    required String value,
    required String label,
    bool compact = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kCalendarBorder),
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
              color: kCalendarText,
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
              color: kCalendarMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekPlanSection() {
    final planDates = _weekPlanDates();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Planning de la semaine',
          style: TextStyle(
            color: kCalendarText,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 14),
        if (planDates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kCalendarBorder),
            ),
            child: const Text(
              'Aucun jour disponible defini pour cette semaine.',
              style: TextStyle(
                color: kCalendarMuted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: planDates.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.72,
            ),
            itemBuilder: (context, index) {
              final date = planDates[index];
              final slot = _slotForWeekday(date.weekday);
              final isAllDay = slot?['allDay'] == true;
              final isConfigured = slot != null;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: kCalendarBorder),
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
                      width: 54,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isConfigured
                              ? const [kCalendarBlue, kCalendarDeepBlue]
                              : const [Color(0xFF60A5FA), Color(0xFF2563EB)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _monthBadge(date),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${date.day}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _weekdayLabel(date),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: kCalendarText,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isConfigured
                                  ? kCalendarLightGreen
                                  : kCalendarLightBlue,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _dayTypeLabel(date),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isConfigured
                                    ? const Color(0xFF15803D)
                                    : kCalendarBlue,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isAllDay
                          ? LucideIcons.sun
                          : isConfigured
                          ? LucideIcons.clock3
                          : LucideIcons.sparkles,
                      color: isConfigured ? kCalendarGreen : kCalendarBlue,
                      size: 22,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildContentPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      decoration: const BoxDecoration(
        color: kCalendarPageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeekSelectorCard(),
          const SizedBox(height: 12),
          _buildApprovalBadge(),
          const SizedBox(height: 14),
          _buildOverviewCard(),
          const SizedBox(height: 14),
          _buildWeekPlanSection(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCalendarPageBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kCalendarBlue))
          : SingleChildScrollView(
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
