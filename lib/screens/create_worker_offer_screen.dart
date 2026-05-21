import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/offers_service.dart';

const _kBlue = Color(0xFF0F63FF);
const _kText = Color(0xFF0F172A);
const _kMuted = Color(0xFF64748B);
const _kBorder = Color(0xFFE6EEFF);
const _kLightBlue = Color(0xFFEFF6FF);
const _kBg = Color(0xFFF7FAFF);

class CreateWorkerOfferScreen extends StatefulWidget {
  const CreateWorkerOfferScreen({
    super.key,
    required this.worker,
    required this.offersService,
  });

  final WorkerProfile worker;
  final OffersService offersService;

  @override
  State<CreateWorkerOfferScreen> createState() =>
      _CreateWorkerOfferScreenState();
}

class _CreateWorkerOfferScreenState extends State<CreateWorkerOfferScreen> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _regularPriceCtrl = TextEditingController();
  final _originalPriceCtrl = TextEditingController();
  final _promoPriceCtrl = TextEditingController();
  final _picker = ImagePicker();

  late final List<Map<String, dynamic>> _availabilitySlots;

  File? _selectedImage;
  late String _department;
  late String _specialty;
  bool _promotionEnabled = false;
  bool _availableNow = true;
  bool _proposedAllDay = false;
  String _proposedStartTime = '08:00 AM';
  String _proposedEndTime = '04:00 PM';
  bool _isPublishing = false;

  final List<String> _timeOptions = const <String>[
    '06:00 AM',
    '07:00 AM',
    '08:00 AM',
    '09:00 AM',
    '10:00 AM',
    '11:00 AM',
    '12:00 PM',
    '01:00 PM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
    '05:00 PM',
    '06:00 PM',
    '07:00 PM',
    '08:00 PM',
  ];

  @override
  void initState() {
    super.initState();
    _department = widget.worker.department;
    _specialty = widget.worker.specialties.isNotEmpty
        ? widget.worker.specialties.first
        : '';
    _availabilitySlots = widget.worker.availabilitySlots
        .map((slot) => Map<String, dynamic>.from(slot))
        .toList();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _regularPriceCtrl.dispose();
    _originalPriceCtrl.dispose();
    _promoPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final size = await file.length();
    if (size > 5 * 1024 * 1024) {
      _showSnack("JPG, PNG - Max. 5 Mo");
      return;
    }
    setState(() => _selectedImage = file);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _proposedStartTime : _proposedEndTime;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _PickerSheet(
          title: isStart ? 'Heure de début' : 'Heure de fin',
          options: _timeOptions,
          selected: current,
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isStart) {
        _proposedStartTime = selected;
      } else {
        _proposedEndTime = selected;
      }
    });
  }

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _showSnack('Veuillez saisir un titre.');
      return;
    }
    if (_descriptionCtrl.text.trim().isEmpty) {
      _showSnack('Veuillez ajouter une description.');
      return;
    }
    if (_department.trim().isEmpty) {
      _showSnack(
        'Votre profil est incomplet. Complétez votre profil avant de publier une offre.',
      );
      return;
    }
    if (_specialty.trim().isEmpty) {
      _showSnack('Veuillez sélectionner une spécialité.');
      return;
    }
    if (!widget.worker.specialties.contains(_specialty)) {
      _showSnack('Veuillez sélectionner une spécialité valide.');
      return;
    }

    final regularRate = double.tryParse(
      _regularPriceCtrl.text.replaceAll(',', '.'),
    );
    final originalRate = double.tryParse(
      _originalPriceCtrl.text.replaceAll(',', '.'),
    );
    final promoRate = double.tryParse(
      _promoPriceCtrl.text.replaceAll(',', '.'),
    );

    if (!_promotionEnabled && (regularRate == null || regularRate <= 0)) {
      _showSnack('Veuillez saisir un prix.');
      return;
    }
    if (_promotionEnabled) {
      if (originalRate == null ||
          originalRate <= 0 ||
          promoRate == null ||
          promoRate <= 0) {
        _showSnack('Veuillez saisir un prix.');
        return;
      }
      if (promoRate >= originalRate) {
        _showSnack('Le prix promo doit être inférieur au prix avant.');
        return;
      }
    }

    setState(() => _isPublishing = true);
    try {
      await widget.offersService.createWorkerOffer(
        worker: widget.worker,
        title: _titleCtrl.text,
        description: _descriptionCtrl.text,
        department: _department,
        specialty: _specialty,
        availabilitySlots: _availabilitySlots,
        proposedStartTime: _proposedStartTime,
        proposedEndTime: _proposedEndTime,
        proposedAllDay: _proposedAllDay,
        regularRate: regularRate,
        isPromotion: _promotionEnabled,
        originalRate: originalRate,
        promotionalRate: promoRate,
        isAvailableNow: _availableNow,
        imageFile: _selectedImage,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Offre publiée avec succès."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } on AddressRequiredException {
      _showSnack(
        "Assignez votre adresse dans votre profil avant de publier une offre.",
      );
    } catch (_) {
      _showSnack("Une erreur est survenue. Réessayez.");
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          children: [
            Row(
              children: [
                _headerButton(
                  LucideIcons.arrowLeft,
                  () => Navigator.pop(context),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Créer une offre',
                        style: TextStyle(
                          color: _kText,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Proposez votre service aux gestionnaires',
                        style: TextStyle(
                          color: _kMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _buildUploadArea(),
            const SizedBox(height: 18),
            _sectionCard(
              icon: LucideIcons.tag,
              title: "Titre de l'offre",
              child: TextField(
                controller: _titleCtrl,
                maxLength: 60,
                decoration: _inputDecoration("Ex. : Réparation fuite évier"),
              ),
            ),
            const SizedBox(height: 14),
            _sectionCard(
              icon: LucideIcons.fileText,
              title: 'Description',
              child: TextField(
                controller: _descriptionCtrl,
                maxLines: 5,
                maxLength: 300,
                decoration: _inputDecoration(
                  'Décrivez votre service, votre expérience et ce qui vous démarque...',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _sectionCard(
                    icon: LucideIcons.building2,
                    title: 'Département',
                    child: _readOnlyProfileField(
                      _department.isEmpty ? '—' : _department,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _sectionCard(
                    icon: LucideIcons.user,
                    title: 'Spécialité / rôle',
                    child: _readOnlyProfileField(
                      _specialty.isEmpty ? '—' : _specialty,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Ces informations proviennent de votre profil. Pour les modifier, rendez-vous dans Mon Profil.',
                style: TextStyle(
                  color: _kMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _sectionCard(
              icon: LucideIcons.clock3,
              title: 'Disponibilité',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_availabilitySlots.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _kLightBlue,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        "Vos disponibilités ne sont pas encore définies. Rendez-vous sur l'accueil et appuyez sur « Complétez votre compte » pour les configurer.",
                        style: TextStyle(
                          color: _kMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else ...[
                    ..._availabilitySlots.map(
                      (slot) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.calendarDays,
                              color: _kBlue,
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${slot['day'] ?? _weekdayLong((slot['weekday'] as num?)?.toInt() ?? 1)} · ${slot['label'] ?? ''}',
                                style: const TextStyle(
                                  color: _kText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Modifiable uniquement dans Mon Profil.',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _sectionCard(
              icon: LucideIcons.clock4,
              title: 'Créneau proposé',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _timeSelectField(
                          label: _proposedStartTime,
                          onTap: () => _pickTime(isStart: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _timeSelectField(
                          label: _proposedEndTime,
                          onTap: () => _pickTime(isStart: false),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    value: _proposedAllDay,
                    activeColor: _kBlue,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Toute la journée',
                      style: TextStyle(
                        color: _kMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _proposedAllDay = value == true);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _sectionCard(
                    icon: LucideIcons.badgeDollarSign,
                    title: 'Prix proposé',
                    child: TextField(
                      controller: _regularPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _inputDecoration(
                        'Ex. : 20',
                      ).copyWith(prefixText: r'$ ', suffixText: '/h'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _promotionCard()),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.zap, color: _kBlue),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Disponible immédiatement',
                          style: TextStyle(
                            color: _kText,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Votre offre apparaîtra comme disponible tout de suite.',
                          style: TextStyle(
                            color: _kMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _availableNow,
                    activeThumbColor: _kBlue,
                    onChanged: (value) => setState(() => _availableNow = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 58,
              child: ElevatedButton.icon(
                onPressed: _isPublishing ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: _isPublishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.send, size: 18),
                label: Text(
                  _isPublishing ? 'Publication...' : "Publier l'offre",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promotionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _promotionEnabled ? _kBlue : _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.badgePercent, color: _kBlue, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Promotion',
                  style: TextStyle(
                    color: _kBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _promotionEnabled,
                  activeThumbColor: _kBlue,
                  onChanged: (value) =>
                      setState(() => _promotionEnabled = value),
                ),
              ),
            ],
          ),
          if (_promotionEnabled) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _originalPriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inputDecoration('Ex. : 25').copyWith(
                labelText: 'Prix avant',
                prefixText: r'$ ',
                suffixText: '/h',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _promoPriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inputDecoration('Ex. : 20').copyWith(
                labelText: 'Prix promo',
                prefixText: r'$ ',
                suffixText: '/h',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadArea() {
    return InkWell(
      onTap: _pickImage,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _kBlue.withValues(alpha: 0.55),
            style: BorderStyle.solid,
          ),
        ),
        child: DottedBorderBox(
          child: _selectedImage == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(LucideIcons.upload, color: _kBlue, size: 56),
                    SizedBox(height: 16),
                    Text(
                      'Ajouter une photo',
                      style: TextStyle(
                        color: _kBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Montrez votre travail ou votre service (facultatif)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'JPG, PNG - Max. 5 Mo',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Row(
                        children: [
                          _imageAction('Changer', _pickImage),
                          const SizedBox(width: 8),
                          _imageAction(
                            'Retirer',
                            () => setState(() => _selectedImage = null),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _imageAction(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _kText,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _kBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _timeSelectField({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _kText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(LucideIcons.chevronDown, color: _kMuted, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyProfileField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _kLightBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _kBlue,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(LucideIcons.lock, color: _kMuted, size: 14),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Icon(icon, color: _kText, size: 22),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _kMuted),
      filled: true,
      fillColor: Colors.white,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _kBlue, width: 1.4),
      ),
    );
  }

  static String _weekdayLong(int weekday) {
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

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD7E4FF),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: _kText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [...options.map(
            (option) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => Navigator.pop(context, option),
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: option == selected
                        ? _kLightBlue
                        : const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: option == selected ? _kBlue : _kBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option,
                          style: TextStyle(
                            color: option == selected ? _kBlue : _kText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (option == selected)
                        const Icon(LucideIcons.check, color: _kBlue, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
          ),
        ),
        ],
      ),
    );
  }
}

class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedBorderPainter(),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kBlue.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dash = 8.0;
    const gap = 6.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(24),
        ),
      );
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
