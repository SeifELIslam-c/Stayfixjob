import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons_flutter.dart';

import '../services/google_places_service.dart';
import '../widgets/address_picker.dart';
import 'home_screen.dart';

const kClockBlue = Color(0xFF0F63FF);
const kClockDeepBlue = Color(0xFF2563EB);
const kClockDarkBlue = Color(0xFF0057E7);
const kClockPageBg = Color(0xFFF7FAFF);
const kClockText = Color(0xFF0F172A);
const kClockMuted = Color(0xFF64748B);
const kClockBorder = Color(0xFFE2E8F0);
const kClockLightBlue = Color(0xFFEFF6FF);
const kClockSuccess = Color(0xFF22C55E);
const kClockDanger = Color(0xFFEF4444);
const kClockWarning = Color(0xFFF97316);

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen>
    with SingleTickerProviderStateMixin {
  static const double _defaultZoneRadiusMeters = 15;
  static const LatLng _defaultMapCenter = LatLng(36.7538, 3.0588);

  late final Timer _timer;
  late final AnimationController _zonePulseController;
  DateTime _currentTime = DateTime.now();
  StreamSubscription<Position>? _positionSubscription;
  GoogleMapController? _mapController;

  bool _isLoading = true;
  bool _isPunchSaving = false;
  bool _isLocationRefreshing = false;
  bool _isWorkAddressSaving = false;
  bool _isPunchedIn = false;
  bool _locationServiceEnabled = false;
  bool _locationPermissionGranted = false;

  DateTime? _punchInTime;
  Position? _currentPosition;
  double? _distanceToWorkLocationMeters;
  List<Map<String, dynamic>> _activities = <Map<String, dynamic>>[];
  Timer? _centerAlertTimer;
  String? _centerAlertMessage;
  bool _centerAlertSuccess = true;
  bool _centerAlertVisible = false;

  String _workAddress = '';
  String _workPlaceId = '';
  String _workPlaceName = '';
  double? _workLatitude;
  double? _workLongitude;
  double _zoneRadiusMeters = _defaultZoneRadiusMeters;

  void _applyWorkLocation(GooglePlaceDetails details) {
    _workAddress = details.formattedAddress;
    _workPlaceId = details.placeId;
    _workPlaceName = details.name;
    _workLatitude = details.latitude;
    _workLongitude = details.longitude;
    _zoneRadiusMeters = _defaultZoneRadiusMeters;
    if (_currentPosition != null) {
      _distanceToWorkLocationMeters = _calculateDistanceToWorkLocation(
        _currentPosition!,
      );
    }
  }

  Future<void> _persistWorkLocation(GooglePlaceDetails details) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid)
        .update({
          'workDepartmentAddress': details.formattedAddress,
          'workDepartmentPlaceId': details.placeId,
          'workDepartmentPlaceName': details.name,
          'workDepartmentLat': details.latitude,
          'workDepartmentLng': details.longitude,
          'workDepartmentZoneRadiusMeters': _zoneRadiusMeters,
        });
  }

  @override
  void initState() {
    super.initState();
    _zonePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    initializeDateFormatting('fr_FR', null).then((_) => _loadClockState());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _positionSubscription?.cancel();
    _centerAlertTimer?.cancel();
    _zonePulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadClockState() async {
    try {
      await _loadProfileData();
      await _configureLocationTracking(requestPermission: true);
      await _animateCameraToRelevantCenter();
    } catch (e) {
      debugPrint('Erreur chargement horloge: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(user.uid)
        .get();
    if (!doc.exists || !mounted) return;

    final data = doc.data() ?? <String, dynamic>{};
    final punchesRaw = data['punches'];

    final loadedActivities = punchesRaw is List
        ? punchesRaw.whereType<Map>().map((raw) {
            final map = Map<String, dynamic>.from(raw);
            final timestamp = map['time'];
            return <String, dynamic>{
              'typeCode': _normalizePunchType(map['typeCode'] ?? map['type']),
              'time': timestamp is Timestamp
                  ? timestamp.toDate()
                  : DateTime.now(),
              'latitude': (map['latitude'] as num?)?.toDouble(),
              'longitude': (map['longitude'] as num?)?.toDouble(),
              'distanceMeters': (map['distanceMeters'] as num?)?.toDouble(),
              'workAddress': map['workAddress'] as String? ?? '',
            };
          }).toList()
        : <Map<String, dynamic>>[];

    loadedActivities.sort(
      (a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime),
    );

    final latestType = loadedActivities.isEmpty
        ? ''
        : loadedActivities.first['typeCode'] as String? ?? '';

    setState(() {
      _activities = loadedActivities;
      _workAddress =
          data['workDepartmentAddress'] as String? ??
          data['jobAddress'] as String? ??
          '';
      _workPlaceId = data['workDepartmentPlaceId'] as String? ?? '';
      _workPlaceName = data['workDepartmentPlaceName'] as String? ?? '';
      _workLatitude = (data['workDepartmentLat'] as num?)?.toDouble();
      _workLongitude = (data['workDepartmentLng'] as num?)?.toDouble();
      _zoneRadiusMeters = _defaultZoneRadiusMeters;
      _isPunchedIn = latestType == 'arrivee';
      _punchInTime = _isPunchedIn
          ? loadedActivities.first['time'] as DateTime
          : null;
    });
  }

  String _normalizePunchType(dynamic rawType) {
    final value = (rawType ?? '').toString().toLowerCase();
    if (value.contains('arriv') || value == 'arrivee') return 'arrivee';
    if (value.contains('depart')) return 'depart';
    return '';
  }

  Future<void> _configureLocationTracking({
    required bool requestPermission,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    LocationPermission permission = await Geolocator.checkPermission();

    if (requestPermission &&
        permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (!mounted) return;
    setState(() {
      _locationServiceEnabled = serviceEnabled;
      _locationPermissionGranted = granted;
    });

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (!serviceEnabled || !granted) {
      if (mounted) {
        setState(() {
          _currentPosition = null;
          _distanceToWorkLocationMeters = null;
        });
      }
      return;
    }

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _updateCurrentPosition(current);
    } catch (e) {
      debugPrint('Erreur position actuelle: $e');
    }

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 8,
          ),
        ).listen(
          _updateCurrentPosition,
          onError: (Object error) {
            debugPrint('Erreur suivi localisation: $error');
          },
        );
  }

  void _updateCurrentPosition(Position position) {
    final nextDistance = _calculateDistanceToWorkLocation(position);
    if (!mounted) return;
    setState(() {
      _currentPosition = position;
      _distanceToWorkLocationMeters = nextDistance;
    });
  }

  LatLng get _workLatLng => LatLng(
    _workLatitude ?? _defaultMapCenter.latitude,
    _workLongitude ?? _defaultMapCenter.longitude,
  );

  LatLng get _cameraCenter {
    if (_workLatitude != null && _workLongitude != null) {
      return LatLng(_workLatitude!, _workLongitude!);
    }
    if (_currentPosition != null) {
      return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    return _defaultMapCenter;
  }

  Set<Marker> _buildMapMarkers() {
    final markers = <Marker>{};

    if (_workLatitude != null && _workLongitude != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('work_zone'),
          position: _workLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(
            title: _workPlaceName.isNotEmpty ? _workPlaceName : 'Departement',
            snippet: _displayWorkAddress(),
          ),
        ),
      );
    }

    return markers;
  }

  Set<Circle> _buildMapCircles() {
    if (_workLatitude == null || _workLongitude == null) {
      return const <Circle>{};
    }

    final pulse = Curves.easeInOut.transform(_zonePulseController.value);
    final pulseRadius = _zoneRadiusMeters * (1.0 + (0.18 * pulse));
    final pulseAlpha = (22 + (20 * pulse)).round().clamp(0, 255);

    return <Circle>{
      Circle(
        circleId: const CircleId('work_zone_base'),
        center: _workLatLng,
        radius: _zoneRadiusMeters,
        fillColor: const Color(0x221D9BF0),
        strokeColor: const Color(0x662D8CFF),
        strokeWidth: 2,
      ),
      Circle(
        circleId: const CircleId('work_zone_pulse'),
        center: _workLatLng,
        radius: pulseRadius,
        fillColor: Color.fromARGB(pulseAlpha, 61, 156, 240),
        strokeColor: Color.fromARGB(
          (70 + (35 * pulse)).round().clamp(0, 255),
          61,
          156,
          240,
        ),
        strokeWidth: 2,
      ),
    };
  }

  Future<void> _animateCameraToRelevantCenter() async {
    final controller = _mapController;
    if (controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _cameraCenter,
          zoom: _workLatitude != null ? 16.6 : 14.2,
        ),
      ),
    );
  }

  double? _calculateDistanceToWorkLocation(Position position) {
    if (_workLatitude == null || _workLongitude == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _workLatitude!,
      _workLongitude!,
    );
  }

  bool get _hasWorkLocation =>
      _workAddress.trim().isNotEmpty &&
      _workLatitude != null &&
      _workLongitude != null;

  bool get _isInsideWorkZone =>
      _distanceToWorkLocationMeters != null &&
      _distanceToWorkLocationMeters! <= _zoneRadiusMeters;

  String _formattedMainTime() {
    return DateFormat(
      'h mm',
      'fr_FR',
    ).format(_currentTime).replaceAll(' ', ' h ');
  }

  String _amPm() => DateFormat('a').format(_currentTime).toLowerCase();

  String _displayWorkAddress() =>
      _workAddress.trim().isEmpty ? 'Adresse non definie' : _workAddress;

  String _zoneStatusTitle() {
    if (!_hasWorkLocation) return 'Configurez votre departement de travail';
    if (!_locationServiceEnabled) return 'Activez la localisation';
    if (!_locationPermissionGranted) return 'Autorisez la localisation';
    if (_currentPosition == null) return 'Recherche de votre position';
    if (_isInsideWorkZone) return 'Vous etes dans la zone de travail';
    return 'Vous etes hors zone';
  }

  Color _zoneAccentColor() {
    if (_isInsideWorkZone) return kClockSuccess;
    if (!_hasWorkLocation ||
        !_locationServiceEnabled ||
        !_locationPermissionGranted) {
      return kClockWarning;
    }
    return kClockDanger;
  }

  void _showCenterAlert(String message, {bool success = true}) {
    _centerAlertTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _centerAlertMessage = message;
      _centerAlertSuccess = success;
      _centerAlertVisible = true;
    });

    _centerAlertTimer = Timer(const Duration(milliseconds: 1900), () async {
      if (!mounted) return;
      setState(() => _centerAlertVisible = false);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted) return;
      setState(() => _centerAlertMessage = null);
    });
  }

  Future<void> _openWorkAddressPicker() async {
    final result = await showAddressPicker(
      context: context,
      initialAddress: _workAddress,
      initialLatitude: _workLatitude,
      initialLongitude: _workLongitude,
      presentation: AddressPickerPresentation.fullscreen,
      title: 'Modifier adresse du poste',
      confirmationText:
          "Confirmez cette position pour enregistrer l'adresse de votre poste actuel.",
      confirmLabel: "Confirmer l'adresse",
    );

    if (result == null || !mounted) return;
    final details = GooglePlaceDetails(
      placeId: result.placeId ?? '',
      name: result.label?.trim().isNotEmpty == true
          ? result.label!.trim()
          : (_workPlaceName.trim().isNotEmpty
                ? _workPlaceName.trim()
                : 'Poste actuel'),
      formattedAddress: result.address.trim(),
      latitude: result.latitude,
      longitude: result.longitude,
    );

    setState(() => _isWorkAddressSaving = true);
    try {
      setState(() => _applyWorkLocation(details));
      unawaited(_animateCameraToRelevantCenter());
      await _persistWorkLocation(details);
      _showCenterAlert('Adresse du departement mise a jour.');
    } catch (_) {
      if (!mounted) return;
      _showCenterAlert(
        "Erreur lors de l'enregistrement de l'adresse.",
        success: false,
      );
    } finally {
      if (mounted) setState(() => _isWorkAddressSaving = false);
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => _isLocationRefreshing = true);
    try {
      await _configureLocationTracking(requestPermission: true);
      await _animateCameraToRelevantCenter();
    } finally {
      if (mounted) setState(() => _isLocationRefreshing = false);
    }
  }

  Future<void> _handleMapTap(LatLng point) async {
    if (_isWorkAddressSaving) return;

    setState(() => _isWorkAddressSaving = true);
    try {
      final details = await GooglePlacesService.reverseGeocode(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted) return;
      setState(() => _applyWorkLocation(details));
      unawaited(_animateCameraToRelevantCenter());
      await _persistWorkLocation(details);
      _showCenterAlert('Point de travail deplace sur la carte.');
    } catch (_) {
      _showCenterAlert(
        "Impossible de recuperer l'adresse depuis la carte.",
        success: false,
      );
    } finally {
      if (mounted) setState(() => _isWorkAddressSaving = false);
    }
  }

  Future<void> _handlePunch() async {
    if (_isPunchSaving) return;

    if (!_hasWorkLocation) {
      _showCenterAlert(
        'Ajoutez d abord votre adresse de travail.',
        success: false,
      );
      return;
    }

    if (!_locationServiceEnabled || !_locationPermissionGranted) {
      _showCenterAlert(
        'La localisation doit etre activee pour pointer.',
        success: false,
      );
      return;
    }

    if (_currentPosition == null) {
      _showCenterAlert(
        'Position en cours de recuperation. Reessayez dans un instant.',
        success: false,
      );
      return;
    }

    if (!_isInsideWorkZone) {
      final distance = _distanceToWorkLocationMeters?.round();
      _showCenterAlert(
        distance == null
            ? 'Vous devez etre dans la zone de travail pour pointer.'
            : 'Vous devez etre dans la zone. Distance actuelle: $distance m.',
        success: false,
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final punchTime = DateTime.now();
    final typeCode = _isPunchedIn ? 'depart' : 'arrivee';

    final payload = <String, dynamic>{
      'typeCode': typeCode,
      'type': typeCode,
      'time': Timestamp.fromDate(punchTime),
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'distanceMeters': _distanceToWorkLocationMeters?.round(),
      'workAddress': _workAddress,
      'workDepartmentPlaceId': _workPlaceId,
      'zoneRadiusMeters': _zoneRadiusMeters.round(),
    };

    setState(() => _isPunchSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .update({
            'punches': FieldValue.arrayUnion([payload]),
          });

      final localPunch = <String, dynamic>{
        'typeCode': typeCode,
        'time': punchTime,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'distanceMeters': _distanceToWorkLocationMeters,
        'workAddress': _workAddress,
      };

      setState(() {
        _activities.insert(0, localPunch);
        if (typeCode == 'arrivee') {
          _isPunchedIn = true;
          _punchInTime = punchTime;
        } else {
          _isPunchedIn = false;
          _punchInTime = null;
        }
      });
      _showCenterAlert(
        typeCode == 'arrivee'
            ? "Pointage d'arrivee enregistre"
            : 'Pointage de depart enregistre',
      );
    } catch (e) {
      if (!mounted) return;
      _showCenterAlert('Erreur lors du pointage.', success: false);
    } finally {
      if (mounted) setState(() => _isPunchSaving = false);
    }
  }

  void _handleBack() {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
      (route) => false,
    );
  }

  BoxDecoration _whiteCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: kClockBorder),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          _heroButton(icon: LucideIcons.arrowLeft, onTap: _handleBack),
          const Expanded(
            child: Text(
              'Horloge',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _heroButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _floatingChip({
    required IconData icon,
    required String label,
    required String value,
    Color? accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(icon, color: accent ?? kClockBlue, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kClockMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kClockText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildFloatingStatusLayer() {
    final accent = _zoneAccentColor();
    final distanceText = _distanceToWorkLocationMeters == null
        ? '--'
        : '${_distanceToWorkLocationMeters!.round()} m';

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 84, 16, 170),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _floatingChip(
                    icon: LucideIcons.clock3,
                    label: 'Heure',
                    value: '${_formattedMainTime()} ${_amPm()}',
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      _cornerActionButton(
                        icon: LucideIcons.history,
                        tooltip: 'Voir les pointages',
                        onTap: _showPunchHistorySheet,
                      ),
                      const SizedBox(height: 10),
                      _cornerActionButton(
                        icon: LucideIcons.locateFixed,
                        tooltip: 'Actualiser la position',
                        onTap: _isLocationRefreshing ? null : _refreshLocation,
                        loading: _isLocationRefreshing,
                      ),
                      const SizedBox(height: 10),
                      _cornerActionButton(
                        icon: LucideIcons.pencil,
                        tooltip: "Modifier l'adresse",
                        onTap: _isWorkAddressSaving
                            ? null
                            : _openWorkAddressPicker,
                        loading: _isWorkAddressSaving,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _floatingChip(
                icon: _isInsideWorkZone
                    ? LucideIcons.shieldCheck
                    : LucideIcons.mapPinOff,
                label: _zoneStatusTitle(),
                value: _hasWorkLocation
                    ? '${_zoneRadiusMeters.round()} m zone  •  $distanceText'
                    : 'Adresse requise',
                accent: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingStatusLayerCompact() {
    final accent = _zoneAccentColor();
    final distanceText = _distanceToWorkLocationMeters == null
        ? '--'
        : '${_distanceToWorkLocationMeters!.round()} m';

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            Positioned(
              left: 16,
              top: 84,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 145),
                child: _floatingChip(
                  icon: LucideIcons.clock3,
                  label: 'Heure',
                  value: '${_formattedMainTime()} ${_amPm()}',
                ),
              ),
            ),
            Positioned(
              top: 84,
              right: 16,
              child: Column(
                children: [
                  _cornerActionButton(
                    icon: LucideIcons.history,
                    tooltip: 'Voir les pointages',
                    onTap: _showPunchHistorySheet,
                  ),
                  const SizedBox(height: 10),
                  _cornerActionButton(
                    icon: LucideIcons.locateFixed,
                    tooltip: 'Actualiser la position',
                    onTap: _isLocationRefreshing ? null : _refreshLocation,
                    loading: _isLocationRefreshing,
                  ),
                  const SizedBox(height: 10),
                  _cornerActionButton(
                    icon: LucideIcons.pencil,
                    tooltip: "Modifier l'adresse",
                    onTap: _isWorkAddressSaving ? null : _openWorkAddressPicker,
                    loading: _isWorkAddressSaving,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              bottom: 176,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 215),
                child: _floatingChip(
                  icon: _isInsideWorkZone
                      ? LucideIcons.shieldCheck
                      : LucideIcons.mapPinOff,
                  label: _zoneStatusTitle(),
                  value: _hasWorkLocation
                      ? '${_zoneRadiusMeters.round()} m zone  -  $distanceText'
                      : 'Adresse requise',
                  accent: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cornerActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: loading
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                : Icon(icon, color: kClockBlue, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildZoneMapCard() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _zonePulseController,
        builder: (context, _) {
          return GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _cameraCenter,
              zoom: _workLatitude != null ? 16.6 : 14.2,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              unawaited(_animateCameraToRelevantCenter());
            },
            myLocationEnabled: _currentPosition != null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: false,
            buildingsEnabled: true,
            circles: _buildMapCircles(),
            markers: _buildMapMarkers(),
            onTap: _handleMapTap,
          );
        },
      ),
    );
  }

  Widget _buildPunchCard() {
    final canPunch =
        _hasWorkLocation &&
        _locationServiceEnabled &&
        _locationPermissionGranted &&
        _currentPosition != null &&
        _isInsideWorkZone &&
        !_isPunchSaving;

    final gradientColors = _isPunchedIn
        ? const [Color(0xFFF97316), kClockDanger]
        : const [kClockBlue, kClockDeepBlue];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: kClockLightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPunchedIn ? LucideIcons.logOut : LucideIcons.logIn,
                  color: _isPunchedIn ? kClockWarning : kClockBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isPunchedIn
                          ? 'Pointage actif sur votre quart'
                          : 'Pret pour votre pointage',
                      style: const TextStyle(
                        color: kClockText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isPunchedIn && _punchInTime != null
                          ? 'Arrivee enregistree a ${DateFormat('HH:mm').format(_punchInTime!)}'
                          : 'Le pointage sera autorise seulement dans la zone de travail.',
                      style: const TextStyle(
                        color: kClockMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x240F63FF),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canPunch ? _handlePunch : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPunchedIn ? LucideIcons.logOut : LucideIcons.logIn,
                          color: _isPunchedIn ? kClockDanger : kClockBlue,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Center(
                          child: _isPunchSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.3,
                                  ),
                                )
                              : Text(
                                  _isPunchedIn
                                      ? 'POINTAGE DE DEPART'
                                      : "POINTAGE D'ARRIVEE",
                                  style: TextStyle(
                                    color: canPunch
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.72),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(Map<String, dynamic> act, {bool showDivider = true}) {
    final typeCode = act['typeCode'] as String? ?? '';
    final isArrival = typeCode == 'arrivee';
    final accent = isArrival ? kClockSuccess : kClockDanger;
    final bg = isArrival ? const Color(0xFFEFF8F1) : const Color(0xFFFFF1F2);
    final time = act['time'] as DateTime;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showDivider ? kClockBorder : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(
              isArrival ? LucideIcons.logIn : LucideIcons.logOut,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArrival ? "Pointage d'arrivee" : 'Pointage de depart',
                  style: const TextStyle(
                    color: kClockText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE d MMMM yyyy, HH:mm', 'fr_FR').format(time),
                  style: const TextStyle(
                    color: kClockMuted,
                    fontSize: 13,
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

  Future<void> _showPunchHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.76,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 72,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8E5FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tous les pointages',
                          style: TextStyle(
                            color: kClockText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _activities.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              "Aucun pointage n'a encore ete enregistre.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: kClockMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                          itemCount: _activities.length,
                          itemBuilder: (context, index) {
                            return _buildHistoryRow(
                              _activities[index],
                              showDivider: index != _activities.length - 1,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCenterAlert() {
    if (_centerAlertMessage == null) return const SizedBox.shrink();

    final accent = _centerAlertSuccess ? kClockSuccess : kClockDanger;

    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          opacity: _centerAlertVisible ? 1 : 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.46),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _centerAlertSuccess
                      ? LucideIcons.checkCircle2
                      : LucideIcons.alertCircle,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _centerAlertMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: kClockPageBg,
        body: Center(child: CircularProgressIndicator(color: kClockBlue)),
      );
    }

    return Scaffold(
      backgroundColor: kClockPageBg,
      body: Stack(
        children: [
          _buildZoneMapCard(),
          _buildFloatingStatusLayerCompact(),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.34),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.56),
                    ],
                    stops: const [0, 0.18, 0.58, 1],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHero(),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: BoxDecoration(
                      color: const Color(0xF9F8FBFF),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD8E5FF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildPunchCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(child: _buildCenterAlert()),
        ],
      ),
    );
  }
}

class _WorkLocationPickerSheet extends StatefulWidget {
  final String initialValue;
  final String currentPlaceName;

  const _WorkLocationPickerSheet({
    required this.initialValue,
    required this.currentPlaceName,
  });

  @override
  State<_WorkLocationPickerSheet> createState() =>
      _WorkLocationPickerSheetState();
}

class _WorkLocationPickerSheetState extends State<_WorkLocationPickerSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _placesSessionToken;
  Timer? _debounce;
  bool _isLoading = false;
  bool _isResolving = false;
  String? _errorMessage;
  List<AddressSuggestion> _suggestions = <AddressSuggestion>[];

  @override
  void initState() {
    super.initState();
    _placesSessionToken = GooglePlacesService.createSessionToken();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    if (widget.initialValue.trim().isNotEmpty) {
      _search(widget.initialValue);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = <AddressSuggestion>[];
        _errorMessage = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _errorMessage = null);
    _debounce = Timer(const Duration(milliseconds: 380), () {
      _search(value);
    });
  }

  Future<void> _search(String value) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await GooglePlacesService.autocomplete(
        value,
        sessionToken: _placesSessionToken,
      );
      if (!mounted) return;
      setState(() => _suggestions = results);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = <AddressSuggestion>[];
        _errorMessage =
            "La recherche Google Maps est indisponible pour le moment.";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectSuggestion(AddressSuggestion suggestion) async {
    setState(() {
      _isResolving = true;
      _errorMessage = null;
    });

    try {
      final details = await GooglePlacesService.fetchPlaceDetails(
        suggestion,
        sessionToken: _placesSessionToken,
      );
      if (!mounted) return;
      _placesSessionToken = GooglePlacesService.createSessionToken();
      Navigator.pop(context, details);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            "Impossible de recuperer cette adresse precise. Essayez une autre suggestion.";
      });
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 12,
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8E5FF),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Adresse du departement',
              style: TextStyle(
                color: kClockText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Choisissez une adresse Google Maps precise. Elle servira a valider la zone de pointage.",
              style: TextStyle(
                color: kClockMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              style: const TextStyle(
                color: kClockText,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Rechercher un hotel, une rue, un batiment...',
                prefixIcon: const Icon(LucideIcons.search, color: kClockBlue),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : (_controller.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _controller.clear();
                                _onQueryChanged('');
                              },
                              icon: const Icon(
                                LucideIcons.x,
                                color: kClockMuted,
                                size: 18,
                              ),
                            )),
                filled: true,
                fillColor: const Color(0xFFF8FBFF),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: Color(0xFFD9E7FF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: Color(0xFFD9E7FF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: kClockBlue, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.currentPlaceName.trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kClockLightBlue,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Adresse actuelle: ${widget.currentPlaceName}',
                  style: const TextStyle(
                    color: kClockBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (widget.currentPlaceName.trim().isNotEmpty)
              const SizedBox(height: 12),
            if (_errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            Flexible(
              child: _suggestions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          _controller.text.trim().isEmpty
                              ? 'Commencez a taper pour voir les suggestions Google Maps.'
                              : 'Aucune suggestion pour cette recherche.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: kClockMuted,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: kClockBorder),
                      itemBuilder: (context, index) {
                        final suggestion = _suggestions[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: kClockLightBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.mapPin,
                              color: kClockBlue,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            suggestion.title,
                            style: const TextStyle(
                              color: kClockText,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            suggestion.subtitle.isEmpty
                                ? suggestion.fullAddress
                                : suggestion.subtitle,
                            style: const TextStyle(
                              color: kClockMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                          trailing: _isResolving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  LucideIcons.chevronRight,
                                  color: kClockMuted,
                                  size: 18,
                                ),
                          onTap: _isResolving
                              ? null
                              : () => _selectSuggestion(suggestion),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
