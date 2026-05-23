import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../utils/profile_formatters.dart';
import '../widgets/address_picker.dart';
import '../widgets/premium_bottom_sheets.dart';

const kSettingsBlue = Color(0xFF0F63FF);
const kSettingsDeepBlue = Color(0xFF2563EB);
const kSettingsDarkBlue = Color(0xFF0047D8);
const kSettingsPageBg = Color(0xFFF7FAFF);
const kSettingsText = Color(0xFF0F172A);
const kSettingsBody = Color(0xFF475569);
const kSettingsMuted = Color(0xFF64748B);
const kSettingsBorder = Color(0xFFE2E8F0);
const kSettingsLightBlue = Color(0xFFEFF6FF);
const kSettingsRed = Color(0xFFFF4D4F);

class SettingsScreen extends StatefulWidget {
  final bool openAddressPickerOnStart;

  const SettingsScreen({super.key, this.openAddressPickerOnStart = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _referralEmployeeIdCtrl = TextEditingController();

  bool _isLoading = true;
  bool _accountDirty = false;
  bool _coordonneesDirty = false;
  bool _privacyDirty = false;
  bool _eligibilityDirty = false;
  bool? _privacyAccepted;
  bool? _referredByEmployee;
  bool? _authorizedToWorkCanada;
  bool? _isAdult;
  bool? _noCriminalRecord;

  String _phoneComplete = '';
  String _phoneCountryIso = 'CA';
  String _phoneDialCode = '1';
  String _expandedSection = '';
  bool _didTriggerInitialAddressPicker = false;
  Map<String, dynamic> _existingCvQuestionnaire = {};
  double? _addressLatitude;
  double? _addressLongitude;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final rawPhone = data['phone'] ?? '';
        final rawDialCode = data['phoneDialCode'] ?? '';
        final phoneDisplay = buildPhoneDisplay(
          phone: rawPhone,
          countryIso: data['phoneCountryIso'] ?? '',
          dialCode: rawDialCode,
        );
        final inferredCountry = inferCountryIsoFromDialCode(
          phoneDisplay.dialCode,
        );
        final questionnaire =
            (data['cvQuestionnaire'] as Map<String, dynamic>?) ?? {};

        setState(() {
          _existingCvQuestionnaire = questionnaire;
          _nameCtrl.text = data['username'] ?? '';
          _addressCtrl.text = data['address'] ?? '';
          _addressLatitude = (data['addressLatitude'] as num?)?.toDouble();
          _addressLongitude = (data['addressLongitude'] as num?)?.toDouble();
          _phoneCtrl.text = data['phoneNational'] ?? phoneDisplay.number;
          _dobCtrl.text = data['dob'] ?? '';
          _phoneDialCode = phoneDisplay.dialCode.isNotEmpty
              ? phoneDisplay.dialCode
              : '1';
          _phoneCountryIso = inferredCountry ?? data['phoneCountryIso'] ?? 'CA';
          _phoneComplete = _phoneDialCode.isEmpty
              ? _phoneCtrl.text.trim()
              : '+$_phoneDialCode${_phoneCtrl.text.trim()}';
          _privacyAccepted =
              data['cvReviewAuthorization'] as bool? ??
              questionnaire['privacyAccepted'] as bool?;
          _referredByEmployee = questionnaire['referredByEmployee'] as bool?;
          _authorizedToWorkCanada =
              questionnaire['authorizedToWorkCanada'] as bool?;
          _isAdult = questionnaire['isAdult'] as bool?;
          _noCriminalRecord = questionnaire['noCriminalRecord'] as bool?;
          _referralEmployeeIdCtrl.text =
              questionnaire['referralEmployeeId'] ?? '';
        });
      }
      if (mounted) {
        setState(() {
          _emailCtrl.text = user.email ?? '';
          _isLoading = false;
        });
        _maybeOpenInitialAddressPicker();
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        _maybeOpenInitialAddressPicker();
      }
    }
  }

  void _maybeOpenInitialAddressPicker() {
    if (!widget.openAddressPickerOnStart || _didTriggerInitialAddressPicker) {
      return;
    }
    _didTriggerInitialAddressPicker = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _pickAddress(saveAfterPick: true);
    });
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

  Widget _buildSectionSaveButton(VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isLoading ? null : onPressed,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Enregistrer'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  Future<void> _saveAccount() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({
        'username': _nameCtrl.text.trim(),
        'dob': _dobCtrl.text.trim(),
      });
      if (_emailCtrl.text.trim() != user.email) {
        await user.verifyBeforeUpdateEmail(_emailCtrl.text.trim());
      }
      if (_passCtrl.text.trim().isNotEmpty) {
        await user.updatePassword(_passCtrl.text.trim());
      }
      if (!mounted) return;
      setState(() => _accountDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compte sauvegarde avec succes !'),
          backgroundColor: Colors.green,
        ),
      );
      _passCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCoordonnees() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({
        'phone': _phoneComplete.isNotEmpty
            ? _phoneComplete
            : _phoneCtrl.text.trim(),
        'phoneNational': _phoneCtrl.text.trim(),
        'phoneCountryIso': _phoneCountryIso,
        'phoneDialCode': _phoneDialCode,
        'address': _addressCtrl.text.trim(),
        'addressLatitude': _addressLatitude,
        'addressLongitude': _addressLongitude,
      });
      if (!mounted) return;
      setState(() => _coordonneesDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coordonnees sauvegardees avec succes !'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePrivacy() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final updatedQuestionnaire = <String, dynamic>{
        ..._existingCvQuestionnaire,
      };
      if (_privacyAccepted != null) {
        updatedQuestionnaire['privacyAccepted'] = _privacyAccepted;
      }
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({
        'cvQuestionnaire': updatedQuestionnaire,
        if (_privacyAccepted != null)
          'cvReviewAuthorization': _privacyAccepted,
      });
      if (!mounted) return;
      setState(() {
        _existingCvQuestionnaire = updatedQuestionnaire;
        _privacyDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confidentialite sauvegardee avec succes !'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveEligibility() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final updatedQuestionnaire = <String, dynamic>{
        ..._existingCvQuestionnaire,
      };
      if (_referredByEmployee != null) {
        updatedQuestionnaire['referredByEmployee'] = _referredByEmployee;
        updatedQuestionnaire['referralEmployeeId'] =
            _referredByEmployee == true
                ? _referralEmployeeIdCtrl.text.trim()
                : '';
      }
      if (_authorizedToWorkCanada != null) {
        updatedQuestionnaire['authorizedToWorkCanada'] =
            _authorizedToWorkCanada;
      }
      if (_isAdult != null) {
        updatedQuestionnaire['isAdult'] = _isAdult;
      }
      if (_noCriminalRecord != null) {
        updatedQuestionnaire['noCriminalRecord'] = _noCriminalRecord;
      }
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({'cvQuestionnaire': updatedQuestionnaire});
      if (!mounted) return;
      setState(() {
        _existingCvQuestionnaire = updatedQuestionnaire;
        _eligibilityDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admissibilite sauvegardee avec succes !'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final parsed = _dobCtrl.text.isNotEmpty
        ? parseProfileDate(_dobCtrl.text)
        : null;
    final picked = await showPremiumDatePickerSheet(
      context: context,
      initialDate: parsed ?? DateTime(now.year - 25, now.month, now.day),
      minimumDate: DateTime(1940),
      maximumDate: DateTime(now.year - 18, now.month, now.day),
    );

    if (picked != null && mounted) {
      setState(() {
        _dobCtrl.text = formatProfileDate(picked);
      });
    }
  }

  Future<void> _saveAddressOnly() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid)
        .update({
          'address': _addressCtrl.text.trim(),
          'addressLatitude': _addressLatitude,
          'addressLongitude': _addressLongitude,
        });
  }

  Future<void> _pickAddress({bool saveAfterPick = false}) async {
    final picked = await showAddressPicker(
      context: context,
      initialAddress: _addressCtrl.text,
      initialLatitude: _addressLatitude,
      initialLongitude: _addressLongitude,
      presentation: AddressPickerPresentation.fullscreen,
    );
    if (picked != null && picked.address.trim().isNotEmpty && mounted) {
      setState(() {
        _addressCtrl.text = picked.address.trim();
        _addressLatitude = picked.latitude;
        _addressLongitude = picked.longitude;
      });
      if (saveAfterPick) {
        try {
          await _saveAddressOnly();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Adresse mise a jour avec succes.'),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Erreur lors de l'enregistrement: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editTextField({
    required String title,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? hintText,
  }) async {
    final localController = TextEditingController(text: controller.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
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
                  Text(
                    title,
                    style: const TextStyle(
                      color: kSettingsText,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: localController,
                    keyboardType: keyboardType,
                    obscureText: obscureText,
                    style: const TextStyle(color: kSettingsText),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: const TextStyle(color: kSettingsMuted),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFF),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: kSettingsBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: kSettingsBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: kSettingsBlue,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          controller.text = localController.text.trim();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kSettingsBlue,
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
    localController.dispose();
  }

  void _toggleSection(String section) {
    setState(() {
      _expandedSection = _expandedSection == section ? '' : section;
    });
  }

  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
    }
  }

  String _displayValue(String value, {String fallback = 'Non renseignee'}) {
    return value.trim().isEmpty ? fallback : value.trim();
  }

  String _phoneSummary() {
    final display = buildPhoneDisplay(
      phone: _phoneComplete.isNotEmpty
          ? _phoneComplete
          : _phoneCtrl.text.trim(),
      countryIso: _phoneCountryIso,
      dialCode: _phoneDialCode,
    );
    final label = display.formatted.isNotEmpty
        ? display.formatted
        : _phoneCtrl.text.trim();
    return label.isEmpty ? 'Non renseigne' : label;
  }

  String _maskedPassword() {
    if (_passCtrl.text.trim().isEmpty) return '••••••••••';
    return '••••••••••';
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

  Future<void> _showPhoneEditorSheet() async {
    final localController = TextEditingController(text: _phoneCtrl.text);
    var localDialCode = _phoneDialCode.isNotEmpty ? _phoneDialCode : '1';
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
                          color: kSettingsText,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choisissez le code regional puis modifiez le numero.',
                        style: TextStyle(
                          color: kSettingsMuted,
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
                        style: const TextStyle(color: kSettingsText),
                        dropdownTextStyle: const TextStyle(
                          color: kSettingsText,
                        ),
                        dropdownIcon: const Icon(
                          Icons.arrow_drop_down,
                          color: kSettingsMuted,
                        ),
                        pickerDialogStyle: PickerDialogStyle(
                          backgroundColor: Colors.white,
                          countryCodeStyle: const TextStyle(
                            color: kSettingsText,
                          ),
                          countryNameStyle: const TextStyle(
                            color: kSettingsText,
                          ),
                          searchFieldCursorColor: kSettingsBlue,
                          searchFieldInputDecoration: InputDecoration(
                            hintText: 'Rechercher...',
                            hintStyle: const TextStyle(color: kSettingsMuted),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFF),
                            prefixIcon: const Icon(
                              CupertinoIcons.search,
                              color: kSettingsMuted,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        decoration: InputDecoration(
                          labelText: 'Numero de telephone',
                          labelStyle: const TextStyle(color: kSettingsMuted),
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: kSettingsBorder,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: kSettingsBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: kSettingsBlue,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (phone) {
                          setModalState(() {
                            localComplete = phone.completeNumber;
                            localCountryIso = phone.countryISOCode;
                            localDialCode = phone.countryCode.replaceAll(
                              '+',
                              '',
                            );
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
                          onPressed: () {
                            setState(() {
                              _phoneCtrl.text = localController.text.trim();
                              _phoneCountryIso = localCountryIso;
                              _phoneDialCode = localDialCode;
                              _phoneComplete = localComplete.isNotEmpty
                                  ? localComplete
                                  : _composePhoneNumber(
                                      localDialCode,
                                      _phoneCtrl.text,
                                    );
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kSettingsBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Utiliser ce numero',
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

  BoxDecoration _whiteCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: kSettingsBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120F63FF),
          blurRadius: 22,
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
          Image.asset('lib/assets/settingsheroimg.png', fit: BoxFit.cover),
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
                    'Parametres',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Compte et preferences',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
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

  Widget _sectionShell({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final expanded = _expandedSection == id;

    return Container(
      decoration: _whiteCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleSection(id),
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: kSettingsLightBlue,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: kSettingsBlue, size: 25),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: kSettingsText,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: kSettingsMuted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  color: kSettingsMuted,
                  size: 20,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _matrixInfoTile({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final tile = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kSettingsBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kSettingsLightBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: kSettingsBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: kSettingsMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kSettingsText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              LucideIcons.chevronRight,
              color: kSettingsMuted,
              size: 18,
            ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: tile,
    );
  }

  Widget _buildAccountSection() {
    final items = [
      _matrixInfoTile(
        icon: LucideIcons.user,
        label: "Nom d'utilisateur",
        value: _displayValue(_nameCtrl.text),
        onTap: () async {
          await _editTextField(
              title: "Nom d'utilisateur", controller: _nameCtrl);
          setState(() => _accountDirty = true);
        },
      ),
      _matrixInfoTile(
        icon: LucideIcons.mail,
        label: 'Email',
        value: _displayValue(_emailCtrl.text),
        onTap: () async {
          await _editTextField(
            title: 'Email',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
          );
          setState(() => _accountDirty = true);
        },
      ),
      _matrixInfoTile(
        icon: LucideIcons.lock,
        label: 'Nouveau mot de passe',
        value: _maskedPassword(),
        onTap: () async {
          await _editTextField(
            title: 'Nouveau mot de passe',
            controller: _passCtrl,
            obscureText: true,
            hintText: 'Laisser vide pour ne pas changer',
          );
          setState(() => _accountDirty = true);
        },
      ),
      _matrixInfoTile(
        icon: LucideIcons.calendar,
        label: 'Date de naissance',
        value: _displayValue(_dobCtrl.text),
        onTap: () async {
          await _pickDob();
          setState(() => _accountDirty = true);
        },
      ),
      _matrixInfoTile(
        icon: LucideIcons.phone,
        label: 'Telephone',
        value: _phoneSummary(),
        onTap: () async {
          await _showPhoneEditorSheet();
          setState(() => _accountDirty = true);
        },
      ),
      _matrixInfoTile(
        icon: LucideIcons.mapPin,
        label: 'Adresse',
        value: _displayValue(_addressCtrl.text),
        onTap: () async {
          await _pickAddress();
          setState(() => _accountDirty = true);
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 560;

        if (!useTwoColumns) {
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                items[i],
                if (i != items.length - 1) const SizedBox(height: 12),
              ],
              if (_accountDirty) _buildSectionSaveButton(_saveAccount),
            ],
          );
        }

        return Column(
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.7,
              children: items,
            ),
            if (_accountDirty) _buildSectionSaveButton(_saveAccount),
          ],
        );
      },
    );
  }

  Widget _buildCoordonneesSection() {
    return Column(
      children: [
        _matrixInfoTile(
          icon: LucideIcons.phone,
          label: 'Numéro de téléphone',
          value: _phoneSummary(),
          onTap: () async {
            await _showPhoneEditorSheet();
            setState(() => _coordonneesDirty = true);
          },
        ),
        const SizedBox(height: 12),
        _matrixInfoTile(
          icon: LucideIcons.mapPin,
          label: 'Adresse',
          value: _displayValue(_addressCtrl.text),
          onTap: () async {
            await _pickAddress();
            setState(() => _coordonneesDirty = true);
          },
        ),
        if (_coordonneesDirty) _buildSectionSaveButton(_saveCoordonnees),
      ],
    );
  }

  Widget _binaryOption({
    required String label,
    required bool selected,
    required bool yesStyle,
    required VoidCallback onTap,
  }) {
    final activeColor = yesStyle ? kSettingsBlue : kSettingsRed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? activeColor : kSettingsBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              Icon(
                yesStyle ? LucideIcons.checkCircle2 : LucideIcons.xCircle,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : kSettingsText,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySection() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kSettingsBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 92,
                height: 116,
                decoration: const BoxDecoration(
                  color: kSettingsLightBlue,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(22),
                  ),
                ),
                child: const Center(
                  child: Icon(
                    LucideIcons.shieldCheck,
                    color: kSettingsBlue,
                    size: 36,
                  ),
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Declaration de confidentialite',
                        style: TextStyle(
                          color: kSettingsText,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Vos informations et votre CV sont traites de maniere securisee et confidentielle conformement au RGPD. StayFix Job ne partage jamais vos donnees sans votre consentement.',
                        style: TextStyle(
                          color: kSettingsBody,
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "J'accepte les conditions",
            style: TextStyle(
              color: kSettingsText,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _binaryOption(
                label: 'Accepter',
                selected: _privacyAccepted == true,
                yesStyle: true,
                onTap: () =>
                    setState(() {
                      _privacyAccepted = true;
                      _privacyDirty = true;
                    }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _binaryOption(
                label: 'Refuser',
                selected: _privacyAccepted == false,
                yesStyle: false,
                onTap: () =>
                    setState(() {
                      _privacyAccepted = false;
                      _privacyDirty = true;
                    }),
              ),
            ),
          ],
        ),
        if (_privacyDirty) _buildSectionSaveButton(_savePrivacy),
      ],
    );
  }

  Widget _questionRow({
    required String question,
    required bool? value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              color: kSettingsText,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _binaryOption(
                  label: 'Oui',
                  selected: value == true,
                  yesStyle: true,
                  onTap: () => onChanged(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _binaryOption(
                  label: 'Non',
                  selected: value == false,
                  yesStyle: false,
                  onTap: () => onChanged(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEligibilitySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kSettingsBorder),
      ),
      child: Column(
        children: [
          _questionRow(
            question: 'Avez-vous ete refere par un employe existant ?',
            value: _referredByEmployee,
            onChanged: (value) => setState(() {
              _referredByEmployee = value;
              _eligibilityDirty = true;
            }),
          ),
          if (_referredByEmployee == true) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _referralEmployeeIdCtrl,
              style: const TextStyle(color: kSettingsText),
              onChanged: (_) => setState(() => _eligibilityDirty = true),
              decoration: InputDecoration(
                hintText: "Numero d'employe du referent",
                hintStyle: const TextStyle(color: kSettingsMuted),
                filled: true,
                fillColor: const Color(0xFFF8FAFF),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: kSettingsBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: kSettingsBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: kSettingsBlue,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ],
          const Divider(color: kSettingsBorder, height: 22),
          _questionRow(
            question: 'Etes-vous legalement autorise a travailler au Canada ?',
            value: _authorizedToWorkCanada,
            onChanged: (value) => setState(() {
              _authorizedToWorkCanada = value;
              _eligibilityDirty = true;
            }),
          ),
          const Divider(color: kSettingsBorder, height: 22),
          _questionRow(
            question: "Ce poste exige l'age legal (18 ans ou plus) ?",
            value: _isAdult,
            onChanged: (value) => setState(() {
              _isAdult = value;
              _eligibilityDirty = true;
            }),
          ),
          const Divider(color: kSettingsBorder, height: 22),
          _questionRow(
            question: "Ce poste exige l'absence d'antecedents criminels ?",
            value: _noCriminalRecord,
            onChanged: (value) => setState(() {
              _noCriminalRecord = value;
              _eligibilityDirty = true;
            }),
          ),
          if (_eligibilityDirty) _buildSectionSaveButton(_saveEligibility),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      decoration: const BoxDecoration(
        color: kSettingsPageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          children: [
            _sectionShell(
              id: 'account',
              icon: LucideIcons.user,
              title: 'Compte',
              subtitle: 'Gerez vos informations de compte',
              child: _buildAccountSection(),
            ),
            const SizedBox(height: 14),
            _sectionShell(
              id: 'contact',
              icon: LucideIcons.phone,
              title: 'Coordonnees',
              subtitle: 'Telephone et informations personnelles',
              child: _buildCoordonneesSection(),
            ),
            const SizedBox(height: 14),
            _sectionShell(
              id: 'privacy',
              icon: LucideIcons.shieldCheck,
              title: 'Confidentialite',
              subtitle: 'Vos donnees sont protegees',
              child: _buildPrivacySection(),
            ),
            const SizedBox(height: 14),
            _sectionShell(
              id: 'eligibility',
              icon: LucideIcons.clipboardCheck,
              title: 'Admissibilite',
              subtitle: "Repondez aux questions d'admissibilite",
              child: _buildEligibilitySection(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSettingsPageBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kSettingsBlue))
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildHero(),
                  Transform.translate(
                    offset: const Offset(0, -10),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _buildContent(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    _addressCtrl.dispose();
    _referralEmployeeIdCtrl.dispose();
    super.dispose();
  }
}
