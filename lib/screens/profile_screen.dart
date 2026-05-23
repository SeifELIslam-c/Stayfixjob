import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/profile_formatters.dart';
import '../widgets/address_picker.dart';
import '../widgets/cv_preview_carousel.dart';
import '../widgets/premium_bottom_sheets.dart';
import 'availability_screen.dart';
import 'cv_privacy_screen.dart';
import 'home_screen.dart';

const kProfileBlue = Color(0xFF0F63FF);
const kProfileDeepBlue = Color(0xFF2563EB);
const kProfileDarkBlue = Color(0xFF0047D8);
const kProfilePageBg = Color(0xFFF7FAFF);
const kProfileText = Color(0xFF0F172A);
const kProfileMuted = Color(0xFF64748B);
const kProfileBody = Color(0xFF475569);
const kProfileBorder = Color(0xFFE2E8F0);
const kProfileLightBlue = Color(0xFFEFF6FF);
const kProfileSuccess = Color(0xFF22C55E);
const kProfileWarning = Color(0xFFF97316);

enum ProfileSection {
  personal,
  cv,
  department,
  specialties,
  address,
  birthday,
  availability,
}

class ProfileScreen extends StatefulWidget {
  final bool completionMode;

  const ProfileScreen({super.key, this.completionMode = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const String _singleSkillDepartment = "Main-d'oeuvre qualifiee";
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _departmentSectionKey = GlobalKey();
  final GlobalKey _specialtiesSectionKey = GlobalKey();
  final GlobalKey _availabilitySectionKey = GlobalKey();
  bool _isLoading = true;
  String _department = '';
  List<String> _selectedSpecialties = [];
  String? _cvFileName;
  String? _cvBase64;
  String? _photoBase64;
  String _address = '';
  double? _addressLatitude;
  double? _addressLongitude;
  String _dob = '';
  String _username = '';
  String _phone = '';
  String _phoneCountryIso = '';
  String _phoneDialCode = '';
  String _email = '';

  // ── Poste actuel ──────────────────────────────────────────────────────────
  String _jobLocation = '';
  String _jobAddress = '';
  String _jobStartDate = '';
  double? _jobAddressLatitude;
  double? _jobAddressLongitude;
  DateTime? _createdAt;
  List<DateTime> _libreDays = [];
  List<int> _availableWeekDays = [];
  List<Map<String, dynamic>> _availabilitySlots = [];
  int? _departmentExperienceYears;
  Map<String, int> _specialtyExperienceYears = {};
  ProfileSection? _openSection;
  Set<int> _quickAvailabilityDays = <int>{};
  bool _quickAvailabilityAllDay = true;
  TimeOfDay _quickAvailabilityFrom = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _quickAvailabilityTo = const TimeOfDay(hour: 16, minute: 0);
  bool _didRunCompletionAutofocus = false;
  List<String> _pendingRoles = [];

  // ignore: prefer_final_fields
  List<Map<String, dynamic>> _departmentsData = [
    {
      'name': 'Maintenance generale',
      'color': Colors.blue,
      'specialties': ['Bricolage', 'Aide generale', 'Jardinage paysager'],
    },
    {
      'name': "Main-d'oeuvre qualifiee",
      'color': Colors.purple,
      'specialties': [
        'Plomberie professionnelle',
        'Electricite avancee',
        'Climatisation & chauffage',
        'Maconnerie professionnelle',
        'Menuiserie generale',
        'Peinture decorative',
        'Soudure industrielle',
      ],
    },
    {
      'name': 'Prepose aux chambres',
      'color': Colors.pink,
      'specialties': [
        'Nettoyage des chambres',
        'Gestion du linge',
        'Remise en etat des chambres',
      ],
    },
    {
      'name': 'Houseman',
      'color': Colors.orange,
      'specialties': [
        'Transport bagages',
        'Entretien couloirs',
        'Soutien Housekeeping',
      ],
    },
    {
      'name': 'Concierge',
      'color': Colors.teal,
      'specialties': [
        'Accueil clients',
        'Service information',
        'Gestion des bagages',
        'Reservations & services',
        'Assistance VIP',
      ],
    },
    {
      'name': 'Menage',
      'color': Colors.green,
      'specialties': [
        'Nettoyage des chambres',
        'Nettoyage espaces communs',
        'Gestion du linge',
        'Desinfection & hygiene',
        'Remise en etat des chambres',
      ],
    },
  ];

  String _normalizeDepartmentName(String value) {
    final normalized = value.trim();
    switch (normalized) {
      case 'Maintenance generale':
      case 'Maintenance générale':
        return 'Maintenance generale';
      case "Main-d'oeuvre qualifiee":
      case "Main-d’œuvre qualifiee":
      case "Main-d'oeuvre qualifieé":
      case "Main-d'œuvre qualifiee":
      case "Main-d'œuvre qualifieé":
      case "Main-d'œuvre qualifiee ":
      case "Main-d'œuvre qualifiée":
        return "Main-d'oeuvre qualifiee";
      case 'Prepose aux chambres':
      case 'Préposé aux chambres':
        return 'Prepose aux chambres';
      case 'Menage':
      case 'Ménage':
        return 'Menage';
      default:
        return normalized;
    }
  }

  String _normalizeSpecialtyName(String value) {
    final normalized = value.trim();
    switch (normalized) {
      case 'Aide generale':
      case 'Aide générale':
        return 'Aide generale';
      case 'Electricite avancee':
      case 'Électricité avancee':
      case 'Électricité avancée':
        return 'Electricite avancee';
      case 'Maconnerie professionnelle':
      case 'Maçonnerie professionnelle':
        return 'Maconnerie professionnelle';
      case 'Menuiserie':
      case 'Menuiserie generale':
      case 'Menuiserie générale':
        return 'Menuiserie generale';
      case 'Peinture professionnelle':
      case 'Peinture decorative':
      case 'Peinture décorative':
        return 'Peinture decorative';
      case 'Nettoyage VIP':
        return 'Nettoyage des chambres';
      case 'Lavage':
        return 'Gestion du linge';
      case 'Organisation':
        return 'Remise en etat des chambres';
      case 'Remise en état des chambres':
        return 'Remise en etat des chambres';
      case 'Désinfection & hygiène':
        return 'Desinfection & hygiene';
      default:
        return normalized;
    }
  }

  List<String> _normalizeSpecialtiesForDepartment(
    Iterable<dynamic> values,
    String department,
  ) {
    final normalizedDepartment = _normalizeDepartmentName(department);
    final baseSpecialties = _departmentsData
        .where((dept) => dept['name'] == normalizedDepartment)
        .expand((dept) => List<String>.from(dept['specialties'] as List))
        .toSet();

    final seen = <String>{};
    final result = <String>[];

    for (final value in values) {
      final specialty = _normalizeSpecialtyName(value.toString());
      if (specialty.isEmpty || !seen.add(specialty)) continue;
      result.add(specialty);
      baseSpecialties.add(specialty);
    }

    if (baseSpecialties.isNotEmpty) {
      for (var i = 0; i < _departmentsData.length; i++) {
        if (_departmentsData[i]['name'] == normalizedDepartment) {
          _departmentsData[i]['specialties'] = baseSpecialties.toList();
        }
      }
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool _hasDepartment() => _department.trim().isNotEmpty;

  bool _hasSpecialties() => _selectedSpecialties.isNotEmpty;

  bool _hasDepartmentExperience() => (_departmentExperienceYears ?? 0) > 0;

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

  bool _hasAddress() => _address.trim().isNotEmpty;

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

  void _syncQuickAvailabilityEditor() {
    _quickAvailabilityDays = <int>{};

    if (_availabilitySlots.isEmpty) {
      _quickAvailabilityAllDay = true;
      _quickAvailabilityFrom = const TimeOfDay(hour: 8, minute: 0);
      _quickAvailabilityTo = const TimeOfDay(hour: 16, minute: 0);
      return;
    }

    final firstSlot = _availabilitySlots.first;
    final isAllDay = firstSlot['allDay'] == true;
    _quickAvailabilityAllDay = isAllDay;

    if (isAllDay) return;

    _quickAvailabilityFrom = _timeOfDayFromStoredSlot(
      hour: (firstSlot['fromHour'] as num?)?.toInt(),
      minute: (firstSlot['fromMinute'] as num?)?.toInt(),
      period: firstSlot['fromPeriod'] as String?,
      fallback: const TimeOfDay(hour: 8, minute: 0),
    );
    _quickAvailabilityTo = _timeOfDayFromStoredSlot(
      hour: (firstSlot['toHour'] as num?)?.toInt(),
      minute: (firstSlot['toMinute'] as num?)?.toInt(),
      period: firstSlot['toPeriod'] as String?,
      fallback: const TimeOfDay(hour: 16, minute: 0),
    );
  }

  Map<String, dynamic>? _quickAvailabilitySlotForWeekday(int weekday) {
    for (final slot in _availabilitySlots) {
      final slotWeekday = (slot['weekday'] as num?)?.toInt();
      if (slotWeekday == weekday) {
        return Map<String, dynamic>.from(slot);
      }
    }
    return null;
  }

  void _selectQuickAvailabilityDay(int weekday) {
    final existingSlot = _quickAvailabilitySlotForWeekday(weekday);

    setState(() {
      _quickAvailabilityDays = <int>{weekday};

      if (existingSlot == null) {
        _quickAvailabilityAllDay = true;
        _quickAvailabilityFrom = const TimeOfDay(hour: 8, minute: 0);
        _quickAvailabilityTo = const TimeOfDay(hour: 16, minute: 0);
        return;
      }

      final isAllDay = existingSlot['allDay'] == true;
      _quickAvailabilityAllDay = isAllDay;

      if (isAllDay) {
        _quickAvailabilityFrom = const TimeOfDay(hour: 8, minute: 0);
        _quickAvailabilityTo = const TimeOfDay(hour: 16, minute: 0);
        return;
      }

      _quickAvailabilityFrom = _timeOfDayFromStoredSlot(
        hour: (existingSlot['fromHour'] as num?)?.toInt(),
        minute: (existingSlot['fromMinute'] as num?)?.toInt(),
        period: existingSlot['fromPeriod'] as String?,
        fallback: const TimeOfDay(hour: 8, minute: 0),
      );
      _quickAvailabilityTo = _timeOfDayFromStoredSlot(
        hour: (existingSlot['toHour'] as num?)?.toInt(),
        minute: (existingSlot['toMinute'] as num?)?.toInt(),
        period: existingSlot['toPeriod'] as String?,
        fallback: const TimeOfDay(hour: 16, minute: 0),
      );
    });
  }

  int? _selectedQuickAvailabilityDay() {
    if (_quickAvailabilityDays.isEmpty) return null;
    return _quickAvailabilityDays.first;
  }

  bool _selectedQuickAvailabilityDayHasSavedSlot() {
    final selectedDay = _selectedQuickAvailabilityDay();
    if (selectedDay == null) return false;
    return _quickAvailabilitySlotForWeekday(selectedDay) != null;
  }

  Future<void> _startCompletionModeIfNeeded() async {
    if (!widget.completionMode || !mounted || _didRunCompletionAutofocus) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    _didRunCompletionAutofocus = true;
    if (!_hasDepartment()) {
      setState(() {
        _openSection = ProfileSection.department;
      });
      await _scrollToKey(_departmentSectionKey);
      return;
    }

    if (!_hasSpecialties()) {
      setState(() {
        _openSection = ProfileSection.specialties;
      });
      await _scrollToKey(_specialtiesSectionKey);
      return;
    }

    if (!_hasDepartmentExperience()) {
      setState(() {
        _openSection = ProfileSection.specialties;
      });
      await _scrollToKey(_specialtiesSectionKey);
      return;
    }

    setState(() {
      _openSection = null;
    });
    await _scrollToKey(_availabilitySectionKey);
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _email = user.email ?? '';

        final approvedRoles = await FirebaseFirestore.instance
            .collection('role_requests')
            .where('status', isEqualTo: 'approved')
            .get();

        for (final doc in approvedRoles.docs) {
          final deptName = doc.data()['department'];
          final newRole = doc.data()['finalRole'];

          if (newRole != null) {
            for (var i = 0; i < _departmentsData.length; i++) {
              if (_departmentsData[i]['name'] == deptName) {
                final specs = List<String>.from(
                  _departmentsData[i]['specialties'],
                );
                if (!specs.contains(newRole)) {
                  specs.add(newRole);
                  _departmentsData[i]['specialties'] = specs;
                }
              }
            }
          }
        }

        final doc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .get();

        if (doc.exists && mounted) {
          final data = doc.data()!;
          final libreDaysRaw = data['libreDays'];
          final availabilitySlotsRaw = data['availabilitySlots'];
          final specialtyExperienceRaw = data['specialtyExperienceYears'];
          final normalizedDepartment = _normalizeDepartmentName(
            data['department'] ?? '',
          );
          final storedSpecialties = _normalizeSpecialtiesForDepartment(
            _uniqueSpecialties(data['specialties'] ?? []),
            normalizedDepartment,
          );
          setState(() {
            _department = normalizedDepartment;
            _selectedSpecialties = storedSpecialties;
            _cvFileName = data['cvFileName'];
            _cvBase64 = data['cvBase64'];
            _photoBase64 = data['photoBase64'];
            _address = data['address'] ?? '';
            _addressLatitude = (data['addressLatitude'] as num?)?.toDouble();
            _addressLongitude = (data['addressLongitude'] as num?)?.toDouble();
            _dob = data['dob'] ?? '';
            _username = data['username'] ?? '';
            _phone = data['phone'] ?? '';
            _phoneCountryIso = data['phoneCountryIso'] ?? '';
            _phoneDialCode = data['phoneDialCode'] ?? '';
            _jobLocation = (data['jobLocation'] as String? ?? '').trim();
            _jobAddress = (data['jobAddress'] as String? ?? '').trim();
            _jobStartDate = (data['jobStartDate'] as String? ?? '').trim();
            _jobAddressLatitude =
                (data['jobAddressLatitude'] as num?)?.toDouble();
            _jobAddressLongitude =
                (data['jobAddressLongitude'] as num?)?.toDouble();
            _createdAt = data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate()
                : null;
            _libreDays = libreDaysRaw is List
                ? libreDaysRaw
                      .whereType<Timestamp>()
                      .map((ts) => ts.toDate())
                      .toList()
                : [];
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
            _availabilitySlots = availabilitySlotsRaw is List
                ? availabilitySlotsRaw
                      .whereType<Map>()
                      .map((slot) => Map<String, dynamic>.from(slot))
                      .toList()
                : [];
            _departmentExperienceYears =
                (data['departmentExperienceYears'] as num?)?.toInt();
            if ((_departmentExperienceYears ?? 0) <= 0 &&
                specialtyExperienceRaw is Map) {
              for (final value in specialtyExperienceRaw.values) {
                final years = (value as num?)?.toInt() ?? 0;
                if (years > 0) {
                  _departmentExperienceYears = years;
                  break;
                }
              }
            }
            _specialtyExperienceYears = specialtyExperienceRaw is Map
                ? specialtyExperienceRaw.map(
                    (key, value) =>
                        MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
                  )
                : <String, int>{};
            _syncQuickAvailabilityEditor();
            _phone = buildPhoneDisplay(
              phone: _phone,
              countryIso: _phoneCountryIso,
              dialCode: _phoneDialCode,
            ).formatted;
          });
          _libreDays.sort((a, b) => a.compareTo(b));
        }

        // Load pending roles from workers collection
        final workerDoc = await FirebaseFirestore.instance
            .collection('workers')
            .doc(user.uid)
            .get();
        if (workerDoc.exists && mounted) {
          final pendingRaw = workerDoc.data()?['pendingRoles'];
          setState(() {
            _pendingRoles = List<String>.from(pendingRaw ?? []);
          });
        }

        _checkNotifications();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startCompletionModeIfNeeded();
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('role_requests')
        .where('userId', isEqualTo: user.uid)
        .where('status', whereIn: ['approved', 'declined'])
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['notified'] == true) continue;

      final status = data['status'];
      final requestedRole = data['requestedRole'];
      final finalRole = data['finalRole'] ?? requestedRole;

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  status == 'approved'
                      ? LucideIcons.checkCircle
                      : LucideIcons.xCircle,
                  color: status == 'approved' ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(
                  status == 'approved'
                      ? 'Demande approuvee'
                      : 'Demande refusee',
                ),
              ],
            ),
            content: Text(
              status == 'approved'
                  ? "Votre demande pour ajouter le role '$requestedRole' a ete acceptee${finalRole != requestedRole ? " sous le nom '$finalRole'" : ''}."
                  : "Votre demande pour ajouter le role '$requestedRole' a ete refusee.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Compris'),
              ),
            ],
          ),
        );
      }

      await doc.reference.update({'notified': true});
    }
  }

  Future<void> _uploadPhoto() async {
    final imagePicker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 5,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFD7E4FF),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image, color: kProfileBlue),
              title: const Text(
                'Galerie',
                style: TextStyle(
                  color: kProfileText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera, color: kProfileBlue),
              title: const Text(
                'Prendre une photo',
                style: TextStyle(
                  color: kProfileText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      setState(() => _isLoading = true);

      final pickedFile = await imagePicker.pickImage(source: source);
      if (pickedFile == null) {
        setState(() => _isLoading = false);
        return;
      }

      final compressedPath = '${pickedFile.path}_compressed.jpg';
      final compressed = await FlutterImageCompress.compressAndGetFile(
        pickedFile.path,
        compressedPath,
        quality: 85,
        minWidth: 100,
        minHeight: 100,
      );

      if (compressed == null) throw 'Erreur compression';

      final bytes = await File(compressed.path).readAsBytes();
      final base64String = base64Encode(bytes);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .update({'photoBase64': base64String});

        if (mounted) {
          setState(() => _photoBase64 = base64String);
          _showInfo('Photo mise a jour.');
        }
      }
    } catch (e) {
      if (mounted) _showInfo('Erreur: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _updateAddressOrDob(String field, String currentValue) async {
    if (field == 'Date de naissance') {
      final now = DateTime.now();
      final picked = await showPremiumDatePickerSheet(
        context: context,
        initialDate:
            parseProfileDate(currentValue) ??
            DateTime(now.year - 25, now.month, now.day),
        minimumDate: DateTime(1940),
        maximumDate: DateTime(now.year - 18, now.month, now.day),
      );

      if (picked == null) return false;
      final value = formatProfileDate(picked);

      setState(() => _isLoading = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('profiles')
              .doc(user.uid)
              .update({'dob': value});
          if (mounted) setState(() => _dob = value);
        }
      } catch (e) {
        if (mounted) _showInfo('Erreur: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      if (widget.completionMode && mounted) {
        await _startCompletionModeIfNeeded();
      }
      return true;
    }

    final pickedAddress = await showAddressPicker(
      context: context,
      initialAddress: currentValue,
      initialLatitude: _addressLatitude,
      initialLongitude: _addressLongitude,
      presentation: AddressPickerPresentation.fullscreen,
    );
    if (pickedAddress == null || pickedAddress.address.trim().isEmpty) {
      return false;
    }

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .update({
              'address': pickedAddress.address.trim(),
              'addressLatitude': pickedAddress.latitude,
              'addressLongitude': pickedAddress.longitude,
            });

        if (mounted) {
          setState(() {
            _address = pickedAddress.address.trim();
            _addressLatitude = pickedAddress.latitude;
            _addressLongitude = pickedAddress.longitude;
          });
        }
      }
    } catch (e) {
      if (mounted) _showInfo('Erreur: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    if (widget.completionMode && mounted) {
      await _startCompletionModeIfNeeded();
    }
    return true;
  }

  Future<void> _changeDepartment(String newDept) async {
    final normalizedDept = _normalizeDepartmentName(newDept);
    if (_department == normalizedDept) return;

    setState(() {
      _department = normalizedDept;
      _selectedSpecialties.clear();
      _departmentExperienceYears = null;
      _specialtyExperienceYears.clear();
    });

    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid)
        .update({
          'department': normalizedDept,
          'specialties': [],
          'departmentExperienceYears': 0,
          'specialtyExperienceYears': {},
        });

    if (!mounted) return;

    await _editDepartmentExperienceYears();
    if (!mounted) return;

    if (widget.completionMode) {
      setState(() => _openSection = ProfileSection.specialties);
      await _scrollToKey(_specialtiesSectionKey);
    }
  }

  Future<void> _toggleSpecialty(String spec) async {
    final normalizedSpec = _normalizeSpecialtyName(spec);
    if (_selectedSpecialties.contains(normalizedSpec)) {
      setState(() {
        _selectedSpecialties.remove(normalizedSpec);
      });

      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({
            'specialties': _selectedSpecialties,
            'specialtyExperienceYears': {},
          });
      return;
    }

    setState(() {
      if (_department == _singleSkillDepartment) {
        _selectedSpecialties
          ..clear()
          ..add(normalizedSpec);
      } else {
        _selectedSpecialties.add(normalizedSpec);
      }
      _selectedSpecialties = _uniqueSpecialties(_selectedSpecialties);
    });

    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid)
        .update({
          'specialties': _selectedSpecialties,
          'specialtyExperienceYears': {},
        });

    if (widget.completionMode &&
        _hasSpecialties() &&
        _hasDepartmentExperience() &&
        mounted) {
      setState(() => _openSection = null);
      await _scrollToKey(_availabilitySectionKey);
    }
  }

  Future<void> _editDepartmentExperienceYears() async {
    if (_department.trim().isEmpty) return;

    final years = await _showExperienceYearsSheet(
      _department,
      initialYears: _departmentExperienceYears,
    );
    if (years == null) return;

    setState(() {
      _departmentExperienceYears = years;
    });

    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid)
        .update({
          'departmentExperienceYears': years,
          'specialtyExperienceYears': {},
        });

    if (widget.completionMode &&
        _hasSpecialties() &&
        _hasDepartmentExperience() &&
        mounted) {
      setState(() => _openSection = null);
      await _scrollToKey(_availabilitySectionKey);
    }
  }

  String _resolvedPhoneCountryIso() {
    final inferred = inferCountryIsoFromDialCode(_phoneDialCode);
    if (inferred != null && inferred.isNotEmpty) return inferred;
    if (_phoneCountryIso.trim().isNotEmpty) return _phoneCountryIso.trim();
    return 'CA';
  }

  String _composePhoneNumber(String dialCode, String nationalNumber) {
    final cleanDialCode = dialCode.replaceAll('+', '').trim();
    final cleanNumber = nationalNumber.trim();
    return cleanDialCode.isEmpty ? cleanNumber : '+$cleanDialCode$cleanNumber';
  }

  List<int> _weekdaysForQuickEditor() =>
      List<int>.generate(7, (index) => index + 1);

  String _weekdayShortLabel(int weekday) {
    const names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return names[weekday - 1];
  }

  String _weekdayLongLabel(int weekday) {
    const names = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return names[weekday - 1];
  }

  TimeOfDay _timeOfDayFromStoredSlot({
    required int? hour,
    required int? minute,
    required String? period,
    required TimeOfDay fallback,
  }) {
    if (hour == null) return fallback;
    final normalizedHour = hour.clamp(1, 12);
    var hour24 = normalizedHour % 12;
    if ((period ?? 'AM').toUpperCase() == 'PM') {
      hour24 += 12;
    }
    return TimeOfDay(hour: hour24, minute: minute ?? 0);
  }

  Map<String, dynamic> _buildAvailabilitySlotMapForQuickEditor(int weekday) {
    if (_quickAvailabilityAllDay) {
      return {
        'weekday': weekday,
        'day': _weekdayLongLabel(weekday),
        'allDay': true,
        'label': 'Toujours disponible',
      };
    }

    final fromHour24 = _quickAvailabilityFrom.hour;
    final toHour24 = _quickAvailabilityTo.hour;
    final fromHour12 = fromHour24 == 0
        ? 12
        : fromHour24 > 12
        ? fromHour24 - 12
        : fromHour24;
    final toHour12 = toHour24 == 0
        ? 12
        : toHour24 > 12
        ? toHour24 - 12
        : toHour24;
    final fromPeriod = fromHour24 >= 12 ? 'PM' : 'AM';
    final toPeriod = toHour24 >= 12 ? 'PM' : 'AM';
    final fromLabel = _formatTimeOfDay(_quickAvailabilityFrom);
    final toLabel = _formatTimeOfDay(_quickAvailabilityTo);

    return {
      'weekday': weekday,
      'day': _weekdayLongLabel(weekday),
      'allDay': false,
      'fromHour': fromHour12,
      'fromMinute': _quickAvailabilityFrom.minute,
      'fromPeriod': fromPeriod,
      'toHour': toHour12,
      'toMinute': _quickAvailabilityTo.minute,
      'toPeriod': toPeriod,
      'label': '$fromLabel - $toLabel',
    };
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _pickQuickAvailabilityTime({required bool isStart}) async {
    final initial = isStart ? _quickAvailabilityFrom : _quickAvailabilityTo;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;

    setState(() {
      if (isStart) {
        _quickAvailabilityFrom = picked;
      } else {
        _quickAvailabilityTo = picked;
      }
    });
  }

  List<Map<String, dynamic>> _mergeQuickAvailabilitySlots({
    required List<int> selectedDays,
  }) {
    final updatedByWeekday = <int, Map<String, dynamic>>{};

    for (final slot in _availabilitySlots) {
      final weekday = (slot['weekday'] as num?)?.toInt();
      if (weekday == null) continue;
      updatedByWeekday[weekday] = {
        ...Map<String, dynamic>.from(slot),
        'day': _weekdayLongLabel(weekday),
      };
    }

    for (final day in selectedDays) {
      updatedByWeekday[day] = _buildAvailabilitySlotMapForQuickEditor(day);
    }

    final merged = updatedByWeekday.values.toList()
      ..sort(
        (a, b) => ((a['weekday'] as num?)?.toInt() ?? 0).compareTo(
          (b['weekday'] as num?)?.toInt() ?? 0,
        ),
      );
    return merged;
  }

  Future<void> _saveQuickAvailability() async {
    final selectedDays = _quickAvailabilityDays.toList()..sort();
    if (selectedDays.isEmpty) {
      _showInfo('Choisissez au moins un jour disponible.', isError: true);
      return;
    }
    if (selectedDays.length > 1) {
      _showInfo('Choisissez un seul jour a la fois.', isError: true);
      return;
    }

    final fromMinutes =
        (_quickAvailabilityFrom.hour * 60) + _quickAvailabilityFrom.minute;
    final toMinutes =
        (_quickAvailabilityTo.hour * 60) + _quickAvailabilityTo.minute;

    if (!_quickAvailabilityAllDay && toMinutes <= fromMinutes) {
      _showInfo(
        "L'heure de fin doit etre apres l'heure de debut.",
        isError: true,
      );
      return;
    }

    final updatedSlots = _mergeQuickAvailabilitySlots(
      selectedDays: selectedDays,
    );
    final updatedWeekDays =
        updatedSlots
            .map((slot) => (slot['weekday'] as num?)?.toInt())
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(user.uid)
            .update({
              'availableWeekDays': updatedWeekDays,
              'availabilitySlots': updatedSlots,
            });
      }

      if (!mounted) return;
      setState(() {
        _availableWeekDays = updatedWeekDays;
        _availabilitySlots = updatedSlots;
      });
      _selectQuickAvailabilityDay(selectedDays.first);
      _showInfo('Disponibilite enregistree avec succes.');
    } catch (e) {
      if (mounted) _showInfo('Erreur: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _editPhoneNumber() async {
    final localController = TextEditingController(text: _phone);
    var localDialCode = _phoneDialCode.isNotEmpty
        ? _phoneDialCode
        : inferDialCodeFromPhone(_phone);
    localDialCode = localDialCode.isNotEmpty ? localDialCode : '1';
    var localCountryIso = _resolvedPhoneCountryIso();
    var localComplete = _composePhoneNumber(
      localDialCode,
      localController.text,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 6,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const Text(
                        'Telephone',
                        style: TextStyle(
                          color: kProfileText,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Changez l indicatif pays et le numero dans le meme champ.',
                        style: TextStyle(
                          color: kProfileMuted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      IntlPhoneField(
                        key: ValueKey(localCountryIso),
                        controller: localController,
                        initialCountryCode: localCountryIso,
                        disableLengthCheck: true,
                        style: const TextStyle(color: kProfileText),
                        dropdownTextStyle: const TextStyle(color: kProfileText),
                        dropdownIcon: const Icon(
                          Icons.arrow_drop_down,
                          color: kProfileMuted,
                        ),
                        pickerDialogStyle: PickerDialogStyle(
                          backgroundColor: Colors.white,
                          countryCodeStyle: const TextStyle(
                            color: kProfileText,
                          ),
                          countryNameStyle: const TextStyle(
                            color: kProfileText,
                          ),
                          searchFieldInputDecoration: InputDecoration(
                            hintText: 'Rechercher...',
                            hintStyle: const TextStyle(color: kProfileMuted),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFF),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        decoration: InputDecoration(
                          labelText: 'Numero de telephone',
                          labelStyle: const TextStyle(color: kProfileMuted),
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(color: kProfileBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(color: kProfileBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: kProfileBlue,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (phone) {
                          setModalState(() {
                            localCountryIso = phone.countryISOCode;
                            localDialCode = phone.countryCode.replaceAll(
                              '+',
                              '',
                            );
                            localComplete = phone.completeNumber;
                          });
                        },
                        onCountryChanged: (country) {
                          setModalState(() {
                            localCountryIso = country.code;
                            localDialCode = country.dialCode;
                            localComplete = _composePhoneNumber(
                              localDialCode,
                              localController.text,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final trimmedNumber = localController.text.trim();
                            final completeNumber = localComplete.isNotEmpty
                                ? localComplete
                                : _composePhoneNumber(
                                    localDialCode,
                                    trimmedNumber,
                                  );

                            setState(() => _isLoading = true);
                            try {
                              final user = FirebaseAuth.instance.currentUser;
                              if (user != null) {
                                await FirebaseFirestore.instance
                                    .collection('profiles')
                                    .doc(user.uid)
                                    .update({
                                      'phone': completeNumber,
                                      'phoneNational': trimmedNumber,
                                      'phoneCountryIso': localCountryIso,
                                      'phoneDialCode': localDialCode,
                                    });
                              }

                              if (!mounted || !context.mounted) return;
                              setState(() {
                                _phone = trimmedNumber;
                                _phoneCountryIso = localCountryIso;
                                _phoneDialCode = localDialCode;
                              });
                              Navigator.pop(context);
                            } catch (e) {
                              if (mounted) {
                                _showInfo('Erreur: $e', isError: true);
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _isLoading = false);
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kProfileBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Enregistrer',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitNewRoleRequest(
    String departmentName,
    String roleName,
  ) async {
    if (roleName.trim().isEmpty) return;
    Navigator.pop(context);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance.collection('role_requests').add({
        'userId': user.uid,
        'department': departmentName,
        'requestedRole': roleName.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showInfo("Demande envoyee. L'administration l'examinera bientot.");
      }
    } catch (e) {
      if (mounted) _showInfo('Erreur: $e', isError: true);
    }
  }

  Future<int?> _showExperienceYearsSheet(
    String specialty, {
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
                    _sheetHandle(),
                    const SizedBox(height: 10),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: kProfileLightBlue,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        LucideIcons.badgeCheck,
                        color: kProfileBlue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Annees d experience',
                      style: TextStyle(
                        color: kProfileText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Indiquez votre experience pour $specialty.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: kProfileBody,
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
                        border: Border.all(color: const Color(0xFFDCE8F8)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$selectedYears ${selectedYears > 1 ? 'ans' : 'an'}',
                            style: const TextStyle(
                              color: kProfileBlue,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Slider(
                            value: selectedYears.toDouble(),
                            min: 1,
                            max: 30,
                            divisions: 29,
                            activeColor: kProfileBlue,
                            inactiveColor: const Color(0xFFDCE8F8),
                            label: '$selectedYears',
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
                              foregroundColor: kProfileBlue,
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
                              backgroundColor: kProfileBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              elevation: 0,
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
            );
          },
        );
      },
    );
  }

  Future<void> _showAddDepartmentRoleSheet() async {
    if (_department.trim().isEmpty) return;

    final deptSpecialties = _currentDepartmentSpecialties();
    final color = _departmentColor(_department);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _sheetHandle()),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(LucideIcons.plus, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ajouter un role',
                          style: TextStyle(
                            color: kProfileText,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          _department,
                          style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Choisissez un role a soumettre pour validation.',
                style: TextStyle(
                  color: kProfileMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (deptSpecialties.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Aucun role disponible pour ce departement.',
                    style: TextStyle(color: kProfileMuted, fontSize: 13),
                  ),
                )
              else
                ...deptSpecialties.map((role) {
                  final isPending = _pendingRoles.contains(role);
                  return InkWell(
                    onTap: isPending
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            try {
                              final uid =
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (uid != null) {
                                await FirebaseFirestore.instance
                                    .collection('workers')
                                    .doc(uid)
                                    .set(
                                      {
                                        'pendingRoles':
                                            FieldValue.arrayUnion([role]),
                                      },
                                      SetOptions(merge: true),
                                    );
                                if (mounted) {
                                  setState(() {
                                    if (!_pendingRoles.contains(role)) {
                                      _pendingRoles = [..._pendingRoles, role];
                                    }
                                  });
                                  _showInfo(
                                    'Role ajouté en attente de validation',
                                  );
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                _showInfo('Erreur: $e', isError: true);
                              }
                            }
                          },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isPending
                            ? const Color(0xFFFFF3CD)
                            : const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isPending
                              ? const Color(0xFFF59E0B)
                              : kProfileBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _specialtyIcon(role),
                            size: 16,
                            color: isPending
                                ? const Color(0xFF92400E)
                                : kProfileMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              role,
                              style: TextStyle(
                                color: isPending
                                    ? const Color(0xFF92400E)
                                    : kProfileText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isPending)
                            const Text(
                              'En attente',
                              style: TextStyle(
                                color: Color(0xFF92400E),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddRoleDialog(String departmentName, Color deptColor) {
    final roleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFDCE8F8)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A0F63FF),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: kProfileLightBlue,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    LucideIcons.plusCircle,
                    color: deptColor,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ajouter une specialite',
                  style: TextStyle(
                    color: kProfileText,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: kProfileLightBlue,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    departmentName,
                    style: TextStyle(
                      color: deptColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  "Votre suggestion sera envoyee pour validation dans le departement $departmentName.",
                  style: const TextStyle(
                    color: kProfileBody,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: kProfileBorder),
                  ),
                  child: TextField(
                    controller: roleController,
                    style: const TextStyle(
                      color: kProfileText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ex: Plomberie generale',
                      hintStyle: const TextStyle(
                        color: kProfileMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon: Icon(
                        LucideIcons.sparkles,
                        color: deptColor,
                        size: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: deptColor, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kProfileBlue,
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kProfileBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () => _submitNewRoleRequest(
                          departmentName,
                          roleController.text,
                        ),
                        child: const Text('Soumettre'),
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
  }

  Future<void> _downloadAndOpenCV() async {
    if (_cvBase64 == null || _cvFileName == null) return;

    try {
      final bytes = base64Decode(_cvBase64!);
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$_cvFileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      await OpenFile.open(filePath);
    } catch (e) {
      if (mounted) _showInfo("Erreur lors de l'ouverture: $e", isError: true);
    }
  }

  Widget _sheetHandle() {
    return Container(
      width: 56,
      height: 6,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFD7E4FF),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  void _showEditCvDialog() {
    final nameController = TextEditingController(text: _cvFileName);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _sheetHandle()),
              const Text(
                'Modifier le nom du CV',
                style: TextStyle(
                  color: kProfileText,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Renommez votre document PDF.',
                style: TextStyle(
                  color: kProfileMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Nom du fichier',
                  labelStyle: const TextStyle(color: kProfileMuted),
                  filled: true,
                  fillColor: const Color(0xFFF8FBFF),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: kProfileBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: kProfileBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: kProfileBlue,
                      width: 1.5,
                    ),
                  ),
                ),
                style: const TextStyle(
                  color: kProfileText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kProfileBlue,
                        side: const BorderSide(color: kProfileBorder),
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) return;
                        Navigator.pop(ctx);

                        setState(() => _isLoading = true);
                        try {
                          final user = FirebaseAuth.instance.currentUser!;
                          var newName = nameController.text.trim();
                          if (!newName.toLowerCase().endsWith('.pdf')) {
                            newName += '.pdf';
                          }

                          await FirebaseFirestore.instance
                              .collection('profiles')
                              .doc(user.uid)
                              .update({'cvFileName': newName});

                          if (mounted) {
                            setState(() => _cvFileName = newName);
                            _showInfo('Nom du CV mis a jour.');
                          }
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kProfileText,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
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

  void _showCvOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            _cvOptionItem(LucideIcons.download, 'Voir le CV', () {
              Navigator.pop(ctx);
              _downloadAndOpenCV();
            }),
            _cvOptionItem(LucideIcons.edit3, 'Modifier le nom', () {
              Navigator.pop(ctx);
              _showEditCvDialog();
            }),
            _cvOptionItem(LucideIcons.fileClock, 'Remplacer', () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CvPrivacyScreen(onUploadComplete: _loadData),
                ),
              );
            }),
            _cvOptionItem(LucideIcons.trash2, 'Supprimer', () async {
              Navigator.pop(ctx);
              if (mounted) setState(() => _isLoading = true);
              try {
                final user = FirebaseAuth.instance.currentUser!;
                await FirebaseFirestore.instance
                    .collection('profiles')
                    .doc(user.uid)
                    .update({
                      'cvFileName': FieldValue.delete(),
                      'cvBase64': FieldValue.delete(),
                    });
                if (mounted) {
                  setState(() {
                    _cvFileName = null;
                    _cvBase64 = null;
                  });
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            }, isDestructive: true),
          ],
        ),
      ),
    );
  }

  Widget _cvOptionItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    final foreground = isDestructive ? const Color(0xFFEF4444) : kProfileText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: isDestructive
                ? const Color(0xFFFFF1F2)
                : const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDestructive
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFDCE8FF),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? const Color(0xFFEF4444) : kProfileBlue,
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: isDestructive ? const Color(0xFFF87171) : kProfileMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfo(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0),
          ),
        ),
        content: Row(
          children: [
            Icon(
              isError ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
              color: isError
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF16A34A),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? const Color(0xFF991B1B)
                      : const Color(0xFF166534),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
      (route) => false,
    );
  }

  ImageProvider? _profileImage() {
    if (_photoBase64 == null || _photoBase64!.isEmpty) return null;
    return MemoryImage(base64Decode(_photoBase64!));
  }

  String _displayName() => _username.isEmpty ? 'Utilisateur' : _username;

  String _displayDepartment() =>
      _department.isEmpty ? 'Non defini' : _department;

  String _primarySpecialty() {
    if (_selectedSpecialties.isEmpty) return 'Aucune specialite';
    if (_selectedSpecialties.length == 1) return _selectedSpecialties.first;
    return '${_selectedSpecialties.first} +${_selectedSpecialties.length - 1}';
  }

  IconData _primaryRoleIcon() {
    if (_department.trim().isNotEmpty) {
      return _departmentIcon(_department);
    }
    if (_selectedSpecialties.isNotEmpty) {
      return _specialtyIcon(_selectedSpecialties.first);
    }
    return LucideIcons.sparkles;
  }

  String _cvStatusText() => _cvFileName == null ? 'CV manquant' : 'CV uploade';

  String _memberSinceText() {
    if (_createdAt == null) return 'Non defini';
    const months = [
      'Janvier',
      'Fevrier',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Aout',
      'Septembre',
      'Octobre',
      'Novembre',
      'Decembre',
    ];
    return '${months[_createdAt!.month - 1]} ${_createdAt!.year}';
  }

  String _displayValue(String value) =>
      value.trim().isEmpty ? 'Non defini' : value;

  void _toggleSection(ProfileSection section) {
    if (widget.completionMode && section == ProfileSection.address) {
      if (_hasDepartment() && _hasSpecialties() && _hasDepartmentExperience()) {
        _updateAddressOrDob('Adresse', _address);
      }
      return;
    }
    if (widget.completionMode && section == ProfileSection.birthday) {
      if (_hasDepartment() &&
          _hasSpecialties() &&
          _hasDepartmentExperience() &&
          _hasAddress()) {
        _updateAddressOrDob('Date de naissance', _dob);
      }
      return;
    }
    setState(() {
      _openSection = _openSection == section ? null : section;
    });
  }

  String _availabilitySummary() {
    if (_availabilitySlots.isNotEmpty) {
      return '${_availabilitySlots.length} creneau(x) client';
    }
    if (_availableWeekDays.isNotEmpty) return 'Disponibilite configuree';
    if (_libreDays.isNotEmpty) return 'Disponible ${_libreDays.length} jour(s)';
    return 'Non definie';
  }

  String _availabilityDaysText() {
    if (_availableWeekDays.isNotEmpty) {
      const names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      return _availableWeekDays.map((d) => names[d - 1]).join(' - ');
    }
    if (_libreDays.isEmpty) return 'Non definie';
    const names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final set = <int>{};
    for (final day in _libreDays) {
      set.add(day.weekday);
    }
    final ordered = set.toList()..sort();
    return ordered.map((d) => names[d - 1]).join(' - ');
  }

  String _nextAvailabilityText() {
    if (_availabilitySlots.isEmpty) return 'Non definie';

    const names = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final firstSlot = _availabilitySlots.first;
    final weekday = (firstSlot['weekday'] as num?)?.toInt();
    final label = firstSlot['label'] as String?;
    if (weekday != null && weekday >= 1 && weekday <= 7 && label != null) {
      return '${names[weekday - 1]} - $label';
    }

    final startsAt = firstSlot['startsAt'];
    if (startsAt is Timestamp && label != null) {
      final date = startsAt.toDate();
      return '${names[date.weekday - 1]} ${date.day} - $label';
    }

    return 'Non definie';
  }

  String _sectionSummary(ProfileSection section) {
    switch (section) {
      case ProfileSection.personal:
        return 'Nom, adresse, telephone';
      case ProfileSection.cv:
        return _cvStatusText();
      case ProfileSection.department:
        return _displayDepartment();
      case ProfileSection.specialties:
        return _primarySpecialty();
      case ProfileSection.address:
        return _displayValue(_address);
      case ProfileSection.birthday:
        return _displayValue(_dob);
      case ProfileSection.availability:
        return _availabilitySummary();
    }
  }

  Color _departmentColor(String departmentName) {
    final normalizedDepartment = _normalizeDepartmentName(departmentName);
    final match = _departmentsData.where(
      (dept) => dept['name'] == normalizedDepartment,
    );
    if (match.isEmpty) return kProfileBlue;
    return match.first['color'] as Color;
  }

  List<String> _currentDepartmentSpecialties() {
    final match = _departmentsData.where(
      (dept) => dept['name'] == _normalizeDepartmentName(_department),
    );
    if (match.isEmpty) return [];
    return List<String>.from(match.first['specialties'] as List);
  }

  IconData _departmentIcon(String departmentName) {
    switch (_normalizeDepartmentName(departmentName)) {
      case 'Maintenance generale':
        return LucideIcons.wrench;
      case "Main-d'oeuvre qualifiee":
        return LucideIcons.hammer;
      case 'Prepose aux chambres':
        return LucideIcons.bedSingle;
      case 'Houseman':
        return LucideIcons.briefcase;
      case 'Concierge':
        return LucideIcons.badgeHelp;
      case 'Menage':
        return LucideIcons.sparkles;
      default:
        return LucideIcons.briefcase;
    }
  }

  IconData _specialtyIcon(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('plomberie')) return LucideIcons.waves;
    if (lower.contains('electric')) return LucideIcons.zap;
    if (lower.contains('chauff')) return LucideIcons.sunMedium;
    if (lower.contains('maconnerie')) return LucideIcons.squareStack;
    if (lower.contains('menuiserie')) return LucideIcons.ruler;
    if (lower.contains('peinture')) return LucideIcons.paintbrush2;
    if (lower.contains('transport')) return LucideIcons.briefcase;
    if (lower.contains('couloir')) return LucideIcons.hotel;
    if (lower.contains('housekeeping')) return LucideIcons.home;
    if (lower.contains('linge')) return LucideIcons.shirt;
    if (lower.contains('nettoyage')) return LucideIcons.sparkles;
    return LucideIcons.badgeCheck;
  }

  String _completionStepLabel(ProfileSection section) {
    switch (section) {
      case ProfileSection.department:
        return '1. Departement';
      case ProfileSection.specialties:
        return '2. Specialite';
      case ProfileSection.address:
        return '';
      case ProfileSection.birthday:
        return '';
      case ProfileSection.availability:
        return '3. Disponibilite';
      case ProfileSection.personal:
      case ProfileSection.cv:
        return '';
    }
  }

  Widget _buildHero() {
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('lib/assets/monprofileimghero.png', fit: BoxFit.cover),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _handleBack,
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
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
                    'Mon profil',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Identite, CV et disponibilite',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 14.5,
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

  Widget _buildSummaryCard() {
    final image = _profileImage();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kProfileBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F63FF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0x804BC0FF),
                    width: 2.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: kProfileLightBlue,
                  backgroundImage: image,
                  child: image == null
                      ? const Icon(
                          Icons.engineering_rounded,
                          color: kProfileBlue,
                          size: 32,
                        )
                      : null,
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _uploadPhoto,
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: kProfileBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        LucideIcons.camera,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackStatusCards = constraints.maxWidth < 220;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kProfileText,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _displayDepartment(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kProfileBlue,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _summaryChip(
                          icon: _primaryRoleIcon(),
                          text: _primarySpecialty(),
                          color: kProfileBlue,
                          background: kProfileLightBlue,
                        ),
                        _summaryChip(
                          icon: LucideIcons.fileWarning,
                          text: _cvStatusText(),
                          color: _cvFileName == null
                              ? kProfileWarning
                              : kProfileSuccess,
                          background: _cvFileName == null
                              ? const Color(0xFFFFF4EB)
                              : const Color(0xFFEFFDF5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (stackStatusCards) ...[
                      _statusInfo(
                        icon: LucideIcons.calendarDays,
                        title: 'Membre depuis',
                        value: _memberSinceText(),
                      ),
                      const SizedBox(height: 8),
                      _statusInfo(
                        icon: LucideIcons.badgeCheck,
                        title: 'Statut',
                        value: 'Actif',
                        highlight: true,
                      ),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _statusInfo(
                              icon: LucideIcons.calendarDays,
                              title: 'Membre depuis',
                              value: _memberSinceText(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statusInfo(
                              icon: LucideIcons.badgeCheck,
                              title: 'Statut',
                              value: 'Actif',
                              highlight: true,
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String text,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusInfo({
    required IconData icon,
    required String title,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFEFFDF5) : const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? const Color(0xFFCFF3DD) : kProfileBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: highlight ? kProfileSuccess : kProfileBlue,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  style: const TextStyle(
                    color: kProfileMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kProfileText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required ProfileSection section,
    required IconData icon,
    required String title,
    GlobalKey? cardKey,
  }) {
    final isOpen = _openSection == section;
    const titleColor = Color(0xFF0F172A);
    final summaryColor = isOpen ? kProfileBlue : kProfileMuted;

    return InkWell(
      key: cardKey,
      onTap: () => _toggleSection(section),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOpen ? const Color(0xFFBDD5FF) : kProfileBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: isOpen ? const Color(0x0D0F63FF) : const Color(0x080F172A),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: kProfileLightBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: kProfileBlue, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.completionMode)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _completionStepLabel(section),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: kProfileBlue,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _sectionSummary(section),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: summaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isOpen ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  color: kProfileMuted,
                  size: 18,
                ),
              ],
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: isOpen
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDCE8F8)),
                  ),
                  child: _buildSectionContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContent() {
    if (_openSection == null) {
      return const SizedBox.shrink();
    }

    switch (_openSection) {
      case ProfileSection.personal:
        return _buildPersonalContent();
      case ProfileSection.cv:
        return _buildCvContent();
      case ProfileSection.department:
        return _buildDepartmentContent();
      case ProfileSection.specialties:
        return _buildSpecialtiesContent();
      case ProfileSection.address:
      case ProfileSection.birthday:
        return const SizedBox.shrink();
      case ProfileSection.availability:
        return _buildAvailabilityContent();
      case null:
        return const SizedBox.shrink();
    }
  }

  // ── Poste actuel card + edit modal ────────────────────────────────────────

  String _displayJobValue(String v) =>
      v.trim().isEmpty ? 'Non défini' : v.trim();

  Future<void> _updateCurrentPost() async {
    final locCtrl = TextEditingController(text: _jobLocation);
    final dateCtrl = TextEditingController(text: _jobStartDate);
    var selectedAddress = _jobAddress;
    var selLat = _jobAddressLatitude;
    var selLng = _jobAddressLongitude;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x240F63FF),
                  blurRadius: 28,
                  offset: Offset(0, -10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7E4FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: kProfileLightBlue,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(LucideIcons.briefcase,
                            color: kProfileBlue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Poste de travail',
                              style: TextStyle(
                                color: kProfileText,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Définissez le lieu, l\'adresse et la date de début.',
                              style: TextStyle(
                                color: kProfileMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Lieu de travail
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FBFF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kProfileBorder),
                    ),
                    child: TextField(
                      controller: locCtrl,
                      style: const TextStyle(
                          color: kProfileText,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: 'Lieu de travail',
                        labelStyle:
                            const TextStyle(color: kProfileMuted, fontSize: 14),
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kProfileLightBlue,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(LucideIcons.building,
                              color: kProfileBlue, size: 18),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Adresse picker
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FBFF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kProfileBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: kProfileLightBlue,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(LucideIcons.mapPin,
                              color: kProfileBlue, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Adresse du poste',
                                style: TextStyle(
                                    color: kProfileMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                selectedAddress.isNotEmpty
                                    ? selectedAddress
                                    : 'Non défini',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selectedAddress.isNotEmpty
                                      ? kProfileText
                                      : kProfileMuted,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            final picked = await showAddressPicker(
                              context: ctx,
                              initialAddress: selectedAddress,
                              initialLatitude: selLat,
                              initialLongitude: selLng,
                              presentation:
                                  AddressPickerPresentation.fullscreen,
                              title: 'Adresse du poste',
                            );
                            if (picked != null) {
                              setSheet(() {
                                selectedAddress = picked.address;
                                selLat = picked.latitude;
                                selLng = picked.longitude;
                              });
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kProfileBlue,
                            side: const BorderSide(color: kProfileBorder),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Modifier',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Date de début
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FBFF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kProfileBorder),
                    ),
                    child: TextField(
                      controller: dateCtrl,
                      style: const TextStyle(
                          color: kProfileText,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: 'Date de début',
                        labelStyle:
                            const TextStyle(color: kProfileMuted, fontSize: 14),
                        prefixIcon: Container(
                          margin: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kProfileLightBlue,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(LucideIcons.calendarDays,
                              color: kProfileBlue, size: 18),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, {
                        'jobLocation': locCtrl.text.trim(),
                        'jobAddress': selectedAddress,
                        'jobStartDate': dateCtrl.text.trim(),
                        'jobAddressLatitude': selLat?.toString() ?? '',
                        'jobAddressLongitude': selLng?.toString() ?? '',
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kProfileBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text(
                        'Enregistrer',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      try {
        final updates = <String, dynamic>{
          'jobLocation': result['jobLocation'] ?? '',
          'jobAddress': result['jobAddress'] ?? '',
          'jobStartDate': result['jobStartDate'] ?? '',
        };
        final latStr = result['jobAddressLatitude'];
        final lngStr = result['jobAddressLongitude'];
        if (latStr != null && latStr.isNotEmpty) {
          updates['jobAddressLatitude'] = double.tryParse(latStr);
        }
        if (lngStr != null && lngStr.isNotEmpty) {
          updates['jobAddressLongitude'] = double.tryParse(lngStr);
        }
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .update(updates);
        if (mounted) {
          setState(() {
            _jobLocation = result['jobLocation'] ?? '';
            _jobAddress = result['jobAddress'] ?? '';
            _jobStartDate = result['jobStartDate'] ?? '';
            if (latStr != null && latStr.isNotEmpty) {
              _jobAddressLatitude = double.tryParse(latStr);
            }
            if (lngStr != null && lngStr.isNotEmpty) {
              _jobAddressLongitude = double.tryParse(lngStr);
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')),
          );
        }
      }
    }
  }

  Widget _buildPostActuelCard() {
    return InkWell(
      onTap: _updateCurrentPost,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kProfileBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: kProfileLightBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.briefcase,
                      color: kProfileBlue, size: 16),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Poste actuel',
                    style: TextStyle(
                      color: kProfileMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(LucideIcons.edit3,
                    color: kProfileMuted, size: 14),
              ],
            ),
            const SizedBox(height: 10),
            _profileDetailRow(
                LucideIcons.building, 'Lieu', _displayJobValue(_jobLocation)),
            const SizedBox(height: 6),
            _profileDetailRow(
                LucideIcons.mapPin, 'Adresse', _displayJobValue(_jobAddress)),
            const SizedBox(height: 6),
            _profileDetailRow(LucideIcons.calendarDays, 'Depuis le',
                _displayJobValue(_jobStartDate)),
          ],
        ),
      ),
    );
  }

  Widget _profileDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 13, color: kProfileMuted),
        const SizedBox(width: 6),
        Text(
          '$label : ',
          style: const TextStyle(
            color: kProfileMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: kProfileText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalContent() {
    final items = [
      _InfoMatrixData(
        icon: LucideIcons.user,
        label: 'Nom complet',
        value: _displayValue(_username),
      ),
      _InfoMatrixData(
        icon: LucideIcons.mapPin,
        label: 'Adresse',
        value: _displayValue(_address),
        onTap: () => _updateAddressOrDob('Adresse', _address),
      ),
      _InfoMatrixData(
        icon: LucideIcons.calendarDays,
        label: 'Date de naissance',
        value: _displayValue(_dob),
        onTap: () => _updateAddressOrDob('Date de naissance', _dob),
      ),
      _InfoMatrixData(
        icon: LucideIcons.phone,
        label: 'Telephone',
        value: _displayValue(_phone),
        onTap: _editPhoneNumber,
      ),
      _InfoMatrixData(
        icon: LucideIcons.mail,
        label: 'Email',
        value: _displayValue(_email),
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _buildMatrixField(items[i], fullWidth: true),
          if (i != items.length - 1) const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        _buildPostActuelCard(),
      ],
    );
  }

  Widget _buildMatrixField(_InfoMatrixData item, {bool fullWidth = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = MediaQuery.of(context).size.width;
        final twoColumns = !fullWidth && width > 380;
        final cardWidth = twoColumns ? (width - 72) / 2 : double.infinity;

        return SizedBox(
          width: cardWidth,
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kProfileBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: kProfileLightBlue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item.icon, color: kProfileBlue, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: kProfileMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kProfileText,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.onTap != null)
                    const Icon(
                      LucideIcons.edit3,
                      color: kProfileMuted,
                      size: 14,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCvContent() {
    if (_cvFileName != null && _cvBase64 != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lightBanner(
            icon: LucideIcons.fileCheck2,
            title: 'CV uploade',
            subtitle: _cvFileName ?? 'Document disponible',
            accent: kProfileSuccess,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _actionPill(
                label: 'Voir le CV',
                icon: LucideIcons.eye,
                onTap: _downloadAndOpenCV,
              ),
              _actionPill(
                label: 'Options',
                icon: LucideIcons.settings2,
                onTap: _showCvOptions,
              ),
            ],
          ),
          const SizedBox(height: 14),
          CvPreviewCarousel(cvBase64: _cvBase64!, cvFileName: _cvFileName!),
        ],
      );
    }

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CvPrivacyScreen(onUploadComplete: _loadData),
        ),
      ),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD5E4FF)),
        ),
        child: Column(
          children: const [
            Icon(LucideIcons.uploadCloud, color: kProfileBlue, size: 28),
            SizedBox(height: 10),
            Text(
              'Uploader votre CV',
              style: TextStyle(
                color: kProfileText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'PDF uniquement, max 5 Mo',
              style: TextStyle(
                color: kProfileMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentContent() {
    final color = _departmentColor(_department);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Touchez un departement pour le changer a tout moment.',
          style: TextStyle(
            color: kProfileMuted,
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _departmentsData.map((dept) {
            final name = dept['name'] as String;
            final isSelected = _department == name;
            final color = dept['color'] as Color;

            return InkWell(
              onTap: () => _changeDepartment(name),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.14)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? color : kProfileBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _departmentIcon(name),
                      color: isSelected ? color : kProfileMuted,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: TextStyle(
                        color: isSelected ? color : kProfileText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_department.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: _editDepartmentExperienceYears,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDCE8F8)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(LucideIcons.badgeCheck, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Experience du departement",
                          style: TextStyle(
                            color: kProfileMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _hasDepartmentExperience()
                              ? '$_departmentExperienceYears ${_departmentExperienceYears! > 1 ? 'ans' : 'an'} dans $_department'
                              : "Annees d'experience non renseignees",
                          style: const TextStyle(
                            color: kProfileText,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.pencil,
                    color: kProfileMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_pendingRoles.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Roles en attente de validation',
            style: TextStyle(
              color: kProfileMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _pendingRoles.map((role) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Text(
                  '$role · En attente',
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 10),
        InkWell(
          onTap: () => _showAddDepartmentRoleSheet(),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kProfileBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.plus, size: 15, color: kProfileMuted),
                const SizedBox(width: 8),
                Text(
                  'Ajouter',
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialtiesContent() {
    final specialties = _currentDepartmentSpecialties();
    if (specialties.isEmpty) {
      return const Text(
        'Selectionnez d abord un departement.',
        style: TextStyle(color: kProfileMuted, fontWeight: FontWeight.w600),
      );
    }

    final color = _departmentColor(_department);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choisissez votre ou vos roles dans ce departement.',
          style: TextStyle(
            color: kProfileMuted,
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ...specialties.map((spec) {
              final isSelected = _selectedSpecialties.contains(spec);
              return InkWell(
                onTap: () => _toggleSpecialty(spec),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.14)
                        : const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected ? color : kProfileBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _specialtyIcon(spec),
                        size: 15,
                        color: isSelected ? color : kProfileMuted,
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          spec,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? color : kProfileText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Icon(LucideIcons.checkCircle2, size: 15, color: color),
                      ],
                    ],
                  ),
                ),
              );
            }),
            InkWell(
              onTap: () => _showAddRoleDialog(_department, color),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kProfileBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.plus,
                      size: 15,
                      color: kProfileMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ajouter',
                      style: TextStyle(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvailabilityContent() {
    if (widget.completionMode) {
      final selectedDay = _selectedQuickAvailabilityDay();
      final hasSavedSelection = _selectedQuickAvailabilityDayHasSavedSlot();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _weekdaysForQuickEditor().map((day) {
              final isSelected = _quickAvailabilityDays.contains(day);
              final isStored = _quickAvailabilitySlotForWeekday(day) != null;
              return InkWell(
                onTap: () => _selectQuickAvailabilityDay(day),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: (isSelected || isStored)
                        ? kProfileBlue.withValues(
                            alpha: isSelected ? 0.18 : 0.12,
                          )
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (isSelected || isStored)
                          ? kProfileBlue
                          : kProfileBorder,
                    ),
                  ),
                  child: Text(
                    _weekdayShortLabel(day),
                    style: TextStyle(
                      color: (isSelected || isStored)
                          ? kProfileBlue
                          : kProfileText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (selectedDay != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCE8F8)),
              ),
              child: Text(
                hasSavedSelection
                    ? '${_weekdayShortLabel(selectedDay)} - ${_quickAvailabilityAllDay ? 'Toujours disponible' : '${_formatTimeOfDay(_quickAvailabilityFrom)} - ${_formatTimeOfDay(_quickAvailabilityTo)}'}'
                    : '${_weekdayShortLabel(selectedDay)} - Nouvelle disponibilite',
                style: const TextStyle(
                  color: kProfileText,
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _compactModePill(
                  label: 'Toujours',
                  selected: _quickAvailabilityAllDay,
                  onTap: () {
                    setState(() => _quickAvailabilityAllDay = true);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _compactModePill(
                  label: 'Horaire',
                  selected: !_quickAvailabilityAllDay,
                  onTap: () {
                    setState(() => _quickAvailabilityAllDay = false);
                  },
                ),
              ),
            ],
          ),
          if (!_quickAvailabilityAllDay) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _compactTimeButton(
                    label: 'Debut',
                    value: _formatTimeOfDay(_quickAvailabilityFrom),
                    onTap: () => _pickQuickAvailabilityTime(isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _compactTimeButton(
                    label: 'Fin',
                    value: _formatTimeOfDay(_quickAvailabilityTo),
                    onTap: () => _pickQuickAvailabilityTime(isStart: false),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveQuickAvailability,
              style: ElevatedButton.styleFrom(
                backgroundColor: kProfileBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                hasSavedSelection
                    ? 'Modifier la disponibilite'
                    : 'Confirmer la disponibilite',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _availabilityChip(
              icon: LucideIcons.badgeCheck,
              text: _availabilitySlots.isEmpty
                  ? 'Non definie'
                  : '${_availabilitySlots.length} creneau(x)',
              success: _availabilitySlots.isNotEmpty,
            ),
            _availabilityChip(
              icon: LucideIcons.calendarDays,
              text: _availabilityDaysText(),
            ),
            _availabilityChip(
              icon: LucideIcons.clock3,
              text: _nextAvailabilityText(),
            ),
            _availabilityChip(
              icon: LucideIcons.calendarCheck2,
              text: _availableWeekDays.isEmpty
                  ? 'Aucun jour disponible'
                  : '${_availableWeekDays.length} jour(s) disponible(s)',
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AvailabilityScreen()),
            ).then((_) => _loadData()),
            icon: const Icon(LucideIcons.calendarRange, size: 18),
            label: const Text('Gerer la disponibilite'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kProfileBlue,
              side: const BorderSide(color: Color(0xFFBDD5FF)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _availabilityChip({
    required IconData icon,
    required String text,
    bool success = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFEFFDF5) : const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: success ? const Color(0xFFCFF3DD) : kProfileBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: success ? kProfileSuccess : kProfileBlue),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: success ? const Color(0xFF15803D) : kProfileText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactModePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? kProfileBlue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? kProfileBlue : kProfileBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : kProfileText,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _compactTimeButton({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kProfileBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: kProfileMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: kProfileText,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionPill({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kProfileLightBlue,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBDD5FF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: kProfileBlue),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: kProfileBlue,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lightBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent == kProfileSuccess
            ? const Color(0xFFEFFDF5)
            : const Color(0xFFFFF4EB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kProfileBody,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApercuButton() {
    return GestureDetector(
      onTap: null, // routing will be added later
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F63FF), Color(0xFF1C4FCE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x280F63FF),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(LucideIcons.eye, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aperçu de mon profil',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Voyez comment votre profil apparaît aux entreprises et employeurs',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(LucideIcons.chevronRight, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kProfilePageBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kProfileBlue))
          : Stack(
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      _buildHero(),
                      Transform.translate(
                        offset: const Offset(0, -10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                          child: Column(
                            children: [
                              if (!widget.completionMode) _buildSummaryCard(),
                              if (!widget.completionMode)
                                const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  12,
                                  12,
                                  12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDFEFF),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: const Color(0xFFE7EEF8),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    if (!widget.completionMode) ...[
                                      _buildSectionCard(
                                        section: ProfileSection.personal,
                                        icon: LucideIcons.user,
                                        title: 'Informations personnelles',
                                      ),
                                      const SizedBox(height: 8),
                                      _buildSectionCard(
                                        section: ProfileSection.cv,
                                        icon: LucideIcons.fileText,
                                        title: 'CV et documents',
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    _buildSectionCard(
                                      cardKey: _departmentSectionKey,
                                      section: ProfileSection.department,
                                      icon: LucideIcons.briefcase,
                                      title: 'Departement et roles',
                                    ),
                                    const SizedBox(height: 8),
                                    _buildSectionCard(
                                      cardKey: _specialtiesSectionKey,
                                      section: ProfileSection.specialties,
                                      icon: LucideIcons.star,
                                      title: 'Specialites',
                                    ),
                                    const SizedBox(height: 8),
                                    _buildSectionCard(
                                      cardKey: _availabilitySectionKey,
                                      section: ProfileSection.availability,
                                      icon: LucideIcons.clock3,
                                      title: 'Disponibilite',
                                    ),
                                    if (widget.completionMode) ...[
                                      const SizedBox(height: 16),
                                      _buildApercuButton(),
                                    ],
                                  ],
                                ),
                              ),
                            ],
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
}

class _InfoMatrixData {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoMatrixData({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });
}
