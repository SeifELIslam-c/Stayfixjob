import 'package:cloud_firestore/cloud_firestore.dart';

class OfferApplication {
  const OfferApplication({
    required this.offerId,
    required this.workerId,
    required this.managerId,
    required this.workerName,
    required this.workerDepartment,
    required this.workerSpecialties,
    required this.status,
    required this.createdAt,
    this.workerPhotoBase64,
    this.message,
    this.proposedPrice,
  });

  final String offerId;
  final String workerId;
  final String managerId;
  final String workerName;
  final String workerDepartment;
  final List<String> workerSpecialties;
  final String? workerPhotoBase64;
  final String status; // always "pending" on creation
  final String? message;
  final double? proposedPrice;
  final DateTime createdAt;

  Map<String, dynamic> toFirestore() {
    return {
      'offerId': offerId,
      'workerId': workerId,
      'managerId': managerId,
      'workerName': workerName,
      'workerDepartment': workerDepartment,
      'workerSpecialties': workerSpecialties,
      if (workerPhotoBase64 != null) 'workerPhotoBase64': workerPhotoBase64,
      'status': status,
      if (message != null) 'message': message,
      if (proposedPrice != null) 'proposedPrice': proposedPrice,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
