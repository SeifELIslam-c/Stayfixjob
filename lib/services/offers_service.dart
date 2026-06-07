import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../models/manager_offer.dart';
import '../models/offer_application.dart';
import 'vps_media_service.dart';

class OffersService {
  OffersService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  Future<WorkerProfile?> loadWorkerProfile() async {
    final uid = _uid;
    if (uid == null) return null;
    final doc = await _firestore.collection('profiles').doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return WorkerProfile.fromFirestore(doc);
  }

  Future<List<ManagerOffer>> loadOffersForWorker(
    String department, {
    bool nearMeOnly = false,
    double? originLatitude,
    double? originLongitude,
    double maxDistanceKm = 35,
  }) async {
    final normalizedDepartment = department.trim().toLowerCase();
    final snapshot = await _firestore.collection('offers').get();
    final offers = snapshot.docs
        .map((doc) => ManagerOffer.fromFirestore(doc))
        .where((offer) {
          if (offer.status != OfferStatus.open) {
            return false;
          }
          if (normalizedDepartment.isNotEmpty &&
              offer.department.trim().toLowerCase() != normalizedDepartment) {
            return false;
          }
          if (!nearMeOnly ||
              originLatitude == null ||
              originLongitude == null) {
            return true;
          }
          if (offer.latitude == null || offer.longitude == null) return false;
          final distance = _distanceKm(
            originLatitude,
            originLongitude,
            offer.latitude!,
            offer.longitude!,
          );
          return distance <= maxDistanceKm;
        })
        .toList();
    offers.sort((a, b) {
      if (nearMeOnly && originLatitude != null && originLongitude != null) {
        final aDistance = a.latitude == null || a.longitude == null
            ? double.infinity
            : _distanceKm(
                originLatitude,
                originLongitude,
                a.latitude!,
                a.longitude!,
              );
        final bDistance = b.latitude == null || b.longitude == null
            ? double.infinity
            : _distanceKm(
                originLatitude,
                originLongitude,
                b.latitude!,
                b.longitude!,
              );
        if (aDistance != bDistance) return aDistance.compareTo(bDistance);
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return offers;
  }

  Future<List<ManagerOffer>> loadManagerCreatedOffersForStayfixJob() async {
    final snapshot = await _firestore.collection('offers').get();
    // Filter in Dart so offers remain visible regardless of whether the manager
    // app writes 'open', 'active', or 'published' — only exclude terminal states.
    // ManagerOffer._parseStatus() maps any unrecognised value to OfferStatus.open,
    // so 'active' and 'published' are treated as open automatically.
    final offers = snapshot.docs
        .map((doc) => ManagerOffer.fromFirestore(doc))
        .where(
          (offer) =>
              (offer.targetApp ?? '').trim().toLowerCase() == 'stayfix_job' &&
              offer.status != OfferStatus.assigned &&
              offer.status != OfferStatus.completed &&
              offer.status != OfferStatus.cancelled,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return offers;
  }

  Future<List<ManagerOffer>> loadMyAssignedOffers(String workerUid) async {
    final snapshot = await _firestore.collection('offers').get();
    final offers = snapshot.docs
        .map((doc) => ManagerOffer.fromFirestore(doc))
        .where((offer) => offer.assignedWorkerId == workerUid)
        .toList();
    offers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return offers;
  }

  Future<List<WorkerOffer>> loadMyPublishedOffers() async {
    final uid = _uid;
    if (uid == null) return const <WorkerOffer>[];
    final results = await Future.wait([
      _firestore.collection('worker_offers').get(),
      _firestore.collection('workers offers').get(),
    ]);
    final byId = <String, WorkerOffer>{};
    for (final snapshot in results) {
      for (final doc in snapshot.docs) {
        final offer = WorkerOffer.fromDocument(doc);
        if (offer.workerId != uid) continue;
        byId[doc.id] = offer;
      }
    }
    final offers = byId.values.toList();
    offers.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return offers;
  }

  Future<String> createWorkerOffer({
    required WorkerProfile worker,
    required String title,
    required String description,
    required String department,
    required String specialty,
    required List<Map<String, dynamic>> availabilitySlots,
    required String proposedStartTime,
    required String proposedEndTime,
    required bool proposedAllDay,
    required double? regularRate,
    required bool isPromotion,
    required double? originalRate,
    required double? promotionalRate,
    required bool isAvailableNow,
    File? imageFile,
    VpsUploadedMedia? uploadedImage,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utilisateur non connecté');
    if (worker.address.trim().isEmpty ||
        worker.addressLatitude == null ||
        worker.addressLongitude == null) {
      throw const AddressRequiredException();
    }

    var preparedUploadedImage = uploadedImage;
    if (preparedUploadedImage == null && imageFile != null) {
      final compressed = await _compressOfferImageIfNeeded(imageFile);
      final workerSlug = _slugify(worker.username);
      preparedUploadedImage = await VpsMediaService.uploadFile(
        file: compressed,
        category: 'workers-offers-media',
        folder: 'workers_offers_media/$workerSlug',
        extraFields: <String, String>{
          'workerName': worker.username,
          'workerId': uid,
        },
      );
    }

    final offerRef = _firestore.collection('worker_offers').doc();
    final discountPercent =
        isPromotion && originalRate != null && promotionalRate != null
        ? (((originalRate - promotionalRate) / originalRate) * 100).round()
        : null;

    final offerData = <String, dynamic>{
      'id': offerRef.id,
      'workerId': uid,
      'workerName': worker.username.trim(),
      'workerPhotoUrl': worker.photoUrl ?? '',
      'workerDepartment': department.trim(),
      'workerSpecialties': worker.specialties,
      'selectedSpecialty': specialty.trim(),
      'title': title.trim(),
      'description': description.trim(),
      'imageUrl': preparedUploadedImage?.url ?? '',
      'imageStoragePath': preparedUploadedImage?.fileId ?? '',
      'status': 'active',
      'visibleToManagers': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'currency': r'$',
      'rateUnit': 'hour',
      'regularRate': isPromotion ? null : regularRate,
      'isPromotion': isPromotion,
      'originalRate': isPromotion ? originalRate : null,
      'promotionalRate': isPromotion ? promotionalRate : null,
      'discountPercent': isPromotion ? discountPercent : null,
      'isAvailableNow': isAvailableNow,
      'availabilitySlots': availabilitySlots,
      'proposedStartTime': proposedStartTime,
      'proposedEndTime': proposedEndTime,
      'proposedAllDay': proposedAllDay,
      'availableWeekDays': worker.availableWeekDays,
      'targetCity': worker.city,
      'targetRegion': worker.region,
      'workerAddress': worker.address,
      'workerAddressLatitude': worker.addressLatitude,
      'workerAddressLongitude': worker.addressLongitude,
      'serviceRadiusKm': 25,
      'managerLocationScope': 'same_city',
      'viewCount': 0,
      'contactCount': 0,
      'mediaStorage': preparedUploadedImage == null ? null : 'vps',
      'mediaCategory': preparedUploadedImage == null
          ? null
          : 'workers-offers-media',
      'mediaFolder': preparedUploadedImage == null
          ? null
          : 'workers_offers_media/${_slugify(worker.username)}',
    };

    await Future.wait([
      offerRef.set(offerData),
      _firestore.collection('workers offers').doc(offerRef.id).set(offerData),
    ]);

    return offerRef.id;
  }

  Future<void> updateWorkerOffer({
    required WorkerOffer existingOffer,
    required WorkerProfile worker,
    required String title,
    required String description,
    required String department,
    required String specialty,
    required List<Map<String, dynamic>> availabilitySlots,
    required String proposedStartTime,
    required String proposedEndTime,
    required bool proposedAllDay,
    required double? regularRate,
    required bool isPromotion,
    required double? originalRate,
    required double? promotionalRate,
    required bool isAvailableNow,
    File? imageFile,
    VpsUploadedMedia? uploadedImage,
    bool removeImage = false,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utilisateur non connecte');

    var preparedUploadedImage = uploadedImage;
    if (preparedUploadedImage == null && imageFile != null) {
      final compressed = await _compressOfferImageIfNeeded(imageFile);
      final workerSlug = _slugify(worker.username);
      preparedUploadedImage = await VpsMediaService.uploadFile(
        file: compressed,
        category: 'workers-offers-media',
        folder: 'workers_offers_media/$workerSlug',
        extraFields: <String, String>{
          'workerName': worker.username,
          'workerId': uid,
        },
      );
    }

    final discountPercent =
        isPromotion && originalRate != null && promotionalRate != null
        ? (((originalRate - promotionalRate) / originalRate) * 100).round()
        : null;

    final nextImageUrl = removeImage
        ? ''
        : preparedUploadedImage?.url ?? (existingOffer.imageUrl ?? '');
    final nextImageStoragePath = removeImage
        ? ''
        : preparedUploadedImage?.fileId ?? (existingOffer.imageStoragePath ?? '');

    final offerData = <String, dynamic>{
      'workerName': worker.username.trim(),
      'workerPhotoUrl': worker.photoUrl ?? '',
      'workerDepartment': department.trim(),
      'workerSpecialties': worker.specialties,
      'selectedSpecialty': specialty.trim(),
      'title': title.trim(),
      'description': description.trim(),
      'imageUrl': nextImageUrl,
      'imageStoragePath': nextImageStoragePath,
      'updatedAt': FieldValue.serverTimestamp(),
      'regularRate': isPromotion ? null : regularRate,
      'isPromotion': isPromotion,
      'originalRate': isPromotion ? originalRate : null,
      'promotionalRate': isPromotion ? promotionalRate : null,
      'discountPercent': isPromotion ? discountPercent : null,
      'isAvailableNow': isAvailableNow,
      'availabilitySlots': availabilitySlots,
      'proposedStartTime': proposedStartTime,
      'proposedEndTime': proposedEndTime,
      'proposedAllDay': proposedAllDay,
      'availableWeekDays': worker.availableWeekDays,
      'targetCity': worker.city,
      'targetRegion': worker.region,
      'workerAddress': worker.address,
      'workerAddressLatitude': worker.addressLatitude,
      'workerAddressLongitude': worker.addressLongitude,
      'mediaStorage': nextImageStoragePath.isEmpty ? null : 'vps',
      'mediaCategory': nextImageStoragePath.isEmpty
          ? null
          : 'workers-offers-media',
      'mediaFolder': nextImageStoragePath.isEmpty
          ? null
          : 'workers_offers_media/${_slugify(worker.username)}',
    };

    await Future.wait([
      _firestore
          .collection('worker_offers')
          .doc(existingOffer.id)
          .set(offerData, SetOptions(merge: true)),
      _firestore
          .collection('workers offers')
          .doc(existingOffer.id)
          .set(offerData, SetOptions(merge: true)),
    ]);

    final oldFileId = existingOffer.imageStoragePath?.trim() ?? '';
    final replacedFileId = preparedUploadedImage?.fileId.trim() ?? '';
    if (oldFileId.isNotEmpty &&
        (removeImage || (replacedFileId.isNotEmpty && replacedFileId != oldFileId))) {
      await VpsMediaService.deleteFiles([oldFileId]);
    }
  }

  Future<void> deleteWorkerOffer(WorkerOffer offer) async {
    await Future.wait([
      _firestore.collection('worker_offers').doc(offer.id).delete(),
      _firestore.collection('workers offers').doc(offer.id).delete(),
    ]);

    final fileId = offer.imageStoragePath?.trim() ?? '';
    if (fileId.isNotEmpty) {
      await VpsMediaService.deleteFiles([fileId]);
    }
  }

  Future<bool> hasAlreadyApplied(String offerId) async {
    final uid = _uid;
    if (uid == null) return false;
    final snapshot = await _firestore.collection('offer_applications').get();
    return snapshot.docs.any((doc) {
      final data = doc.data();
      return (data['offerId'] as String? ?? '') == offerId &&
          (data['workerId'] as String? ?? '') == uid;
    });
  }

  Future<void> applyToOffer({
    required ManagerOffer offer,
    required WorkerProfile worker,
    String? message,
    double? proposedPrice,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Utilisateur non connecte');

    if (await hasAlreadyApplied(offer.id)) throw AlreadyAppliedException();

    final application = OfferApplication(
      offerId: offer.id,
      workerId: uid,
      managerId: offer.createdByManagerId,
      workerName: worker.username,
      workerDepartment: worker.department,
      workerSpecialties: worker.specialties,
      workerPhotoBase64: worker.photoBase64,
      status: 'pending',
      message: message,
      proposedPrice: proposedPrice,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection('offer_applications')
        .add(application.toFirestore());
  }

  Future<Set<String>> loadAppliedOfferIds() async {
    final uid = _uid;
    if (uid == null) return {};
    final snapshot = await _firestore.collection('offer_applications').get();
    return snapshot.docs
        .where((doc) => (doc.data()['workerId'] as String? ?? '') == uid)
        .map((doc) => doc.data()['offerId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<File> _compressOfferImageIfNeeded(File imageFile) async {
    final bytes = await imageFile.length();
    if (bytes <= 5 * 1024 * 1024) return imageFile;

    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/offer_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      imageFile.absolute.path,
      targetPath,
      quality: 82,
      minWidth: 1600,
      minHeight: 1600,
    );
    return result != null ? File(result.path) : imageFile;
  }

  static double _distanceKm(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(endLat - startLat);
    final dLng = _toRadians(endLng - startLng);
    final a =
        pow(sin(dLat / 2), 2) +
        cos(_toRadians(startLat)) *
            cos(_toRadians(endLat)) *
            pow(sin(dLng / 2), 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;

  static String _slugify(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    return normalized.replaceAll(RegExp(r'^_+|_+$'), '').isEmpty
        ? 'worker'
        : normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

class AlreadyAppliedException implements Exception {
  @override
  String toString() => 'Vous avez déjà postulé à cette offre.';
}

class AddressRequiredException implements Exception {
  const AddressRequiredException();
}

class WorkerOffer {
  const WorkerOffer({
    required this.id,
    required this.workerId,
    required this.title,
    required this.description,
    required this.selectedSpecialty,
    required this.status,
    required this.visibleToManagers,
    required this.isPromotion,
    required this.isAvailableNow,
    required this.currency,
    required this.rateUnit,
    required this.viewCount,
    required this.contactCount,
    this.imageUrl,
    this.imageStoragePath,
    this.regularRate,
    this.originalRate,
    this.promotionalRate,
    this.discountPercent,
    this.createdAt,
  });

  final String id;
  final String workerId;
  final String title;
  final String description;
  final String selectedSpecialty;
  final String status;
  final bool visibleToManagers;
  final bool isPromotion;
  final bool isAvailableNow;
  final String currency;
  final String rateUnit;
  final int viewCount;
  final int contactCount;
  final String? imageUrl;
  final String? imageStoragePath;
  final double? regularRate;
  final double? originalRate;
  final double? promotionalRate;
  final int? discountPercent;
  final DateTime? createdAt;

  factory WorkerOffer.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return WorkerOffer(
      id: doc.id,
      workerId: data['workerId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      selectedSpecialty: data['selectedSpecialty'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      visibleToManagers: data['visibleToManagers'] != false,
      isPromotion: data['isPromotion'] == true,
      isAvailableNow: data['isAvailableNow'] == true,
      currency: data['currency'] as String? ?? r'$',
      rateUnit: data['rateUnit'] as String? ?? 'hour',
      viewCount: (data['viewCount'] as num?)?.toInt() ?? 0,
      contactCount: (data['contactCount'] as num?)?.toInt() ?? 0,
      imageUrl: VpsMediaService.normalizeMediaUrlSync(
        data['imageUrl'] as String?,
      ),
      imageStoragePath: data['imageStoragePath'] as String?,
      regularRate: (data['regularRate'] as num?)?.toDouble(),
      originalRate: (data['originalRate'] as num?)?.toDouble(),
      promotionalRate: (data['promotionalRate'] as num?)?.toDouble(),
      discountPercent: (data['discountPercent'] as num?)?.toInt(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  double? get effectiveRate => promotionalRate ?? regularRate ?? originalRate;
}

class WorkerProfile {
  const WorkerProfile({
    required this.uid,
    required this.username,
    required this.department,
    required this.specialties,
    required this.isAvailable,
    this.photoBase64,
    this.photoUrl,
    this.address = '',
    this.addressLatitude,
    this.addressLongitude,
    this.availableWeekDays = const <int>[],
    this.availabilitySlots = const <Map<String, dynamic>>[],
    this.city,
    this.region,
    this.profileCompleted,
    this.termsAccepted,
  });

  final String uid;
  final String username;
  final String department;
  final List<String> specialties;
  final bool isAvailable;
  final String? photoBase64;
  final String? photoUrl;
  final String address;
  final double? addressLatitude;
  final double? addressLongitude;
  final List<int> availableWeekDays;
  final List<Map<String, dynamic>> availabilitySlots;
  final String? city;
  final String? region;
  final bool? profileCompleted;
  final bool? termsAccepted;

  String get initials {
    final parts = username
        .split(' ')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  factory WorkerProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final address = (data['address'] as String? ?? '').trim();
    final city = _extractAddressPart(address, offsetFromEnd: 3);
    final region = _extractAddressPart(address, offsetFromEnd: 2);

    return WorkerProfile(
      uid: doc.id,
      username:
          ((data['username'] as String?)?.trim().isNotEmpty == true
              ? data['username'] as String
              : ((data['name'] as String?)?.trim().isNotEmpty == true
                    ? data['name'] as String
                    : 'Utilisateur')),
      department: data['department'] as String? ?? '',
      specialties: _stringList(data['specialties']),
      isAvailable: data['isAvailable'] == true,
      photoBase64: data['photoBase64'] as String?,
      photoUrl: VpsMediaService.resolveProfileImageUrl(data),
      address: address,
      addressLatitude: (data['addressLatitude'] as num?)?.toDouble(),
      addressLongitude: (data['addressLongitude'] as num?)?.toDouble(),
      availableWeekDays: _intList(data['availableWeekDays']),
      availabilitySlots: _mapList(data['availabilitySlots']),
      city: city,
      region: region,
      profileCompleted: data['profileCompleted'] as bool?,
      termsAccepted: data['termsAccepted'] as bool?,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static List<int> _intList(dynamic value) {
    if (value is Iterable) {
      return value.map((item) => (item as num?)?.toInt() ?? 0).toList();
    }
    return const [];
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is Iterable) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const [];
  }

  static String? _extractAddressPart(
    String address, {
    required int offsetFromEnd,
  }) {
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < offsetFromEnd) return null;
    return parts[parts.length - offsetFromEnd];
  }
}
