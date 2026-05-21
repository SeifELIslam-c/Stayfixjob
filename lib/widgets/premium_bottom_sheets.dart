import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/google_places_service.dart';

const _sheetBlue = Color(0xFF0F63FF);
const _sheetText = Color(0xFF0F172A);
const _sheetBody = Color(0xFF475569);
const _sheetMuted = Color(0xFF64748B);
const _sheetBorder = Color(0xFFE2E8F0);
const _sheetLightBlue = Color(0xFFEAF2FF);

Future<DateTime?> showPremiumDatePickerSheet({
  required BuildContext context,
  DateTime? initialDate,
  DateTime? minimumDate,
  DateTime? maximumDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (context) => _PremiumDatePickerSheet(
      initialDate: initialDate,
      minimumDate: minimumDate,
      maximumDate: maximumDate,
    ),
  );
}

Future<String?> showSmartAddressPickerSheet({
  required BuildContext context,
  String initialValue = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (context) => _SmartAddressPickerSheet(initialValue: initialValue),
  );
}

class _PremiumDatePickerSheet extends StatefulWidget {
  const _PremiumDatePickerSheet({
    required this.initialDate,
    required this.minimumDate,
    required this.maximumDate,
  });

  final DateTime? initialDate;
  final DateTime? minimumDate;
  final DateTime? maximumDate;

  @override
  State<_PremiumDatePickerSheet> createState() =>
      _PremiumDatePickerSheetState();
}

class _PremiumDatePickerSheetState extends State<_PremiumDatePickerSheet> {
  static const List<String> _months = <String>[
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

  late final DateTime _minimumDate;
  late final DateTime _maximumDate;
  late List<int> _years;
  late int _selectedMonth;
  late int _selectedDay;
  late int _selectedYear;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _dayController;
  late FixedExtentScrollController _yearController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _minimumDate = widget.minimumDate ?? DateTime(1940, 1, 1);
    _maximumDate = widget.maximumDate ?? DateTime(now.year, now.month, now.day);
    final fallback = DateTime(now.year - 25, now.month, now.day);
    final initial = _clampDate(widget.initialDate ?? fallback);

    _selectedMonth = initial.month;
    _selectedDay = initial.day;
    _selectedYear = initial.year;
    _years = List<int>.generate(
      _maximumDate.year - _minimumDate.year + 1,
      (index) => _minimumDate.year + index,
    );
    _monthController = FixedExtentScrollController(
      initialItem: _selectedMonth - 1,
    );
    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
    _yearController = FixedExtentScrollController(
      initialItem: _years.indexOf(_selectedYear),
    );
  }

  @override
  void dispose() {
    _monthController.dispose();
    _dayController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  DateTime _clampDate(DateTime input) {
    final cleaned = DateTime(input.year, input.month, input.day);
    if (cleaned.isBefore(_minimumDate)) return _minimumDate;
    if (cleaned.isAfter(_maximumDate)) return _maximumDate;
    return cleaned;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  void _syncDayToValidRange() {
    final maxDay = _daysInMonth(_selectedYear, _selectedMonth);
    if (_selectedDay > maxDay) {
      _selectedDay = maxDay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _dayController.jumpToItem(_selectedDay - 1);
          setState(() {});
        }
      });
    }

