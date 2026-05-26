import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _kPrivacyBlue = Color(0xFF0F63FF);
const _kPrivacyDeepBlue = Color(0xFF2563EB);
const _kPrivacyBg = Color(0xFFF7FAFF);
const _kPrivacyText = Color(0xFF0F172A);
const _kPrivacyBody = Color(0xFF475569);
const _kPrivacyBorder = Color(0xFFE2E8F0);
const _kPrivacyLightBlue = Color(0xFFEFF6FF);

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPrivacyBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _kPrivacyText,
        title: const Text(
          'Politique de confidentialite',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        children: const [
          _PrivacyHeroCard(),
          SizedBox(height: 14),
          _PrivacySectionCard(
            icon: LucideIcons.database,
            title: 'Donnees collectees',
            body:
                'StayFix Job peut collecter les informations de compte que vous saisissez, votre photo de profil, votre CV, vos messages de travail, vos medias partages, votre position pour le pointage et certaines donnees techniques necessaires au fonctionnement de l application.',
          ),
          SizedBox(height: 14),
          _PrivacySectionCard(
            icon: LucideIcons.scanSearch,
            title: 'Pourquoi ces donnees sont utilisees',
            body:
                'Ces donnees sont utilisees pour creer et gerer votre profil, afficher vos informations aux employeurs ou managers concernes, permettre les conversations de travail, verifier votre presence sur le lieu de travail avant le pointage, envoyer des notifications et securiser votre acces a la plateforme.',
          ),
          SizedBox(height: 14),
          _PrivacySectionCard(
            icon: LucideIcons.share2,
            title: 'Partage des donnees',
            body:
                'Vos donnees ne sont partagees qu avec les services necessaires au fonctionnement de StayFix Job, comme Firebase pour l authentification, la base de donnees et les notifications, ainsi qu avec les responsables ou employeurs qui doivent consulter votre profil ou vos echanges professionnels. StayFix Job ne vend pas vos donnees personnelles.',
          ),
          SizedBox(height: 14),
          _PrivacySectionCard(
            icon: LucideIcons.mapPinned,
            title: 'Permissions de l appareil',
            body:
                'Camera: photo de profil, photos et videos dans les conversations. Microphone: messages vocaux et videos avec son. Phototheque: selection d images et de videos existantes. Localisation: verification de zone de travail et aide au choix d adresse.',
          ),
          SizedBox(height: 14),
          _PrivacySectionCard(
            icon: LucideIcons.shieldCheck,
            title: 'Conservation et suppression',
            body:
                'Vos donnees sont conservees tant que votre compte est actif ou tant qu elles sont necessaires a la fourniture du service. Vous pouvez demander la suppression de votre compte depuis les reglages de l application. La suppression retire votre profil actif de l application et demande aussi la suppression de votre compte d authentification.',
          ),
          SizedBox(height: 14),
          _PrivacySectionCard(
            icon: LucideIcons.settings2,
            title: 'Vos choix',
            body:
                'Vous pouvez refuser certaines permissions, mais certaines fonctions dependront alors de solutions manuelles ou seront limitees. Vous pouvez egalement retirer votre consentement pour certaines utilisations en cessant d utiliser la fonction correspondante ou en supprimant votre compte depuis l application.',
          ),
          SizedBox(height: 14),
          _PrivacySectionCard(
            icon: LucideIcons.mail,
            title: 'Support et demandes',
            body:
                'Pour toute question sur vos donnees, utilisez les coordonnees de support fournies sur la fiche App Store de StayFix Job ou contactez votre administrateur ou manager StayFix habituel.',
          ),
        ],
      ),
    );
  }
}

class _PrivacyHeroCard extends StatelessWidget {
  const _PrivacyHeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPrivacyBlue, _kPrivacyDeepBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220F63FF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.shieldCheck, color: Colors.white, size: 28),
          SizedBox(height: 14),
          Text(
            'Vos donnees doivent rester comprehensibles, utiles et protegees.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Cette page resume les informations utilisees par StayFix Job, leur finalite et les options disponibles pour les utilisateurs.',
            style: TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySectionCard extends StatelessWidget {
  const _PrivacySectionCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kPrivacyBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: _kPrivacyLightBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _kPrivacyBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _kPrivacyText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: _kPrivacyBody,
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
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
