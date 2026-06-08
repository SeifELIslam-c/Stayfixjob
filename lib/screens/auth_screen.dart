// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/vps_media_service.dart';
import 'home_screen.dart';
import 'role_selection_screen.dart';
import 'terms_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _googleLogoSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#FFC107" d="M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12c0-6.627,5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24c0,11.045,8.955,20,20,20c11.045,0,20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z"/>
<path fill="#FF3D00" d="M6.306,14.691l6.571,4.819C14.655,15.108,18.961,12,24,12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C16.318,4,9.656,8.337,6.306,14.691z"/>
<path fill="#4CAF50" d="M24,44c5.166,0,9.86-1.977,13.409-5.192l-6.19-5.238C29.211,35.091,26.715,36,24,36c-5.202,0-9.619-3.317-11.283-7.946l-6.522,5.025C9.505,39.556,16.227,44,24,44z"/>
<path fill="#1976D2" d="M43.611,20.083H42V20H24v8h11.303c-0.792,2.237-2.231,4.166-4.087,5.571c0.001-0.001,0.002-0.001,0.003-0.002l6.19,5.238C36.971,39.205,44,34,44,24C44,22.659,43.862,21.35,43.611,20.083z"/>
</svg>
''';

  bool _isRegisterMode = false;
  bool _isLoading = false;
  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _obscureRegisterConfirmPassword = true;
  bool _rememberMe = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _phoneComplete = '';
  String _phoneCountryIso = 'CA';
  String _phoneDialCode = '1';

  Widget _buildGoogleLogo({required bool compact}) {
    return SvgPicture.string(
      _googleLogoSvg,
      width: compact ? 18 : 20,
      height: compact ? 18 : 20,
    );
  }

  bool get _supportsAppleSignIn =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  String _defaultProfileName({String fallback = 'Employe'}) {
    final typedName = _nameController.text.trim();
    if (typedName.isNotEmpty) return typedName;

    final email = _emailController.text.trim();
    if (email.contains('@')) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty) return localPart;
    }

    return fallback;
  }

  String _resolvedProfileName(
    User user, {
    String? preferredName,
    String fallback = 'Employe',
  }) {
    final candidates = <String?>[
      preferredName,
      user.displayName,
      _nameController.text.trim(),
      _defaultProfileName(fallback: fallback),
    ];
    for (final candidate in candidates) {
      final value = candidate?.trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'utilisateur') {
        return value;
      }
    }
    return fallback;
  }

  String _resolvedProfilePhotoUrl(User user, {String? preferredPhotoUrl}) {
    final candidates = <String?>[preferredPhotoUrl, user.photoURL];
    for (final candidate in candidates) {
      final value = candidate?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  bool _isGenericUserName(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'utilisateur' ||
        normalized == 'employe' ||
        normalized == 'employé' ||
        normalized == 'employe (nouveau)' ||
        normalized == 'employé (nouveau)';
  }

  Future<({Map<String, dynamic> data, bool created})> _syncProfileFromAuth(
    User user, {
    String? profileName,
    String? profileEmail,
    String? profilePhone,
    String? profilePhotoUrl,
    bool preferIncomingName = false,
  }) async {
    final profileRef = FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid);
    final snapshot = await profileRef.get();
    final existingData = snapshot.data() ?? <String, dynamic>{};

    final incomingName = _resolvedProfileName(user, preferredName: profileName);
    final existingName = (existingData['username'] as String?)?.trim() ?? '';
    final finalName = (preferIncomingName || _isGenericUserName(existingName))
        ? incomingName
        : (existingName.isNotEmpty ? existingName : incomingName);

    final incomingEmail = (profileEmail ?? user.email ?? '').trim();
    final existingEmail = (existingData['email'] as String?)?.trim() ?? '';
    final incomingPhone = (profilePhone ?? _phoneComplete).trim();
    final existingPhone = (existingData['phone'] as String?)?.trim() ?? '';
    final incomingPhotoUrl = _resolvedProfilePhotoUrl(
      user,
      preferredPhotoUrl: profilePhotoUrl,
    );
    final existingPhotoUrl = VpsMediaService.resolveProfileImageUrl(
      existingData,
    );

    final updates = <String, dynamic>{
      'id': user.uid,
      'username': finalName,
      'name': finalName,
      'workerName': finalName,
      'email': incomingEmail.isNotEmpty ? incomingEmail : existingEmail,
      'phone': incomingPhone.isNotEmpty ? incomingPhone : existingPhone,
      'phoneNational': _phoneController.text.trim(),
      'phoneCountryIso': _phoneCountryIso,
      'phoneDialCode': _phoneDialCode,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!snapshot.exists) {
      updates.addAll({
        'department': '',
        'maintenanceType': '',
        'specialties': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final finalPhotoUrl = incomingPhotoUrl.isNotEmpty
        ? incomingPhotoUrl
        : (existingPhotoUrl ?? '');
    if (finalPhotoUrl.isNotEmpty) {
      updates['photoURL'] = finalPhotoUrl;
      updates['photoUrl'] = finalPhotoUrl;
    }

    await profileRef.set(updates, SetOptions(merge: true));
    return (
      data: <String, dynamic>{...existingData, ...updates},
      created: !snapshot.exists,
    );
  }

  Future<bool> _isStayFixConcierge(String userId) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    final userData = userDoc.data() ?? <String, dynamic>{};
    return userData['accountType'] == 'concierge' &&
        userData['appAccess'] == 'stayfix_job' &&
        userData['status'] != 'deleted';
  }

  bool _hasAnySelectionData(Map<String, dynamic> profileData) {
    final department = (profileData['department'] as String? ?? '').trim();
    final maintenanceType =
        (profileData['maintenanceType'] as String? ?? '').trim();
    final specialties = (profileData['specialties'] as List? ?? const <dynamic>[])
        .where((value) => value.toString().trim().isNotEmpty)
        .toList();
    return department.isNotEmpty ||
        maintenanceType.isNotEmpty ||
        specialties.isNotEmpty;
  }

  bool _shouldTreatTermsAsAccepted(Map<String, dynamic> profileData) {
    if (profileData['termsAccepted'] == true) return true;
    return _hasAnySelectionData(profileData);
  }

  Future<void> _routeAuthenticatedUser(
    Map<String, dynamic> profileData, {
    required String userId,
    bool isExistingAccount = false,
  }) async {
    final isStayFixConcierge = await _isStayFixConcierge(userId);
    final dept = (profileData['department'] as String? ?? '').trim();
    final termsAccepted = _shouldTreatTermsAsAccepted(profileData);

    if (!mounted) return;
    if (isExistingAccount) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
      );
      return;
    }
    if (!termsAccepted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TermsScreen(
            nextScreen: isStayFixConcierge
                ? const HomeScreen(requireAuth: false)
                : null,
          ),
        ),
      );
    } else if (!isStayFixConcierge && dept.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
      );
    }
  }

  Future<void> _completeAuthenticatedUser(
    UserCredential userCredential, {
    String? profileName,
    String? profileEmail,
    String? profilePhone,
    String? profilePhotoUrl,
    bool preferIncomingName = false,
  }) async {
    final user = userCredential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'null-user',
        message: 'Aucun utilisateur Firebase n a ete retourne.',
      );
    }

    final userId = user.uid;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);

    final result = await _syncProfileFromAuth(
      user,
      profileName: profileName,
      profileEmail: profileEmail,
      profilePhone: profilePhone,
      profilePhotoUrl: profilePhotoUrl,
      preferIncomingName: preferIncomingName,
    );

    // Check for concierge account (created by StayFix manager app)
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    final userData = userDoc.data() ?? <String, dynamic>{};
    final accountType = userData['accountType'] as String?;
    final appAccess = userData['appAccess'] as String?;
    final userStatus = userData['status'] as String?;

    if (accountType == 'concierge' && appAccess == 'stayfix_job') {
      if (userStatus == 'deleted') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ce compte a été désactivé.')),
        );
        return;
      }
      if (!mounted) return;
      // Concierge must accept terms but never goes through RoleSelectionScreen
      final termsAccepted = result.data['termsAccepted'] ?? false;
      if (!termsAccepted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const TermsScreen(nextScreen: HomeScreen(requireAuth: false)),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const HomeScreen(requireAuth: false),
          ),
        );
      }
      return;
    }

    if (result.created) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TermsScreen()),
      );
      return;
    }

    await _routeAuthenticatedUser(
      result.data,
      userId: userId,
      isExistingAccount: !result.created,
    );
  }

  void _handleSubmit() async {
    if (_isRegisterMode && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nom d'utilisateur requis"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email et Mot de passe requis'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_isRegisterMode &&
        _passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les mots de passe ne correspondent pas'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = FirebaseAuth.instance;
      final db = FirebaseFirestore.instance;
      UserCredential userCredential;

      if (_isRegisterMode) {
        try {
          userCredential = await auth.createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Compte existant. Connexion automatique...'),
                backgroundColor: Colors.orange,
              ),
            );
            userCredential = await auth.signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
          } else {
            rethrow;
          }
        }
      } else {
        userCredential = await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }

      final userId = userCredential.user!.uid;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', userId);

      if (_isRegisterMode) {
        await userCredential.user?.updateDisplayName(
          _nameController.text.trim(),
        );
      }

      final syncedProfile = await _syncProfileFromAuth(
        userCredential.user!,
        profileName: _isRegisterMode ? _nameController.text.trim() : null,
        profileEmail: _emailController.text.trim(),
        profilePhone: _phoneComplete.isNotEmpty
            ? _phoneComplete
            : _phoneController.text.trim(),
        preferIncomingName: _isRegisterMode,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (syncedProfile.created) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TermsScreen()),
          );
          return;
        }

        await _routeAuthenticatedUser(syncedProfile.data, userId: userId);
      }
      return;

      // ignore: dead_code
      final docSnapshot = await db.collection('profiles').doc(userId).get();

      if (!docSnapshot.exists) {
        await db.collection('profiles').doc(userId).set({
          'id': userId,
          'username': _nameController.text.isNotEmpty
              ? _nameController.text.trim()
              : 'Employé (Nouveau)',
          'email': _emailController.text.trim(),
          'phone': _phoneComplete.isNotEmpty
              ? _phoneComplete
              : _phoneController.text.trim(),
          'phoneNational': _phoneController.text.trim(),
          'phoneCountryIso': _phoneCountryIso,
          'phoneDialCode': _phoneDialCode,
          'department': '',
          'maintenanceType': '',
          'specialties': [],
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TermsScreen()),
          );
        }
      } else {
        final data = docSnapshot.data()!;
        final dept = data['department'] ?? '';
        final termsAccepted = data['termsAccepted'] ?? false;

        if (mounted) {
          setState(() => _isLoading = false);
          if (!termsAccepted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            );
          } else if (dept.isEmpty) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const HomeScreen(requireAuth: false),
              ),
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      String errorMessage = 'Erreur de connexion';
      if (e.code == 'weak-password')
        errorMessage = 'Le mot de passe est trop faible.';
      else if (e.code == 'user-not-found' || e.code == 'wrong-password')
        errorMessage = 'Email ou mot de passe incorrect.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn(scopes: const ['email']);
      await googleSignIn.signOut();
      final googleAccount = await googleSignIn.signIn();
      if (googleAccount == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleAccount.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      await _completeAuthenticatedUser(
        userCredential,
        profileName: userCredential.user?.displayName ?? _defaultProfileName(),
        profileEmail:
            userCredential.user?.email ?? _emailController.text.trim(),
        profilePhotoUrl: userCredential.user?.photoURL,
        preferIncomingName: true,
      );
      final userId = userCredential.user!.uid;
      var skipLegacyGoogleBootstrap = DateTime.now().microsecond < 0;
      if (skipLegacyGoogleBootstrap) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userId', userId);

        final db = FirebaseFirestore.instance;
        final docSnapshot = await db.collection('profiles').doc(userId).get();

        if (!docSnapshot.exists) {
          await db.collection('profiles').doc(userId).set({
            'id': userId,
            'username': userCredential.user?.displayName ?? 'Employé',
            'email': userCredential.user?.email ?? '',
            'phone': '',
            'department': '',
            'maintenanceType': '',
            'specialties': [],
            'createdAt': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            );
          }
        } else {
          final data = docSnapshot.data()!;
          final dept = data['department'] ?? '';
          final termsAccepted = data['termsAccepted'] ?? false;

          if (mounted) {
            if (!termsAccepted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const TermsScreen()),
              );
            } else if (dept.isEmpty) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const HomeScreen(requireAuth: false),
                ),
              );
            }
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur Google Sign-In: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString().contains('ApiException: 10')
            ? "Google Sign-In n'est pas configure pour com.rezzaky.stayfix_job/SHA. Telechargez un nouveau google-services.json apres avoir ajoute SHA-1 et SHA-256 dans Firebase."
            : 'Erreur: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final appleProvider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      final userCredential = await FirebaseAuth.instance.signInWithProvider(
        appleProvider,
      );

      await _completeAuthenticatedUser(
        userCredential,
        profileName:
            userCredential.user?.displayName ??
            _defaultProfileName(fallback: 'Employe Apple'),
        profileEmail:
            userCredential.user?.email ?? _emailController.text.trim(),
        profilePhotoUrl: userCredential.user?.photoURL,
        preferIncomingName: true,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'web-context-cancelled'
                  ? 'Connexion Apple annulee.'
                  : 'Erreur Sign in with Apple: ${e.message ?? e.code}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur Apple Sign-In: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    bool isSending = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSending,
      builder: (dialogContext) {
        const heroBlue = Color(0xFF0F63FF);
        const headingColor = Color(0xFF13203F);
        const bodyColor = Color(0xFF7C8BA8);
        const fieldBorderColor = Color(0xFFE3EBF9);
        const iconColor = Color(0xFF7D8CAF);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submitReset() async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                setDialogState(() {
                  errorText = 'Veuillez saisir votre adresse e-mail.';
                });
                return;
              }

              setDialogState(() {
                isSending = true;
                errorText = null;
              });

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                /*

                  if (response.statusCode < 200 || response.statusCode >= 300) {
                    String message = 'Impossible d’envoyer l’e-mail.';
                    try {
                      final parsed = jsonDecode(responseBody);
                      if (parsed is Map &&
                          parsed['message'] is String &&
                          (parsed['message'] as String).isNotEmpty) {
                        message = parsed['message'] as String;
                      }
                    } catch (_) {}
                    throw Exception(message);
                  }
                } finally {
                  client.close();
                }

                */
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Si ce compte existe, un email de réinitialisation a été envoyé.',
                    ),
                    backgroundColor: Color(0xFF0F9D58),
                  ),
                );
              } catch (e) {
                String message = 'Impossible d’envoyer l’e-mail.';
                final raw = e.toString();
                if (raw.contains('Email is required')) {
                  message = 'Veuillez saisir votre adresse e-mail.';
                } else if (raw.contains('Server configuration error')) {
                  message =
                      'Le service de réinitialisation n’est pas configuré correctement.';
                } else if (raw.contains('invalid-email')) {
                  message = 'Adresse e-mail invalide.';
                } else if (raw.contains('SocketException')) {
                  message =
                      'Impossible de joindre le serveur de réinitialisation.';
                } else if (raw.contains('TimeoutException')) {
                  message =
                      'Le serveur met trop de temps à répondre. Réessayez.';
                } else if (raw.startsWith('Exception: ')) {
                  message = raw.substring('Exception: '.length);
                }

                setDialogState(() {
                  isSending = false;
                  errorText = message;
                });
              }
            }

            return MediaQuery.removeViewInsets(
              removeBottom: true,
              context: dialogContext,
              child: Material(
                color: Colors.transparent,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1A0F63FF),
                              blurRadius: 30,
                              offset: Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mot de passe oublié ?',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: headingColor,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Saisissez votre adresse e-mail pour recevoir un lien de réinitialisation.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: bodyColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: fieldBorderColor),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0A163B7A),
                                    blurRadius: 18,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                enabled: !isSending,
                                scrollPadding: EdgeInsets.zero,
                                style: const TextStyle(
                                  color: headingColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Adresse E-mail',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF8B98B3),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  prefixIcon: Icon(
                                    LucideIcons.mail,
                                    color: iconColor,
                                    size: 20,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 18,
                                  ),
                                ),
                                onSubmitted: (_) {
                                  if (!isSending) submitReset();
                                },
                              ),
                            ),
                            if (errorText != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                errorText!,
                                style: const TextStyle(
                                  color: Color(0xFFD93025),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: isSending ? null : submitReset,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [heroBlue, Color(0xFF1A56DB)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  child: Center(
                                    child: isSending
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Envoyer l’e-mail',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: isSending
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                child: const Text('Annuler'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Widget _buildSocialButton({
    required String label,
    required VoidCallback? onPressed,
    required Widget icon,
    required bool compact,
    Color backgroundColor = Colors.white,
    Color foregroundColor = const Color(0xFF13203F),
    BorderSide side = const BorderSide(color: Color(0xFFD9E4F7)),
  }) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 48 : 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: side,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRegisterMode) {
      return _buildRegisterScaffold();
    }
    return _buildLoginScaffold();
  }

  Widget _buildLoginScaffold() {
    final theme = Theme.of(context);
    const heroBlue = Color(0xFF0F63FF);
    const heroBlueDark = Color(0xFF1C4FCE);
    const cardBackground = Color(0xFFFDFEFF);
    const headingColor = Color(0xFF13203F);
    const bodyColor = Color(0xFF7C8BA8);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF1F6FF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F8FF), Color(0xFFEAF1FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ultraCompact = constraints.maxHeight < 700;
            final heroHeight = (constraints.maxHeight * 0.39).clamp(
              255.0,
              360.0,
            );
            final horizontalPadding = ultraCompact ? 20.0 : 24.0;
            final topPadding = ultraCompact ? 8.0 : 12.0;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    _buildHero(
                      heroHeight: heroHeight,
                      heroBlue: heroBlue,
                      heroBlueDark: heroBlueDark,
                      cardBackground: cardBackground,
                      bridgeHeight: 22,
                    ),
                    Container(
                      width: double.infinity,
                      transform: Matrix4.translationValues(0, -18, 0),
                      decoration: const BoxDecoration(
                        color: cardBackground,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(34),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x140F63FF),
                            blurRadius: 28,
                            offset: Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          topPadding,
                          horizontalPadding,
                          24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bienvenue',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: heroBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: ultraCompact ? 13 : 14,
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 2 : 4),
                            Text(
                              'Connexion',
                              style:
                                  (ultraCompact
                                          ? theme.textTheme.headlineSmall
                                          : theme.textTheme.headlineMedium)
                                      ?.copyWith(
                                        color: headingColor,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.6,
                                      ),
                            ),
                            SizedBox(height: ultraCompact ? 2 : 4),
                            Text(
                              'Accédez à votre espace personnel',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: bodyColor,
                                fontWeight: FontWeight.w500,
                                fontSize: ultraCompact ? 13 : 14,
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 12 : 16),
                            _buildLoginTextField(
                              label: 'Adresse E-mail',
                              controller: _emailController,
                              icon: LucideIcons.mail,
                              keyboardType: TextInputType.emailAddress,
                              compact: ultraCompact,
                            ),
                            SizedBox(height: ultraCompact ? 4 : 8),
                            _buildLoginTextField(
                              label: 'Mot de passe',
                              controller: _passwordController,
                              icon: LucideIcons.lock,
                              isPassword: true,
                              compact: ultraCompact,
                            ),
                            SizedBox(height: ultraCompact ? 4 : 8),
                            Row(
                              children: [
                                Transform.scale(
                                  scale: ultraCompact ? 0.78 : 0.88,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: heroBlue,
                                    side: const BorderSide(
                                      color: Color(0xFFD5E0F5),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _rememberMe = value ?? false;
                                      });
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    'Se souvenir de moi',
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: bodyColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: ultraCompact ? 10.5 : 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _showForgotPasswordDialog,
                                  style: TextButton.styleFrom(
                                    foregroundColor: heroBlue,
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Mot de passe oublié ?',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: heroBlue,
                                      fontWeight: FontWeight.w700,
                                      fontSize: ultraCompact ? 10.5 : 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: ultraCompact ? 8 : 12),
                            SizedBox(
                              width: double.infinity,
                              height: ultraCompact ? 52 : 58,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(31),
                                  ),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [heroBlue, Color(0xFF1A56DB)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(31),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x330F63FF),
                                        blurRadius: 24,
                                        offset: Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: ultraCompact ? 36 : 40,
                                          height: ultraCompact ? 36 : 40,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            LucideIcons.arrowRight,
                                            color: heroBlue,
                                            size: 18,
                                          ),
                                        ),
                                        Expanded(
                                          child: Center(
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2.4,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : Text(
                                                    'Se connecter',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: ultraCompact
                                                          ? 15
                                                          : 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        SizedBox(width: ultraCompact ? 36 : 40),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 10 : 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: const Color(0xFFE2E9F5),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    'OU',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: bodyColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: ultraCompact ? 11 : 12,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: const Color(0xFFE2E9F5),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: ultraCompact ? 10 : 16),
                            _buildSocialButton(
                              label: 'Continuer avec Google',
                              onPressed: _isLoading ? null : _signInWithGoogle,
                              icon: _buildGoogleLogo(compact: ultraCompact),
                              compact: ultraCompact,
                            ),
                            if (_supportsAppleSignIn) ...[
                              SizedBox(height: ultraCompact ? 8 : 10),
                              _buildSocialButton(
                                label: 'Continuer avec Apple',
                                onPressed: _isLoading ? null : _signInWithApple,
                                icon: Icon(
                                  Icons.apple,
                                  size: ultraCompact ? 18 : 20,
                                ),
                                compact: ultraCompact,
                                backgroundColor: const Color(0xFF111111),
                                foregroundColor: Colors.white,
                                side: BorderSide.none,
                              ),
                            ],
                            SizedBox(height: ultraCompact ? 4 : 8),
                            Center(
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isRegisterMode = true;
                                    _passwordController.clear();
                                    _confirmPasswordController.clear();
                                  });
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: heroBlue,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(
                                  LucideIcons.userPlus,
                                  size: 16,
                                ),
                                label: Text(
                                  'Pas de compte ? Inscrivez-vous',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: ultraCompact ? 12.5 : 13.5,
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildRegisterScaffold() {
    final theme = Theme.of(context);
    const heroBlue = Color(0xFF0F63FF);
    const heroBlueDark = Color(0xFF1C4FCE);
    const cardBackground = Color(0xFFFDFEFF);
    const headingColor = Color(0xFF13203F);
    const bodyColor = Color(0xFF7C8BA8);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF1F6FF),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F8FF), Color(0xFFEAF1FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ultraCompact = constraints.maxHeight < 860;
            final heroHeight = (constraints.maxHeight * 0.24).clamp(
              150.0,
              215.0,
            );
            final horizontalPadding = ultraCompact ? 20.0 : 24.0;
            final topPadding = ultraCompact ? 6.0 : 10.0;
            final bottomPadding = ultraCompact ? 6.0 : 10.0;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    _buildHero(
                      heroHeight: heroHeight,
                      heroBlue: heroBlue,
                      heroBlueDark: heroBlueDark,
                      cardBackground: cardBackground,
                      bridgeHeight: 22,
                    ),
                    Container(
                      width: double.infinity,
                      transform: Matrix4.translationValues(0, -18, 0),
                      decoration: const BoxDecoration(
                        color: cardBackground,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(34),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x140F63FF),
                            blurRadius: 28,
                            offset: Offset(0, -8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          topPadding,
                          horizontalPadding,
                          bottomPadding + 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nouveau compte',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: heroBlue,
                                fontWeight: FontWeight.w700,
                                fontSize: ultraCompact ? 13 : 14,
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 2 : 4),
                            Text(
                              'Inscription',
                              style:
                                  (ultraCompact
                                          ? theme.textTheme.headlineSmall
                                          : theme.textTheme.headlineMedium)
                                      ?.copyWith(
                                        color: headingColor,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.6,
                                      ),
                            ),
                            SizedBox(height: ultraCompact ? 2 : 4),
                            Text(
                              'Créez votre espace professionnel',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: bodyColor,
                                fontWeight: FontWeight.w500,
                                fontSize: ultraCompact ? 13 : 14,
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 8 : 10),
                            Container(
                              width: 54,
                              height: 4,
                              decoration: BoxDecoration(
                                color: heroBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 10 : 14),
                            _buildRegisterField(
                              label: 'Nom d’utilisateur',
                              controller: _nameController,
                              icon: LucideIcons.user,
                              compact: ultraCompact,
                            ),
                            SizedBox(height: ultraCompact ? 6 : 10),
                            _buildPhoneField(compact: ultraCompact),
                            SizedBox(height: ultraCompact ? 6 : 10),
                            _buildRegisterField(
                              label: 'Adresse E-mail',
                              controller: _emailController,
                              icon: LucideIcons.mail,
                              compact: ultraCompact,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            SizedBox(height: ultraCompact ? 6 : 10),
                            _buildRegisterField(
                              label: 'Mot de passe',
                              controller: _passwordController,
                              icon: LucideIcons.lock,
                              isPassword: true,
                              compact: ultraCompact,
                              obscureText: _obscureRegisterPassword,
                              onTogglePassword: () {
                                setState(() {
                                  _obscureRegisterPassword =
                                      !_obscureRegisterPassword;
                                });
                              },
                            ),
                            SizedBox(height: ultraCompact ? 6 : 10),
                            _buildRegisterField(
                              label: 'Confirmer le mot de passe',
                              controller: _confirmPasswordController,
                              icon: LucideIcons.lock,
                              isPassword: true,
                              compact: ultraCompact,
                              obscureText: _obscureRegisterConfirmPassword,
                              onTogglePassword: () {
                                setState(() {
                                  _obscureRegisterConfirmPassword =
                                      !_obscureRegisterConfirmPassword;
                                });
                              },
                            ),
                            SizedBox(height: ultraCompact ? 2 : 4),
                            SizedBox(
                              width: double.infinity,
                              height: ultraCompact ? 52 : 58,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(31),
                                  ),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [heroBlue, Color(0xFF1A56DB)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(31),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x330F63FF),
                                        blurRadius: 24,
                                        offset: Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: ultraCompact ? 36 : 40,
                                          height: ultraCompact ? 36 : 40,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            LucideIcons.arrowRight,
                                            color: heroBlue,
                                            size: 18,
                                          ),
                                        ),
                                        Expanded(
                                          child: Center(
                                            child: _isLoading
                                                ? const SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2.4,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : Text(
                                                    'Créer un compte',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: ultraCompact
                                                          ? 15
                                                          : 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        SizedBox(width: ultraCompact ? 36 : 40),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: ultraCompact ? 8 : 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: const Color(0xFFE2E9F5),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    'OU',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: bodyColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: ultraCompact ? 11 : 12,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: const Color(0xFFE2E9F5),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: ultraCompact ? 8 : 12),
                            _buildSocialButton(
                              label: 'Continuer avec Google',
                              onPressed: _isLoading ? null : _signInWithGoogle,
                              icon: _buildGoogleLogo(compact: ultraCompact),
                              compact: ultraCompact,
                            ),
                            if (_supportsAppleSignIn) ...[
                              SizedBox(height: ultraCompact ? 8 : 10),
                              _buildSocialButton(
                                label: 'Continuer avec Apple',
                                onPressed: _isLoading ? null : _signInWithApple,
                                icon: Icon(
                                  Icons.apple,
                                  size: ultraCompact ? 18 : 20,
                                ),
                                compact: ultraCompact,
                                backgroundColor: const Color(0xFF111111),
                                foregroundColor: Colors.white,
                                side: BorderSide.none,
                              ),
                            ],
                            SizedBox(height: ultraCompact ? 2 : 6),
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isRegisterMode = false;
                                    _passwordController.clear();
                                    _confirmPasswordController.clear();
                                  });
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: heroBlue,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: ultraCompact ? 12.5 : 13.5,
                                      color: bodyColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    children: const [
                                      TextSpan(
                                        text: 'Vous avez déjà un compte ? ',
                                      ),
                                      TextSpan(
                                        text: 'Connectez-vous',
                                        style: TextStyle(
                                          color: heroBlue,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero({
    required double heroHeight,
    required Color heroBlue,
    required Color heroBlueDark,
    required Color cardBackground,
    required double bridgeHeight,
  }) {
    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [heroBlue, heroBlueDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Image.asset(
            'lib/assets/icon/heroimg.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0),
                  heroBlue.withValues(alpha: 0.08),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            child: Container(
              height: bridgeHeight,
              decoration: BoxDecoration(
                color: cardBackground,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(34),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
    bool compact = false,
    TextInputType? keyboardType,
  }) {
    const fieldBorderColor = Color(0xFFE3EBF9);
    const iconColor = Color(0xFF7D8CAF);
    const textColor = Color(0xFF13203F);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fieldBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A163B7A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: isPassword ? _obscureLoginPassword : false,
        style: TextStyle(
          color: textColor,
          fontSize: compact ? 14 : 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(
            color: const Color(0xFF8B98B3),
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: iconColor, size: compact ? 18 : 20),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      _obscureLoginPassword = !_obscureLoginPassword;
                    });
                  },
                  icon: Icon(
                    _obscureLoginPassword
                        ? LucideIcons.eye
                        : LucideIcons.eyeOff,
                    color: iconColor,
                    size: compact ? 18 : 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 18,
            vertical: compact ? 15 : 18,
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    bool compact = false,
    TextInputType? keyboardType,
    VoidCallback? onTogglePassword,
  }) {
    const fieldBorderColor = Color(0xFFE3EBF9);
    const iconColor = Color(0xFF7D8CAF);
    const textColor = Color(0xFF13203F);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fieldBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A163B7A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: isPassword ? obscureText : false,
        style: TextStyle(
          color: textColor,
          fontSize: compact ? 14 : 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(
            color: const Color(0xFF8B98B3),
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: iconColor, size: compact ? 18 : 20),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(
                    obscureText ? LucideIcons.eye : LucideIcons.eyeOff,
                    color: iconColor,
                    size: compact ? 18 : 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 18,
            vertical: compact ? 15 : 18,
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneField({required bool compact}) {
    const fieldBorderColor = Color(0xFFE3EBF9);
    const iconColor = Color(0xFF7D8CAF);
    const textColor = Color(0xFF13203F);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fieldBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A163B7A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: Colors.white,
          dialogTheme: DialogThemeData(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Colors.white,
          ),
        ),
        child: IntlPhoneField(
          controller: _phoneController,
          initialCountryCode: 'CA',
          disableLengthCheck: true,
          style: TextStyle(
            color: textColor,
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w500,
          ),
          dropdownTextStyle: TextStyle(
            color: textColor,
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w600,
          ),
          pickerDialogStyle: PickerDialogStyle(
            backgroundColor: Colors.white,
            countryNameStyle: TextStyle(
              color: textColor,
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.w600,
            ),
            countryCodeStyle: TextStyle(
              color: const Color(0xFF6E7F9E),
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w600,
            ),
            listTileDivider: const Divider(
              thickness: 1,
              height: 1,
              color: Color(0xFFE6EEFB),
            ),
            searchFieldInputDecoration: InputDecoration(
              hintText: 'Search country',
              hintStyle: TextStyle(
                color: const Color(0xFF8B98B3),
                fontSize: compact ? 14 : 15,
                fontWeight: FontWeight.w500,
              ),
              suffixIcon: const Icon(Icons.search, color: Color(0xFF9AA8C2)),
              filled: true,
              fillColor: Colors.white,
              border: InputBorder.none,
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFD9E4F7)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF0F63FF), width: 1.4),
              ),
            ),
          ),
          decoration: InputDecoration(
            hintText: 'Numéro de téléphone',
            hintStyle: TextStyle(
              color: const Color(0xFF8B98B3),
              fontSize: compact ? 14 : 15,
              fontWeight: FontWeight.w500,
            ),
            prefixIconConstraints: const BoxConstraints(),
            border: InputBorder.none,
            counterText: '',
            contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 18,
              vertical: compact ? 15 : 18,
            ),
          ),
          dropdownIcon: Icon(
            LucideIcons.chevronDown,
            color: iconColor,
            size: compact ? 18 : 20,
          ),
          flagsButtonPadding: EdgeInsets.only(left: compact ? 14 : 16),
          showCountryFlag: true,
          onChanged: (phone) {
            _phoneComplete = phone.completeNumber;
            _phoneCountryIso = phone.countryISOCode;
            _phoneDialCode = phone.countryCode.replaceAll('+', '');
          },
          onCountryChanged: (country) {
            _phoneCountryIso = country.code;
            _phoneDialCode = country.dialCode;
            _phoneComplete =
                '+${country.dialCode}${_phoneController.text.trim()}';
          },
        ),
      ),
    );
  }
}