    final candidate = DateTime(_selectedYear, _selectedMonth, _selectedDay);
    final clamped = _clampDate(candidate);
    if (candidate != clamped) {
      _selectedMonth = clamped.month;
      _selectedDay = clamped.day;
      _selectedYear = clamped.year;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _monthController.jumpToItem(_selectedMonth - 1);
        _dayController.jumpToItem(_selectedDay - 1);
        _yearController.jumpToItem(_years.indexOf(_selectedYear));
        setState(() {});
      });
    }
  }

  Widget _columnDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 34),
      color: _sheetBorder.withValues(alpha: 0.72),
    );
  }

  String _selectedDateLabel() {
    return '${_months[_selectedMonth - 1]} $_selectedDay, $_selectedYear';
  }

  Widget _pickerColumn({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) labelBuilder,
    required int selectedIndex,
    required ValueChanged<int> onSelectedItemChanged,
    double flex = 1,
  }) {
    return Expanded(
      flex: flex.toInt(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _sheetBlue.withValues(alpha: 0.12)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F63FF),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Container(
                  height: 58,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _sheetLightBlue.withValues(alpha: 0.92),
                        Colors.white,
                        _sheetLightBlue.withValues(alpha: 0.92),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          CupertinoPicker.builder(
            scrollController: controller,
            itemExtent: 54,
            diameterRatio: 1.7,
            squeeze: 1.08,
            useMagnifier: true,
            magnification: 1.04,
            selectionOverlay: const SizedBox.shrink(),
            onSelectedItemChanged: (index) {
              onSelectedItemChanged(index);
              setState(() {});
            },
            childCount: itemCount,
            itemBuilder: (context, index) {
              final isSelected = index == selectedIndex;
              return Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(
                    color: isSelected
                        ? _sheetBlue
                        : _sheetText.withValues(alpha: 0.34),
                    fontSize: isSelected ? 18.5 : 16.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  ),
                  child: Text(labelBuilder(index)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxDays = _daysInMonth(_selectedYear, _selectedMonth);

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFFD8E5FF),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF8FBFF), Color(0xFFEFF6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFFDCE8FF)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Date de naissance',
                    style: TextStyle(
                      color: _sheetMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _selectedDateLabel(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _sheetBlue,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(
                        color: _sheetBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      final result = _clampDate(
                        DateTime(_selectedYear, _selectedMonth, _selectedDay),
                      );
                      Navigator.pop(context, result);
                    },
                    child: const Text(
                      'Termine',
                      style: TextStyle(
                        color: _sheetBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 320,
              decoration: BoxDecoration(
                color: const Color(0xFFFDFEFF),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFDCE8FF)),
              ),
              child: Row(
                children: [
                  _pickerColumn(
                    controller: _monthController,
                    itemCount: _months.length,
                    labelBuilder: (index) => _months[index],
                    selectedIndex: _selectedMonth - 1,
                    onSelectedItemChanged: (index) {
                      _selectedMonth = index + 1;
                      _syncDayToValidRange();
                    },
                    flex: 2,
                  ),
                  _columnDivider(),
                  _pickerColumn(
                    controller: _dayController,
                    itemCount: maxDays,
                    labelBuilder: (index) => '${index + 1}',
                    selectedIndex: _selectedDay - 1,
                    onSelectedItemChanged: (index) {
                      _selectedDay = index + 1;
                    },
                  ),
                  _columnDivider(),
                  _pickerColumn(
                    controller: _yearController,
                    itemCount: _years.length,
                    labelBuilder: (index) => '${_years[index]}',
                    selectedIndex: _years.indexOf(_selectedYear),
                    onSelectedItemChanged: (index) {
                      _selectedYear = _years[index];
                      _syncDayToValidRange();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartAddressPickerSheet extends StatefulWidget {
  const _SmartAddressPickerSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_SmartAddressPickerSheet> createState() =>
      _SmartAddressPickerSheetState();
}

class _SmartAddressPickerSheetState extends State<_SmartAddressPickerSheet> {
  static const LatLng _defaultMapCenter = LatLng(36.7538, 3.0588);

  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _placesSessionToken;
  Timer? _debounce;
  GoogleMapController? _mapController;
  bool _isLoading = false;
  bool _isResolving = false;
  bool _isLocating = false;
  String? _errorMessage;
  List<AddressSuggestion> _suggestions = <AddressSuggestion>[];
  GooglePlaceDetails? _selectedDetails;

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
    _mapController?.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _errorMessage = null;
    });

    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = <AddressSuggestion>[];
        _isLoading = false;
      });
      return;
    }

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
      setState(() {
        _suggestions = results;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _suggestions = <AddressSuggestion>[];
        _errorMessage =
            "La recherche d'adresse est indisponible pour le moment.";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      _controller.value = TextEditingValue(
        text: details.formattedAddress.trim(),
        selection: TextSelection.collapsed(
          offset: details.formattedAddress.trim().length,
        ),
      );
      setState(() {
        _selectedDetails = details;
        _suggestions = <AddressSuggestion>[];
      });
      await _animateToSelectedLocation();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            "Impossible de valider cette adresse Google Maps. Essayez une autre suggestion.";
      });
    } finally {
      if (mounted) {
        setState(() => _isResolving = false);
      }
    }
  }

  Future<void> _chooseCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('service-disabled');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      final granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) {
        throw Exception('permission-denied');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final details = await GooglePlacesService.reverseGeocode(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;

      _controller.value = TextEditingValue(
        text: details.formattedAddress.trim(),
        selection: TextSelection.collapsed(
          offset: details.formattedAddress.trim().length,
        ),
      );

      setState(() {
        _selectedDetails = details;
        _suggestions = <AddressSuggestion>[];
      });

      await _animateToSelectedLocation();
    } catch (error) {
      if (!mounted) return;

      final message = switch (error.toString()) {
        'Exception: service-disabled' =>
          'Activez la localisation du telephone pour utiliser votre position exacte.',
        'Exception: permission-denied' =>
          'Autorisez la localisation pour choisir votre position exacte.',
        _ =>
          "Impossible de recuperer votre position exacte depuis Google Maps pour le moment.",
      };

      setState(() => _errorMessage = message);
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  LatLng get _mapCenter {
    final details = _selectedDetails;
    if (details != null) {
      return LatLng(details.latitude, details.longitude);
    }
    return _defaultMapCenter;
  }

  Set<Marker> _buildMarkers() {
    final details = _selectedDetails;
    if (details == null) return const <Marker>{};

    return <Marker>{
      Marker(
        markerId: const MarkerId('selected_address'),
        position: LatLng(details.latitude, details.longitude),
        infoWindow: InfoWindow(
          title: details.name.trim().isEmpty
              ? 'Adresse selectionnee'
              : details.name,
          snippet: details.formattedAddress,
        ),
      ),
    };
  }

  Future<void> _animateToSelectedLocation() async {
    final details = _selectedDetails;
    final controller = _mapController;
    if (details == null || controller == null) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(details.latitude, details.longitude),
          zoom: 17,
        ),
      ),
    );
  }

  void _confirmSelection() {
    final details = _selectedDetails;
    if (details == null) return;
    Navigator.pop(context, details.formattedAddress.trim());
  }

  Widget _suggestionRow(AddressSuggestion suggestion) {
    return InkWell(
      onTap: _isResolving || _isLocating
          ? null
          : () => _selectSuggestion(suggestion),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: _sheetLightBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.mapPin,
                color: _sheetBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.title,
                    style: const TextStyle(
                      color: _sheetText,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (suggestion.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      suggestion.subtitle,
                      style: const TextStyle(
                        color: _sheetBody,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(LucideIcons.chevronRight, color: _sheetBlue, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDetails = _selectedDetails;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.84,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 120,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8E5FF),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Adresse',
                style: TextStyle(
                  color: _sheetText,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Recherchez une vraie adresse Google Maps ou utilisez votre position exacte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _sheetMuted,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _sheetBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F63FF),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _mapCenter,
                    zoom: selectedDetails == null ? 12 : 17,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (selectedDetails != null) {
                      unawaited(_animateToSelectedLocation());
                    }
                  },
                  markers: _buildMarkers(),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: _onQueryChanged,
                      style: const TextStyle(
                        color: _sheetText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Adresse Google Maps *',
                        labelStyle: const TextStyle(
                          color: _sheetBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        hintText: 'Entrez votre adresse',
                        hintStyle: const TextStyle(color: _sheetMuted),
                        prefixIcon: const Icon(
                          LucideIcons.search,
                          color: _sheetBlue,
                          size: 20,
                        ),
                        suffixIcon: _isResolving || _isLocating
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : _controller.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _controller.clear();
                                  _onQueryChanged('');
                                  setState(() {
                                    _selectedDetails = null;
                                  });
                                },
                                icon: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: _sheetLightBlue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    LucideIcons.x,
                                    color: _sheetBlue,
                                    size: 18,
                                  ),
                                ),
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: _sheetBlue,
                            width: 1.4,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: _sheetBlue,
                            width: 1.4,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: _sheetBlue,
                            width: 1.7,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLocating || _isResolving
                            ? null
                            : _chooseCurrentLocation,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _sheetBlue,
                          side: const BorderSide(color: Color(0xFFD4E3FF)),
                          backgroundColor: const Color(0xFFF8FBFF),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: _isLocating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _sheetBlue,
                                ),
                              )
                            : const Icon(LucideIcons.locateFixed, size: 18),
                        label: const Text(
                          'Choisir ma position',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (selectedDetails != null) ...[
                const SizedBox(height: 14),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _sheetLightBlue,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD5E4FF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Adresse selectionnee',
                        style: TextStyle(
                          color: _sheetBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selectedDetails.formattedAddress,
                        style: const TextStyle(
                          color: _sheetText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: _sheetBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F0F63FF),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: _sheetBlue),
                        )
                      : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.searchX,
                                  color: _sheetBlue,
                                  size: 30,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: _sheetText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "Essayez d'etre plus precis et choisissez une suggestion Google Maps.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _sheetMuted,
                                    fontSize: 13.5,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _controller.text.trim().isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              "Saisissez une adresse pour afficher les suggestions.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _sheetMuted,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                      : _suggestions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.searchX,
                                  color: _sheetBlue,
                                  size: 30,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Aucune adresse trouvee',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _sheetText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "Essayez d'etre plus precis pour afficher des adresses Google Maps.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _sheetMuted,
                                    fontSize: 13.5,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemBuilder: (context, index) =>
                              _suggestionRow(_suggestions[index]),
                          separatorBuilder: (context, index) => const Divider(
                            color: _sheetBorder,
                            height: 1,
                            indent: 84,
                            endIndent: 16,
                          ),
                          itemCount: _suggestions.length,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _sheetBlue,
                          side: const BorderSide(color: _sheetBlue),
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Annuler',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: selectedDetails == null
                            ? null
                            : _confirmSelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _sheetBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFBFDBFE),
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Utiliser cette adresse',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
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
}
