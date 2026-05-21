import 'package:cloud_firestore/cloud_firestore.dart';

/// Urgency level as stored in Firestore field "urgency".
enum OfferUrgency { normal, high, urgent, veryUrgent }

/// Status as stored in Firestore field "status".
enum OfferStatus { open, assigned, completed, cancelled }

class ManagerOffer {
  const ManagerOffer({
    required this.id,
    required this.createdByManagerId,
    required this.createdByManagerName,
    required this.condoId,
    required this.condoName,
    required this.title,
    required this.description,
    required this.department,
    required this.specialty,
    required this.requestedDate,
    required this.requestedTime,
    required this.estimatedDuration,
    required this.urgency,
    required this.budgetAmount,
    required this.budgetCurrency,
    required this.isNegotiable,
    required this.status,
    required this.proposalCount,
    required this.createdAt,
    this.managerPhotoBase64,
    this.condoAddress,
    this.condoImageBase64,
    this.assignedWorkerId,
    this.updatedAt,
    this.latitude,
    this.longitude,
    this.managerPhotoUrl,
    this.condoImageUrl,
  });

  final String id;
  final String createdByManagerId;
  final String createdByManagerName;
  final String? managerPhotoBase64;
  final String? managerPhotoUrl;
  final String condoId;
  final String condoName;
  final String? condoAddress;
  final String? condoImageBase64;
  final String? condoImageUrl;
  final String title;
  final String description;
  final String department;
  final String specialty;
  final String requestedDate;
  final String requestedTime;
  final String estimatedDuration;
  final OfferUrgency urgency;
  final double budgetAmount;
  final String budgetCurrency;
  final bool isNegotiable;
  final OfferStatus status;
  final int proposalCount;
  final String? assignedWorkerId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final double? latitude;
  final double? longitude;

  bool get isUrgent =>
      urgency == OfferUrgency.urgent || urgency == OfferUrgency.veryUrgent;

  factory ManagerOffer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ManagerOffer(
      id: doc.id,
      createdByManagerId: data['createdByManagerId'] as String? ?? '',
      createdByManagerName:
          data['createdByManagerName'] as String? ?? 'Gestionnaire',
      managerPhotoBase64: data['managerPhotoBase64'] as String?,
      managerPhotoUrl: data['managerPhotoUrl'] as String?,
      condoId: data['condoId'] as String? ?? '',
      condoName: data['condoName'] as String? ?? '',
      condoAddress: data['condoAddress'] as String?,
      condoImageBase64: data['condoImageBase64'] as String?,
      condoImageUrl:
          data['condoImageUrl'] as String? ?? data['imageUrl'] as String?,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      department: data['department'] as String? ?? '',
      specialty: data['specialty'] as String? ?? '',
      requestedDate: data['requestedDate'] as String? ?? '',
      requestedTime: data['requestedTime'] as String? ?? '',
      estimatedDuration: data['estimatedDuration'] as String? ?? '',
      urgency: _parseUrgency(data['urgency']),
      budgetAmount: (data['budgetAmount'] as num?)?.toDouble() ?? 0.0,
      budgetCurrency: data['budgetCurrency'] as String? ?? 'DZD',
      isNegotiable: data['isNegotiable'] == true,
      status: _parseStatus(data['status']),
      proposalCount: (data['proposalCount'] as num?)?.toInt() ?? 0,
      assignedWorkerId: data['assignedWorkerId'] as String?,
      createdAt: _toDateTime(data['createdAt']) ?? DateTime.now(),
      updatedAt: _toDateTime(data['updatedAt']),
      latitude:
          (data['condoLatitude'] as num?)?.toDouble() ??
          (data['latitude'] as num?)?.toDouble(),
      longitude:
          (data['condoLongitude'] as num?)?.toDouble() ??
          (data['longitude'] as num?)?.toDouble(),
    );
  }

  static OfferUrgency _parseUrgency(dynamic raw) {
    switch (raw?.toString()) {
      case 'high':
        return OfferUrgency.high;
      case 'urgent':
        return OfferUrgency.urgent;
      case 'very_urgent':
        return OfferUrgency.veryUrgent;
      default:
        return OfferUrgency.normal;
    }
  }

  static OfferStatus _parseStatus(dynamic raw) {
    switch (raw?.toString()) {
      case 'assigned':
        return OfferStatus.assigned;
      case 'completed':
        return OfferStatus.completed;
      case 'cancelled':
        return OfferStatus.cancelled;
      default:
        return OfferStatus.open;
    }
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
