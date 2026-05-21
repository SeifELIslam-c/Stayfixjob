import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_env.dart';

class AddressSuggestion {
  final String placeId;
  final String title;
  final String subtitle;
  final String fullAddress;

  const AddressSuggestion({
    required this.placeId,
    required this.title,
    required this.subtitle,
    required this.fullAddress,
  });
}

class GooglePlaceDetails {
  final String placeId;
  final String name;
  final String formattedAddress;
  final double latitude;
  final double longitude;

  const GooglePlaceDetails({
    required this.placeId,
    required this.name,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
  });
}

class GooglePlacesService {
  static String createSessionToken() {
    final random = Random.secure();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }

  static Future<List<AddressSuggestion>> autocomplete(
    String input, {
    String? sessionToken,
  }) async {
    final query = input.trim();
    if (query.isEmpty) return const [];

    final apiKey = AppEnv.get('GOOGLE_MAPS_API_KEY');
    if (apiKey == null || apiKey.isEmpty) {
      throw const _PlacesUnavailableException();
    }

    final activeSessionToken = sessionToken ?? createSessionToken();

    final addressResults = await _requestAutocomplete(
      query: query,
      apiKey: apiKey,
      sessionToken: activeSessionToken,
      placeType: 'address',
    );

    if (addressResults.isNotEmpty) {
      return addressResults;
    }

    final geocodeResults = await _requestAutocomplete(
      query: query,
      apiKey: apiKey,
      sessionToken: activeSessionToken,
      placeType: 'geocode',
    );

    if (geocodeResults.isNotEmpty) {
      return geocodeResults;
    }

    final broadResults = await _requestAutocomplete(
      query: query,
      apiKey: apiKey,
      sessionToken: activeSessionToken,
    );

    if (broadResults.isNotEmpty) {
      return broadResults;
    }

    return _requestGeocode(query: query, apiKey: apiKey);
  }

