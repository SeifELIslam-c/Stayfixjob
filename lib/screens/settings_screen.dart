import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_screen.dart';
import 'privacy_policy_screen.dart';
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
  static const List<String> _deleteReasons = <String>[
    'J ai trouve un emploi',
    'Je n utilise plus l application',
    'Je cree un nouveau compte',
    'Je souhaite proteger mes donnees',
    'Autre raison',
  ];

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _referralEmployeeIdCtrl = TextEditingController();

  bool _isLoading = true;
  bool _accountDirty = false;
  bool _languagesDirty = false;
  bool _coordonneesDirty = false;
  bool _privacyDirty = false;
  bool _eligibilityDirty = false;
  bool _speaksFrench = false;
  bool _speaksEnglish = false;
  bool _speaksArabic = false;
  bool _speaksSpanish = false;
  bool? _privacyAccepted;
  bool? _referredByEmployee;
  bool? _authorizedToWorkCanada;
  bool? _isAdult;
  bool? _noCriminalRecord;

  String _phoneComplete = '';
  String _phoneCountryIso = 'CA';
  String _phoneDialCode = '1';
  String _expandedSection = 'danger';
  bool _didTriggerInitialAddressPicker = false;
  Map<String, dynamic> _existingCvQuestionnaire = {};
  double? _addressLatitude;
  double? _addressLongitude;
  bool _isDeletingAccount = false;

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
        final storedLanguages = ((data['languages'] as List?) ?? const <dynamic>[])
            .map((item) => item.toString().trim().toLowerCase())
            .toSet();

        setState(() {
          _existingCvQuestionnaire = questionnaire;
          _nameCtrl.text = ((data['username'] as String?)?.trim().isNotEmpty ==
                      true
                  ? data['username']
                  : user.displayName) ??
              '';
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
          _speaksFrench = data['speaksFrench'] as bool? ?? false;
          _speaksEnglish = data['speaksEnglish'] as bool? ?? false;
          _speaksArabic =
              data['speaksArabic'] as bool? ?? storedLanguages.contains('arabic');
          _speaksSpanish =
              data['speaksSpanish'] as bool? ?? storedLanguages.contains('spanish');
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
      final trimmedName = _nameCtrl.text.trim();
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({
        'username': trimmedName,
        'name': trimmedName,
        'workerName': trimmedName,
        'dob': _dobCtrl.text.trim(),
      });
      if (trimmedName.isNotEmpty && trimmedName != (user.displayName ?? '')) {
        await user.updateDisplayName(trimmedName);
      }
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

  Future<void> _saveLanguages() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final languages = <String>[
        if (_speaksFrench) 'french',
        if (_speaksEnglish) 'english',
        if (_speaksArabic) 'arabic',
        if (_speaksSpanish) 'spanish',
      ];
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({
        'speaksFrench': _speaksFrench,
        'speaksEnglish': _speaksEnglish,
        'speaksArabic': _speaksArabic,
        'speaksSpanish': _speaksSpanish,
        'languages': languages,
      });
      if (!mounted) return;
      setState(() => _languagesDirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Langues sauvegardees avec succes !'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
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

  Future<String?> _promptCurrentPassword() async {
    final controller = TextEditingController();
    String? errorText;
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE7EEF8)),
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DEEE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Icon(
                          LucideIcons.lockKeyhole,
                          color: kSettingsBlue,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Confirmer votre identite',
                            style: TextStyle(
                              color: kSettingsText,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Pour supprimer definitivement votre compte, saisissez votre mot de passe actuel.',
                      style: TextStyle(
                        color: kSettingsBody,
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CupertinoTextField(
                      controller: controller,
                      obscureText: true,
                      autofocus: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      placeholder: 'Mot de passe actuel',
                      style: const TextStyle(
                        color: kSettingsText,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      placeholderStyle: const TextStyle(
                        color: kSettingsMuted,
                        fontSize: 15,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: errorText == null
                              ? kSettingsBorder
                              : const Color(0xFFFCA5A5),
                        ),
                      ),
                      onSubmitted: (_) {
                        final value = controller.text.trim();
                        if (value.isEmpty) {
                          setDialogState(() {
                            errorText = 'Le mot de passe est requis.';
                          });
                          return;
                        }
                        Navigator.of(dialogContext).pop(value);
                      },
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText,
                        style: const TextStyle(
                          color: kSettingsRed,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kSettingsText,
                              side: const BorderSide(color: kSettingsBorder),
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final value = controller.text.trim();
                              if (value.isEmpty) {
                                setDialogState(() {
                                  errorText = 'Le mot de passe est requis.';
                                });
                                return;
                              }
                              Navigator.of(dialogContext).pop(value);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: kSettingsBlue,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
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

    controller.dispose();
    return password;
  }

  Future<void> _reauthenticateForDeletion(User user) async {
    final providerIds = user.providerData
        .map((provider) => provider.providerId)
        .toSet();

    if (providerIds.contains(EmailAuthProvider.PROVIDER_ID)) {
      final password = await _promptCurrentPassword();
      if (password == null) {
        throw FirebaseAuthException(
          code: 'user-cancelled',
          message: 'Suppression annulee.',
        );
      }
      final email = user.email?.trim() ?? _emailCtrl.text.trim();
      if (email.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-email',
          message: 'Adresse e-mail introuvable pour la reauthentification.',
        );
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return;
    }

    if (providerIds.contains('google.com')) {
      final googleSignIn = GoogleSignIn(scopes: const ['email']);
      await googleSignIn.signOut();
      final googleAccount = await googleSignIn.signIn();
      if (googleAccount == null) {
        throw FirebaseAuthException(
          code: 'user-cancelled',
          message: 'Suppression annulee.',
        );
      }
      final googleAuth = await googleAccount.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providerIds.contains('apple.com')) {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      await user.reauthenticateWithProvider(provider);
    }
  }

  Future<String?> _showDeletionReasonPicker(String currentValue) async {
    final initialIndex =
        _deleteReasons.indexOf(currentValue) < 0
            ? 0
            : _deleteReasons.indexOf(currentValue);
    var selectedIndex = initialIndex;

    return showCupertinoModalPopup<String>(
      context: context,
      builder: (dialogContext) {
        return Container(
          height: 320,
          decoration: const BoxDecoration(
            color: Color(0xFFF7F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Annuler'),
                    ),
                    const Expanded(
                      child: Text(
                        'Motif de suppression',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: kSettingsText,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(dialogContext)
                          .pop(_deleteReasons[selectedIndex]),
                      child: const Text('Valider'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE3EAF7)),
              Expanded(
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: initialIndex,
                  ),
                  itemExtent: 42,
                  useMagnifier: true,
                  magnification: 1.05,
                  onSelectedItemChanged: (index) => selectedIndex = index,
                  children: _deleteReasons
                      .map(
                        (reason) => Center(
                          child: Text(
                            reason,
                            style: const TextStyle(
                              color: kSettingsText,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
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
      },
    );
  }

  Future<String?> _showDeleteAccountSheet() async {
    final confirmationController = TextEditingController();
    var selectedReason = _deleteReasons.first;
    var acknowledged = false;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final canContinue =
                acknowledged &&
                confirmationController.text.trim().toUpperCase() ==
                    'SUPPRIMER';
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE7EEF8)),
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5DEEE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            LucideIcons.badgeAlert,
                            color: kSettingsRed,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Suppression definitive du compte',
                                style: TextStyle(
                                  color: kSettingsText,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Cette action supprimera votre acces, votre profil et vos donnees principales.',
                                style: TextStyle(
                                  color: kSettingsBody,
                                  fontSize: 13,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kSettingsBorder),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ce qui sera supprime',
                            style: TextStyle(
                              color: kSettingsText,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 10),
                          _DeleteFlowBullet(
                            text: 'Votre compte Firebase Authentication',
                          ),
                          _DeleteFlowBullet(
                            text: 'Votre profil et vos donnees utilisateur dans Firestore',
                          ),
                          _DeleteFlowBullet(
                            text: 'Vos candidatures, stories et offres personnelles enregistrees',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Motif de suppression',
                      style: TextStyle(
                        color: kSettingsText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await _showDeletionReasonPicker(
                          selectedReason,
                        );
                        if (picked == null) return;
                        setSheetState(() => selectedReason = picked);
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: kSettingsBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.listFilter,
                              color: kSettingsBlue,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedReason,
                                style: const TextStyle(
                                  color: kSettingsText,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(
                              LucideIcons.chevronDown,
                              color: kSettingsMuted,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Tapez SUPPRIMER pour confirmer',
                      style: TextStyle(
                        color: kSettingsText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: confirmationController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setSheetState(() {}),
                      placeholder: 'SUPPRIMER',
                      style: const TextStyle(
                        color: kSettingsText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: confirmationController.text.isEmpty
                              ? kSettingsBorder
                              : canContinue
                                  ? const Color(0xFFBBF7D0)
                                  : const Color(0xFFFECACA),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => setSheetState(
                        () => acknowledged = !acknowledged,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: acknowledged
                              ? const Color(0xFFFFF1F2)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: acknowledged
                                ? const Color(0xFFFDA4AF)
                                : kSettingsBorder,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              acknowledged
                                  ? LucideIcons.checkCircle2
                                  : LucideIcons.circle,
                              color: acknowledged
                                  ? kSettingsRed
                                  : kSettingsMuted,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Je comprends que cette suppression est definitive et que je devrai creer un nouveau compte pour revenir.',
                                style: TextStyle(
                                  color: kSettingsBody,
                                  fontSize: 13,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kSettingsText,
                              side: const BorderSide(color: kSettingsBorder),
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: canContinue
                                ? () => Navigator.of(dialogContext)
                                    .pop(selectedReason)
                                : null,
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            label: const Text('Supprimer'),
                            style: FilledButton.styleFrom(
                              backgroundColor: kSettingsRed,
                              disabledBackgroundColor:
                                  const Color(0xFFFCA5A5),
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
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

    confirmationController.dispose();
    return result;
  }

  Future<void> _deleteDocsByField({
    required FirebaseFirestore firestore,
    required String collection,
    required String field,
    required String value,
  }) async {
    final snapshot = await firestore
        .collection(collection)
        .where(field, isEqualTo: value)
        .get();
    if (snapshot.docs.isEmpty) return;

    for (var i = 0; i < snapshot.docs.length; i += 400) {
      final batch = firestore.batch();
      final chunk = snapshot.docs.skip(i).take(400);
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _deleteFirestoreAccountData(
    String uid, {
    required String deletionReason,
  }) async {
    final firestore = FirebaseFirestore.instance;

    await Future.wait([
      firestore.collection('profiles').doc(uid).delete(),
      firestore.collection('users').doc(uid).delete(),
      _deleteDocsByField(
        firestore: firestore,
        collection: 'worker_offers',
        field: 'workerId',
        value: uid,
      ),
      _deleteDocsByField(
        firestore: firestore,
        collection: 'workers offers',
        field: 'workerId',
        value: uid,
      ),
      _deleteDocsByField(
        firestore: firestore,
        collection: 'offer_applications',
        field: 'workerId',
        value: uid,
      ),
      _deleteDocsByField(
        firestore: firestore,
        collection: 'stories',
        field: 'ownerUid',
        value: uid,
      ),
      _deleteDocsByField(
        firestore: firestore,
        collection: 'role_requests',
        field: 'userId',
        value: uid,
      ),
      _deleteDocsByField(
        firestore: firestore,
        collection: 'role_requests',
        field: 'requesterId',
        value: uid,
      ),
    ]);

    debugPrint(
      'Account deletion cleanup complete for uid=$uid, reason=$deletionReason',
    );
  }

  Future<void> _deleteAccount() async {
    final deletionReason = await _showDeleteAccountSheet();
    if (deletionReason == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _isDeletingAccount = true;
      });
    }

    try {
      final uid = user.uid;
      await _reauthenticateForDeletion(user);
      await _deleteFirestoreAccountData(uid, deletionReason: deletionReason);
      await user.delete();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isLoggedIn');
      await prefs.remove('userId');
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'wrong-password' =>
          'Le mot de passe saisi est incorrect. Le compte n a pas ete supprime.',
        'requires-recent-login' =>
          'Reconnectez-vous puis recommencez pour confirmer la suppression du compte.',
        'user-cancelled' => 'Suppression du compte annulee.',
        _ => e.message ?? 'Impossible de supprimer le compte pour le moment.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible de supprimer le compte: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isDeletingAccount = false;
        });
      }
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

  Widget _languageTile({
    required String flag,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            decoration: const BoxDecoration(
              color: kSettingsLightBlue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(flag, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: kSettingsText,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: Colors.green,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagesSection() {
    return Column(
      children: [
        _languageTile(
          flag: '🇫🇷',
          label: 'Français',
          value: _speaksFrench,
          onChanged: (v) => setState(() {
            _speaksFrench = v;
            _languagesDirty = true;
          }),
        ),
        const SizedBox(height: 12),
        _languageTile(
          flag: '🇬🇧',
          label: 'Anglais',
          value: _speaksEnglish,
          onChanged: (v) => setState(() {
            _speaksEnglish = v;
            _languagesDirty = true;
          }),
        ),
        const SizedBox(height: 12),
        _languageTile(
          flag: '🇩🇿',
          label: 'Arabe',
          value: _speaksArabic,
          onChanged: (v) => setState(() {
            _speaksArabic = v;
            _languagesDirty = true;
          }),
        ),
        const SizedBox(height: 12),
        _languageTile(
          flag: '🇪🇸',
          label: 'Espagnol',
          value: _speaksSpanish,
          onChanged: (v) => setState(() {
            _speaksSpanish = v;
            _languagesDirty = true;
          }),
        ),
        if (_languagesDirty) _buildSectionSaveButton(_saveLanguages),
      ],
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
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              );
            },
            icon: const Icon(LucideIcons.fileLock2, size: 18),
            label: const Text('Lire la politique de confidentialite'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kSettingsBlue,
              side: const BorderSide(color: Color(0xFFBDD5FF)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
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

  Widget _buildDangerSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.triangleAlert, color: kSettingsRed, size: 20),
              SizedBox(width: 10),
              Text(
                'Suppression definitive',
                style: TextStyle(
                  color: kSettingsText,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Supprimez votre compte directement depuis l application si vous ne souhaitez plus utiliser StayFix Job.',
            style: TextStyle(
              color: kSettingsBody,
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_isLoading || _isDeletingAccount)
                  ? null
                  : _deleteAccount,
              icon: _isDeletingAccount
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.trash2, size: 18),
              label: Text(
                _isDeletingAccount
                    ? 'Suppression en cours...'
                    : 'Supprimer mon compte',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: kSettingsRed,
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteAccountCallout() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF5F5), Color(0xFFFFF1F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFFECACA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10FF4D4F),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  LucideIcons.shieldAlert,
                  color: kSettingsRed,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suppression du compte',
                      style: TextStyle(
                        color: kSettingsText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Option visible dans l application pour supprimer definitivement votre compte et vos donnees principales.',
                      style: TextStyle(
                        color: kSettingsBody,
                        fontSize: 13.2,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_isLoading || _isDeletingAccount)
                  ? null
                  : _deleteAccount,
              icon: _isDeletingAccount
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.trash2, size: 18),
              label: Text(
                _isDeletingAccount
                    ? 'Suppression en cours...'
                    : 'Supprimer mon compte maintenant',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: kSettingsRed,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
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
            _buildDeleteAccountCallout(),
            const SizedBox(height: 14),
            _sectionShell(
              id: 'account',
              icon: LucideIcons.user,
              title: 'Compte',
              subtitle: 'Gerez vos informations de compte',
              child: _buildAccountSection(),
            ),
            const SizedBox(height: 14),
            _sectionShell(
              id: 'languages',
              icon: LucideIcons.globe,
              title: 'Langues que je parle',
              subtitle: 'Langues parlees et comprises',
              child: _buildLanguagesSection(),
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
            const SizedBox(height: 14),
            _sectionShell(
              id: 'danger',
              icon: LucideIcons.shieldAlert,
              title: 'Suppression du compte',
              subtitle: 'Suppression definitive du compte depuis l application',
              child: _buildDangerSection(),
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

class _DeleteFlowBullet extends StatelessWidget {
  const _DeleteFlowBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(
              Icons.circle,
              color: kSettingsRed,
              size: 8,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: kSettingsBody,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
