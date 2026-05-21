import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../screens/auth_screen.dart';

class DeviceLockGate extends StatefulWidget {
  final Widget child;

  const DeviceLockGate({super.key, required this.child});

  @override
  State<DeviceLockGate> createState() => _DeviceLockGateState();
}

class _DeviceLockGateState extends State<DeviceLockGate> {
  final LocalAuthentication _auth = LocalAuthentication();

  bool _unlocked = false;
  bool _checkingAvailability = true;
  bool _authenticating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareGate());
  }

  Future<void> _prepareGate() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!mounted) return;

      setState(() {
        _checkingAvailability = false;
        _unlocked = false;
        _message = supported
            ? null
            : "Aucun verrouillage d'appareil detecte. Votre session reste memorisee sur cet appareil.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingAvailability = false;
        _unlocked = true;
      });
    }
  }

  Future<void> _closeAccount() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _authenticate() async {
    if (_authenticating || _unlocked || _checkingAvailability) return;

    setState(() {
      _authenticating = true;
      _message = null;
    });

    try {
      final supported = await _auth.isDeviceSupported();
      if (!mounted) return;

      if (!supported) {
        setState(() {
          _authenticating = false;
          _unlocked = true;
        });
        return;
      }

      final ok = await _auth.authenticate(
        localizedReason:
            'Deverrouillez votre appareil pour retrouver votre session',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;
      setState(() {
        _unlocked = ok;
        _message = ok
            ? null
            : 'Verification annulee. Touchez Deverrouiller pour reessayer.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            "Impossible d'ouvrir le verrouillage de l'appareil pour le moment. Reessayez.";
      });
    } finally {
      if (mounted) {
        setState(() => _authenticating = false);
      }
    }
  }

  Widget _securityBadge() {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F63FF), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220F63FF),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(LucideIcons.shieldCheck, color: Colors.white, size: 48),
    );
  }

  Widget _unlockButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF0F63FF)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x260F63FF),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _authenticate,
            borderRadius: BorderRadius.circular(20),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.lock, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text(
                  'Deverrouiller',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contentCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 56),
      padding: const EdgeInsets.fromLTRB(22, 86, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: const Color(0xFFE6EEFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160F63FF),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Compte verrouille',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _message ??
                "Deverrouillez avec le code, l'empreinte ou Face ID de cet appareil pour retrouver votre session.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14.5,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE6EEFF)),
            ),
            child: const Row(
              children: [
                Icon(
                  LucideIcons.smartphone,
                  color: Color(0xFF0F63FF),
                  size: 18,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Votre compte reste memorise sur cet appareil jusqu'a ce que vous vous deconnectiez.",
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_checkingAvailability || _authenticating)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Color(0xFF0F63FF),
                strokeWidth: 2.6,
              ),
            )
          else ...[
            _unlockButton(),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _closeAccount,
              child: const Text(
                'Utiliser un autre compte',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: 320,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF0F63FF),
                      Color(0xFF0047D8),
                      Color(0xFF0036B5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              const Expanded(child: ColoredBox(color: Color(0xFFF6FAFF))),
            ],
          ),
          Positioned(
            left: -30,
            top: 90,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: -24,
            top: 40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                  child: Column(
                    children: [
                      const Spacer(),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 420,
                          maxHeight: constraints.maxHeight - 28,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.topCenter,
                          children: [
                            _contentCard(),
                            Positioned(top: 0, child: _securityBadge()),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
