import 'package:cloud_firestore/cloud_firestore.dart';

class TaskModel {
  const TaskModel({
    required this.id,
    required this.title,
    required this.instruction,
    required this.status,
    required this.createdById,
    required this.createdByName,
    required this.createdAt,
    this.assignedToId,
    this.assignedToName,
    this.assignedMemberIds = const <String>[],
    this.assignedMemberNames = const <String, String>{},
    this.acceptedBy,
    this.acceptedByName,
    this.acceptedAt,
    this.completedBy = const <String>[],
    this.completedByNames = const <String, String>{},
    this.completedAt,
    this.deletedAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String instruction;
  final String status; // 'open' | 'accepted' | 'completed'
  final String createdById;
  final String createdByName;
  final DateTime createdAt;
  final String? assignedToId;
  final String? assignedToName;
  final List<String> assignedMemberIds;
  final Map<String, String> assignedMemberNames;
  final String? acceptedBy;
  final String? acceptedByName;
  final DateTime? acceptedAt;
  final List<String> completedBy;
  final Map<String, String> completedByNames;
  final DateTime? completedAt;
  final DateTime? deletedAt;
  final DateTime? updatedAt;

  bool get isGroupAssignment => assignedMemberIds.isNotEmpty;
  bool get isDeleted => status == 'deleted' || deletedAt != null;

  int get assigneeCount {
    if (assignedMemberIds.isNotEmpty) return assignedMemberIds.length;
    return (assignedToId?.trim().isNotEmpty ?? false) ? 1 : 0;
  }

  int get completedCount => completedBy.length;

  bool get isFullyCompleted =>
      assigneeCount > 0 && completedCount >= assigneeCount;

  String get progressLabel {
    if (assigneeCount <= 0) return '';
    return '$completedCount/$assigneeCount';
  }

  static List<String> _readStringList(dynamic value) {
    if (value is List) {
      return value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
    }
    if (value == null) return const <String>[];
    final single = value.toString().trim();
    return single.isEmpty ? const <String>[] : <String>[single];
  }

  factory TaskModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    DateTime tsToDate(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.now();
    DateTime? tsToDateOpt(dynamic v) => v is Timestamp ? v.toDate() : null;
    final assignedMemberNamesRaw = d['assignedMemberNames'];
    final completedByNamesRaw = d['completedByNames'];
    return TaskModel(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      instruction: (d['instruction'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'open',
      createdById: (d['createdById'] as String?) ?? '',
      createdByName: (d['createdByName'] as String?) ?? '',
      createdAt: tsToDate(d['createdAt']),
      assignedToId: d['assignedToId'] as String?,
      assignedToName: d['assignedToName'] as String?,
      assignedMemberIds: _readStringList(d['assignedMemberIds']),
      assignedMemberNames: assignedMemberNamesRaw is Map
          ? assignedMemberNamesRaw.map(
              (key, value) =>
                  MapEntry(key.toString(), value?.toString().trim() ?? ''),
            )
          : const <String, String>{},
      acceptedBy: d['acceptedBy'] as String?,
      acceptedByName: d['acceptedByName'] as String?,
      acceptedAt: tsToDateOpt(d['acceptedAt']),
      completedBy: _readStringList(d['completedBy']),
      completedByNames: completedByNamesRaw is Map
          ? completedByNamesRaw.map(
              (key, value) =>
                  MapEntry(key.toString(), value?.toString().trim() ?? ''),
            )
          : const <String, String>{},
      completedAt: tsToDateOpt(d['completedAt']),
      deletedAt: tsToDateOpt(d['deletedAt']),
      updatedAt: tsToDateOpt(d['updatedAt']),
    );
  }
}
