import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../models/manager_offer.dart';
import '../services/messages_repository.dart';
import '../services/offers_service.dart';
import 'chat_detail_screen.dart';

const _kBlue = Color(0xFF0F63FF);
const _kBg = Color(0xFFF7FAFF);
const _kText = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE6EEFF);
const _kLightBlue = Color(0xFFEFF6FF);
const _kSuccess = Color(0xFF16A34A);
const _kWarning = Color(0xFFF59E0B);

class OfferDetailScreen extends StatefulWidget {
  const OfferDetailScreen({
    super.key,
    required this.offer,
    required this.worker,
    required this.offersService,
    this.alreadyApplied = false,
  });

  final ManagerOffer offer;
  final WorkerProfile worker;
  final OffersService offersService;
  final bool alreadyApplied;

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  final MessagesRepository _messagesRepository = MessagesRepository();
  bool _applying = false;
  bool _applied = false;
  bool _openingChat = false;

  @override
  void initState() {
    super.initState();
    _applied = widget.alreadyApplied;
  }

  Future<void> _apply() async {
    if (_applied || _applying) return;
    setState(() => _applying = true);
    try {
      await widget.offersService.applyToOffer(
        offer: widget.offer,
        worker: widget.worker,
      );
      if (mounted) {
        setState(() {
          _applied = true;
          _applying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Candidature envoyée avec succès !'),
            backgroundColor: _kSuccess,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on AlreadyAppliedException {
      if (mounted) {
        setState(() {
          _applied = true;
          _applying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vous avez déjà postulé à cette offre.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _contactManager() async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    try {
      final conversationId = await _messagesRepository
          .ensureWorkerManagerConversation(
            managerId: widget.offer.createdByManagerId,
            managerName: widget.offer.createdByManagerName,
            managerSubtitle: widget.offer.specialty.isNotEmpty
                ? widget.offer.specialty
                : 'Gestionnaire',
            managerPhotoUrl: widget.offer.managerPhotoUrl,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(conversationId: conversationId),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conversation indisponible : $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Color _urgencyColor() {
    switch (widget.offer.urgency) {
      case OfferUrgency.veryUrgent:
      case OfferUrgency.urgent:
        return Colors.red.shade600;
      case OfferUrgency.high:
        return _kWarning;
      case OfferUrgency.normal:
        return _kSuccess;
    }
  }

  String _urgencyLabel() {
    switch (widget.offer.urgency) {
      case OfferUrgency.veryUrgent:
        return 'Très urgent';
      case OfferUrgency.urgent:
        return 'Urgent';
      case OfferUrgency.high:
        return 'Élevée';
      case OfferUrgency.normal:
        return 'Normale';
    }
  }

  Widget _avatar({double size = 56}) {
    final offer = widget.offer;
    if (offer.managerPhotoUrl?.isNotEmpty == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: Image.network(
          offer.managerPhotoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: _kLightBlue),
        ),
      );
    }
    if (offer.condoImageUrl?.isNotEmpty == true) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: Image.network(
          offer.condoImageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: _kLightBlue),
        ),
      );
    }
    final base64 = offer.managerPhotoBase64?.isNotEmpty == true
        ? offer.managerPhotoBase64
        : (offer.condoImageBase64?.isNotEmpty == true
              ? offer.condoImageBase64
              : null);

    if (base64 != null) {
      try {
        final bytes = base64Decode(base64);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {}
    }

    final initial = offer.condoName.isNotEmpty
        ? offer.condoName[0].toUpperCase()
        : null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _kLightBlue,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: initial != null
          ? Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: _kBlue,
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Icon(LucideIcons.building2, color: _kBlue, size: size * 0.44),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final budgetFormatted = NumberFormat(
      '#,##0',
      'fr_FR',
    ).format(offer.budgetAmount.toInt());
    final urgencyColor = _urgencyColor();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: _kText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Détail de l'offre",
          style: TextStyle(
            color: _kText,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kBorder),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A0F63FF),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _avatar(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer.title,
                            style: const TextStyle(
                              color: _kText,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            offer.condoName,
                            style: const TextStyle(
                              color: _kBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (offer.condoAddress?.isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              offer.condoAddress!,
                              style: const TextStyle(
                                color: _kMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: urgencyColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.flame, color: urgencyColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _urgencyLabel(),
                        style: TextStyle(
                          color: urgencyColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Info grid
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Détails de la mission',
                  style: TextStyle(
                    color: _kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                _InfoRow(
                  icon: LucideIcons.calendarDays,
                  label: 'Date',
                  value: offer.requestedDate,
                ),
                _InfoRow(
                  icon: LucideIcons.clock3,
                  label: 'Heure',
                  value: offer.requestedTime,
                ),
                _InfoRow(
                  icon: LucideIcons.timer,
                  label: 'Durée estimée',
                  value: offer.estimatedDuration,
                ),
                _InfoRow(
                  icon: LucideIcons.briefcase,
                  label: 'Département',
                  value: offer.department,
                ),
                _InfoRow(
                  icon: LucideIcons.star,
                  label: 'Spécialité',
                  value: offer.specialty,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Description
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Description',
                  style: TextStyle(
                    color: _kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  offer.description,
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 14,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Budget card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _kLightBlue,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    LucideIcons.wallet,
                    color: _kBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$budgetFormatted ${offer.budgetCurrency}',
                        style: const TextStyle(
                          color: _kText,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        offer.isNegotiable ? 'Négociable' : 'Non négociable',
                        style: TextStyle(
                          color: offer.isNegotiable ? _kSuccess : _kMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _openingChat ? null : _contactManager,
                    icon: _openingChat
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.messageCircle, size: 18),
                    label: const Text('Contacter'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kBlue,
                      side: const BorderSide(color: _kBlue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_applied || _applying) ? null : _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _applied ? _kMuted : _kBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _applying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _applied ? 'Candidature envoyée' : 'Postuler',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: _kBlue, size: 16),
          const SizedBox(width: 10),
          Text(
            '$label : ',
            style: const TextStyle(
              color: _kMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '—',
              style: const TextStyle(
                color: _kText,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
