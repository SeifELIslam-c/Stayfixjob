import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/google_places_service.dart';

const Color kAddressPickerBlue = Color(0xFF0F63FF);
const Color kAddressPickerDeepBlue = Color(0xFF2563EB);
const Color kAddressPickerText = Color(0xFF0F172A);
const Color kAddressPickerMuted = Color(0xFF64748B);
const Color kAddressPickerBody = Color(0xFF475569);
const Color kAddressPickerBorder = Color(0xFFDCE8FF);
const Color kAddressPickerSoftBlue = Color(0xFFEFF6FF);

class AddressPickerResult {
  const AddressPickerResult({
    required this.address,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.label,
  });

  final String address;
  final double latitude;
  final double longitude;
  final String? placeId;
  final String? label;
}

enum AddressPickerPresentation { fullscreen, modal }

Future<AddressPickerResult?> showAddressPicker({
  required BuildContext context,
  String initialAddress = '',
  double? initialLatitude,
  double? initialLongitude,
  AddressPickerPresentation presentation = AddressPickerPresentation.fullscreen,
  String title = 'Modifier adresse',
  String confirmationText =
      'Confirmez cette position pour enregistrer votre adresse du condo.',
  String confirmLabel = 'Confirmer adresse',
}) async {
  final picker = _AddressPickerScaffold(
    initialAddress: initialAddress,
    initialLatitude: initialLatitude,
    initialLongitude: initialLongitude,
    title: title,
    confirmationText: confirmationText,
    confirmLabel: confirmLabel,
  );

  if (presentation == AddressPickerPresentation.fullscreen) {
    return Navigator.of(context).push<AddressPickerResult>(
      MaterialPageRoute(builder: (_) => picker, fullscreenDialog: true),
    );
  }

  return showModalBottomSheet<AddressPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(heightFactor: 0.75, child: picker),
  );
}

class _AddressPickerScaffold extends StatefulWidget {
  const _AddressPickerScaffold({
    required this.initialAddress,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.title,
    required this.confirmationText,
    required this.confirmLabel,
  });

  final String initialAddress;
  final double? initialLatitude;
  final double? initialLongitude;
  final String title;
  final String confirmationText;
  final String confirmLabel;

  @override
  State<_AddressPickerScaffold> createState() => _AddressPickerScaffoldState();
}

class _AddressPickerScaffoldState extends State<_AddressPickerScaffold> {
  static const LatLng _fallbackMapCenter = LatLng(20.0, 0.0);

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late String _placesSessionToken;

  GoogleMapController? _mapController;
  Timer? _debounce;
  bool _isBootstrapping = true;
  bool _isSearching = false;
  bool _isResolving = false;
  bool _isLocationRefreshing = false;
  bool _locationPermissionGranted = false;
  String? _errorMessage;
  List<AddressSuggestion> _suggestions = <AddressSuggestion>[];
  AddressPickerResult? _selectedResult;
  LatLng? _selectedLatLng;