  static Future<List<AddressSuggestion>> _requestAutocomplete({
    required String query,
    required String apiKey,
    required String sessionToken,
    String? placeType,
  }) async {
    final params = <String, String>{
      'input': query,
      'language': 'fr',
      'sessiontoken': sessionToken,
      'key': apiKey,
    };

    if (placeType != null && placeType.isNotEmpty) {
      params['types'] = placeType;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != HttpStatus.ok) {
        throw const _PlacesRequestException();
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final status = decoded['status'] as String? ?? 'UNKNOWN_ERROR';
      if (status == 'ZERO_RESULTS') return const [];
      if (status != 'OK') throw const _PlacesRequestException();

      final predictions = decoded['predictions'] as List<dynamic>? ?? const [];
      return predictions
          .map((item) {
            final map = item as Map<String, dynamic>;
            final formatting =
                map['structured_formatting'] as Map<String, dynamic>? ??
                const {};
            return AddressSuggestion(
              placeId: map['place_id'] as String? ?? '',
              title:
                  formatting['main_text'] as String? ??
                  (map['description'] as String? ?? ''),
              subtitle: formatting['secondary_text'] as String? ?? '',
              fullAddress: map['description'] as String? ?? '',
            );
          })
          .where(
            (item) => item.placeId.isNotEmpty || item.fullAddress.isNotEmpty,
          )
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<AddressSuggestion>> _requestGeocode({
    required String query,
    required String apiKey,
  }) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': query,
      'language': 'fr',
      'key': apiKey,
    });

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != HttpStatus.ok) {
        throw const _PlacesRequestException();
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final status = decoded['status'] as String? ?? 'UNKNOWN_ERROR';
      if (status == 'ZERO_RESULTS') return const [];
      if (status != 'OK') throw const _PlacesRequestException();

      final results = decoded['results'] as List<dynamic>? ?? const [];
      return results
          .take(8)
          .map((item) {
            final map = item as Map<String, dynamic>;
            final formattedAddress = map['formatted_address'] as String? ?? '';
            final parts = formattedAddress
                .split(',')
                .map((part) => part.trim())
                .where((part) => part.isNotEmpty)
                .toList();
            final title = parts.isEmpty ? formattedAddress : parts.first;
            final subtitle = parts.length <= 1 ? '' : parts.skip(1).join(', ');
            final placeId = map['place_id'] as String? ?? '';

            return AddressSuggestion(
              placeId: placeId,
              title: title,
              subtitle: subtitle,
              fullAddress: formattedAddress,
            );
          })
          .where((item) => item.fullAddress.isNotEmpty)
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> fetchPlaceAddress(
    AddressSuggestion suggestion, {
    String? sessionToken,
  }) async {
    final apiKey = AppEnv.get('GOOGLE_MAPS_API_KEY');
    if (apiKey == null || apiKey.isEmpty) {
      return suggestion.fullAddress;
    }
    if (suggestion.placeId.isEmpty) return suggestion.fullAddress;

    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': suggestion.placeId,
          'fields': 'formatted_address',
          'language': 'fr',
          if (sessionToken != null && sessionToken.isNotEmpty)
            'sessiontoken': sessionToken,
          'key': apiKey,
        });

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != HttpStatus.ok) {
        return suggestion.fullAddress;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final status = decoded['status'] as String? ?? 'UNKNOWN_ERROR';
      if (status != 'OK') return suggestion.fullAddress;

      final result = decoded['result'] as Map<String, dynamic>? ?? const {};
      return result['formatted_address'] as String? ?? suggestion.fullAddress;
    } catch (_) {
      return suggestion.fullAddress;
    } finally {
      client.close(force: true);
    }
  }

  static Future<GooglePlaceDetails> fetchPlaceDetails(
    AddressSuggestion suggestion, {
    String? sessionToken,
  }) async {
    final apiKey = AppEnv.get('GOOGLE_MAPS_API_KEY');
    if (apiKey == null || apiKey.isEmpty) {
      throw const _PlacesUnavailableException();
    }
    if (suggestion.placeId.isEmpty) {
      throw const _PlacesRequestException();
    }

    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
          'place_id': suggestion.placeId,
          'fields': 'place_id,name,formatted_address,geometry',
          'language': 'fr',
          if (sessionToken != null && sessionToken.isNotEmpty)
            'sessiontoken': sessionToken,
          'key': apiKey,
        });

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != HttpStatus.ok) {
        throw const _PlacesRequestException();
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final status = decoded['status'] as String? ?? 'UNKNOWN_ERROR';
      if (status != 'OK') throw const _PlacesRequestException();

      final result = decoded['result'] as Map<String, dynamic>? ?? const {};
      final geometry = result['geometry'] as Map<String, dynamic>? ?? const {};
      final location =
          geometry['location'] as Map<String, dynamic>? ?? const {};

      final latitude = (location['lat'] as num?)?.toDouble();
      final longitude = (location['lng'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        throw const _PlacesRequestException();
      }

      return GooglePlaceDetails(
        placeId: result['place_id'] as String? ?? suggestion.placeId,
        name: result['name'] as String? ?? suggestion.title,
        formattedAddress:
            result['formatted_address'] as String? ?? suggestion.fullAddress,
        latitude: latitude,
        longitude: longitude,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<GooglePlaceDetails> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final apiKey = AppEnv.get('GOOGLE_MAPS_API_KEY');
    if (apiKey == null || apiKey.isEmpty) {
      throw const _PlacesUnavailableException();
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '$latitude,$longitude',
      'language': 'fr',
      'key': apiKey,
    });

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != HttpStatus.ok) {
        throw const _PlacesRequestException();
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final status = decoded['status'] as String? ?? 'UNKNOWN_ERROR';
      if (status != 'OK') throw const _PlacesRequestException();

      final results = decoded['results'] as List<dynamic>? ?? const [];
      if (results.isEmpty) throw const _PlacesRequestException();

      final result = results.first as Map<String, dynamic>;
      final formattedAddress = result['formatted_address'] as String? ?? '';
      final placeId = result['place_id'] as String? ?? '';

      final parts = formattedAddress
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      final title = parts.isEmpty ? formattedAddress : parts.first;

      return GooglePlaceDetails(
        placeId: placeId,
        name: title,
        formattedAddress: formattedAddress,
        latitude: latitude,
        longitude: longitude,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _PlacesUnavailableException implements Exception {
  const _PlacesUnavailableException();
}

class _PlacesRequestException implements Exception {
  const _PlacesRequestException();
}