  @override
  void initState() {
    super.initState();
    _placesSessionToken = GooglePlacesService.createSessionToken();
    _searchController = TextEditingController(text: widget.initialAddress);
    _searchFocusNode = FocusNode();
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      if (widget.initialLatitude != null && widget.initialLongitude != null) {
        final result = await _reverseGeocodeLatLng(
          LatLng(widget.initialLatitude!, widget.initialLongitude!),
          fallbackAddress: widget.initialAddress,
        );
        if (!mounted) return;
        setState(() {
          _selectedResult = result;
          _selectedLatLng = LatLng(result.latitude, result.longitude);
        });
      } else {
        await _resolveCurrentLocation(initialLoad: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isBootstrapping = false);
      }
    }
  }

  Future<void> _resolveCurrentLocation({bool initialLoad = false}) async {
    if (!initialLoad) {
      setState(() {
        _isLocationRefreshing = true;
        _errorMessage = null;
      });
    }

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

      _locationPermissionGranted = true;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final result = await _reverseGeocodeLatLng(
        LatLng(position.latitude, position.longitude),
        fallbackAddress: widget.initialAddress,
      );

      if (!mounted) return;
      setState(() {
        _selectedResult = result;
        _selectedLatLng = LatLng(result.latitude, result.longitude);
        _searchController.text = result.address;
        _suggestions = <AddressSuggestion>[];
      });
      await _animateToSelected();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationPermissionGranted = false;
        _errorMessage = switch (error.toString()) {
          'Exception: service-disabled' =>
            'La localisation est desactivee. Vous pouvez quand meme rechercher une adresse ou toucher la carte.',
          'Exception: permission-denied' =>
            'La permission de localisation est refusee. Utilisez la recherche ou touchez la carte pour choisir une adresse.',
          _ =>
            'Impossible de recuperer votre position actuelle pour le moment.',
        };
        _selectedLatLng ??= _fallbackMapCenter;
      });
    } finally {
      if (mounted && !initialLoad) {
        setState(() => _isLocationRefreshing = false);
      }
    }
  }

  Future<AddressPickerResult> _reverseGeocodeLatLng(
    LatLng latLng, {
    String fallbackAddress = '',
  }) async {
    try {
      final details = await GooglePlacesService.reverseGeocode(
        latitude: latLng.latitude,
        longitude: latLng.longitude,
      );

      return AddressPickerResult(
        address: details.formattedAddress.trim(),
        latitude: details.latitude,
        longitude: details.longitude,
        placeId: details.placeId,
        label: details.name,
      );
    } catch (_) {
      return AddressPickerResult(
        address: fallbackAddress.trim().isEmpty
            ? 'Adresse selectionnee'
            : fallbackAddress.trim(),
        latitude: latLng.latitude,
        longitude: latLng.longitude,
      );
    }
  }

  Future<void> _search(String query) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await GooglePlacesService.autocomplete(
        query,
        sessionToken: _placesSessionToken,
      );
      if (!mounted) return;
      setState(() => _suggestions = results);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = <AddressSuggestion>[];
        _errorMessage =
            'La recherche Google Maps est indisponible pour le moment.';
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _suggestions = <AddressSuggestion>[]);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 320), () {
      _search(value);
    });
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

      final result = AddressPickerResult(
        address: details.formattedAddress.trim(),
        latitude: details.latitude,
        longitude: details.longitude,
        placeId: details.placeId,
        label: details.name,
      );

      setState(() {
        _selectedResult = result;
        _selectedLatLng = LatLng(details.latitude, details.longitude);
        _searchController.text = details.formattedAddress.trim();
        _suggestions = <AddressSuggestion>[];
      });
      await _animateToSelected(zoom: 17);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Impossible de recuperer cette adresse precise. Essayez une autre suggestion.';
      });
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _handleMapTap(LatLng latLng) async {
    setState(() {
      _isResolving = true;
      _errorMessage = null;
      _selectedLatLng = latLng;
      _suggestions = <AddressSuggestion>[];
    });

    final result = await _reverseGeocodeLatLng(
      latLng,
      fallbackAddress: _selectedResult?.address ?? widget.initialAddress,
    );
    if (!mounted) return;

    setState(() {
      _selectedResult = result;
      _searchController.text = result.address;
      _isResolving = false;
    });
  }

  Future<void> _animateToSelected({double zoom = 16.8}) async {
    final controller = _mapController;
    final selected = _selectedLatLng;
    if (controller == null || selected == null) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: selected, zoom: zoom),
      ),
    );
  }

  Future<void> _zoomBy(double delta) async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(CameraUpdate.zoomBy(delta));
  }

  Set<Marker> _buildMarkers() {
    final selected = _selectedLatLng;
    final result = _selectedResult;
    if (selected == null) return const <Marker>{};

    return <Marker>{
      Marker(
        markerId: const MarkerId('selected_location'),
        position: selected,
        infoWindow: InfoWindow(
          title: result?.label?.trim().isNotEmpty == true
              ? result!.label
              : 'Position selectionnee',
          snippet: result?.address,
        ),
      ),
    };
  }

  void _confirmSelection() {
    final result = _selectedResult;
    if (result == null) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final mapHeightBottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: kAddressPickerPageBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: _isBootstrapping
                ? const DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xFFF4F8FF)),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: kAddressPickerBlue,
                      ),
                    ),
                  )
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _selectedLatLng ?? _fallbackMapCenter,
                      zoom: _selectedResult == null ? 2.4 : 16.2,
                    ),
                    onMapCreated: (controller) async {
                      _mapController = controller;
                      if (_selectedLatLng != null) {
                        await _animateToSelected();
                      }
                    },
                    onTap: _handleMapTap,
                    myLocationEnabled: _locationPermissionGranted,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    buildingsEnabled: true,
                    rotateGesturesEnabled: true,
                    tiltGesturesEnabled: false,
                    markers: _buildMarkers(),
                  ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.9),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.18),
                    ],
                    stops: const [0.0, 0.18, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      _TopCircleButton(
                        icon: LucideIcons.arrowLeft,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: kAddressPickerText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _SearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    isLoading: _isSearching || _isResolving,
                    onChanged: _onSearchChanged,
                    onClear: () {
                      _searchController.clear();
                      setState(() => _suggestions = <AddressSuggestion>[]);
                    },
                  ),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                          fontSize: 12.8,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                if (_suggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kAddressPickerBorder),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x120F63FF),
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          color: kAddressPickerBorder,
                        ),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: kAddressPickerSoftBlue,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                LucideIcons.mapPin,
                                color: kAddressPickerBlue,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              suggestion.title,
                              style: const TextStyle(
                                color: kAddressPickerText,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              suggestion.subtitle.isEmpty
                                  ? suggestion.fullAddress
                                  : suggestion.subtitle,
                              style: const TextStyle(
                                color: kAddressPickerBody,
                                fontSize: 12.8,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: const Icon(
                              LucideIcons.chevronRight,
                              color: kAddressPickerMuted,
                              size: 18,
                            ),
                            onTap: () => _selectSuggestion(suggestion),
                          );
                        },
                      ),
                    ),
                  ),
                const Spacer(),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    18 + mapHeightBottomInset,
                  ),
                  child: _BottomConfirmationCard(
                    result: _selectedResult,
                    confirmationText: widget.confirmationText,
                    confirmLabel: widget.confirmLabel,
                    onConfirm: _selectedResult == null
                        ? null
                        : _confirmSelection,
                  ),
                ),
              ],
            ),
          ),
          if (!_isBootstrapping)
            Positioned(
              right: 16,
              top: 180,
              child: Column(
                children: [
                  _MapActionButton(
                    icon: LucideIcons.locateFixed,
                    loading: _isLocationRefreshing,
                    onTap: _isLocationRefreshing
                        ? null
                        : () => _resolveCurrentLocation(),
                  ),
                  const SizedBox(height: 10),
                  _MapActionButton(
                    icon: LucideIcons.plus,
                    onTap: () => _zoomBy(1),
                  ),
                  const SizedBox(height: 10),
                  _MapActionButton(
                    icon: LucideIcons.minus,
                    onTap: () => _zoomBy(-1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const Color kAddressPickerPageBg = Color(0xFFF7FAFF);

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kAddressPickerBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x100F63FF),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: kAddressPickerBlue, size: 20),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kAddressPickerBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F63FF),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: kAddressPickerText,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Rechercher une adresse...',
          hintStyle: const TextStyle(color: kAddressPickerMuted),
          prefixIcon: const Icon(
            LucideIcons.search,
            color: kAddressPickerBlue,
            size: 18,
          ),
          suffixIcon: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : controller.text.trim().isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(
                    LucideIcons.x,
                    color: kAddressPickerMuted,
                    size: 18,
                  ),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
        ),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kAddressPickerBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F63FF),
                blurRadius: 16,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(icon, color: kAddressPickerBlue, size: 20),
        ),
      ),
    );
  }
}

class _BottomConfirmationCard extends StatelessWidget {
  const _BottomConfirmationCard({
    required this.result,
    required this.confirmationText,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final AddressPickerResult? result;
  final String confirmationText;
  final String confirmLabel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kAddressPickerBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180F63FF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: LucideIcons.mapPin,
                label: result == null ? 'Aucune position' : 'Position choisie',
              ),
              if (result != null)
                _InfoChip(
                  icon: LucideIcons.navigation,
                  label:
                      '${result!.latitude.toStringAsFixed(5)}, ${result!.longitude.toStringAsFixed(5)}',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            result?.address ?? 'Touchez la carte ou recherchez une adresse.',
            style: const TextStyle(
              color: kAddressPickerText,
              fontSize: 17,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            confirmationText,
            style: const TextStyle(
              color: kAddressPickerBody,
              fontSize: 13.4,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: kAddressPickerBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                confirmLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: kAddressPickerSoftBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kAddressPickerBlue),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: kAddressPickerBlue,
              fontSize: 11.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
