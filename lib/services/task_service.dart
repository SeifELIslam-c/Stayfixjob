import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:stayfix_job/models/task_model.dart';

class TaskService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _tasks(String conversationId) =>
      _db.collection('conversations').doc(conversationId).collection('tasks');

  CollectionReference<Map<String, dynamic>> _messages(String conversationId) =>
      _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages');

  List<String> _readStringList(dynamic value) {
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

  Future<void> _postMissionSystemMessage(
    String conversationId, {
    required String text,
    required String event,
    required Map<String, dynamic> metadata,
  }) async {
    await _messages(conversationId).add({
      'senderId': '',
      'senderName': 'Systeme',
      'text': text,
      'type': 'system',
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': const <String>[],
      'deliveredTo': const <String>[],
      'metadata': {'event': event, ...metadata},
    });
    await _db.collection('conversations').doc(conversationId).set({
      'systemBannerText': text,
      'systemBannerAt': FieldValue.serverTimestamp(),
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<TaskModel>> tasksStream(String conversationId) {
    return _tasks(conversationId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => TaskModel.fromFirestore(d)).toList(),
        );
  }

  Future<void> createTask({
    required String conversationId,
    required String title,
    required String instruction,
    required String createdById,
    required String createdByName,
    String? assignedToId,
    String? assignedToName,
    List<String> assignedMemberIds = const <String>[],
    Map<String, String> assignedMemberNames = const <String, String>{},
  }) async {
    final cleanAssignedIds = assignedMemberIds
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList();
    final isGroupAssignment = cleanAssignedIds.isNotEmpty;
    final taskRef = await _tasks(conversationId).add({
      'title': title,
      'instruction': instruction,
      'status': isGroupAssignment ? 'open' : 'open',
      'createdById': createdById,
      'createdByName': createdByName,
      'assignedToId': assignedToId,
      'assignedToName': assignedToName,
      'assignedMemberIds': cleanAssignedIds,
      'assignedMemberNames': assignedMemberNames,
      'completedBy': <String>[],
      'completedByNames': <String, String>{},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final resolvedAssignedNames = isGroupAssignment
        ? assignedMemberNames
        : <String, String>{
            if ((assignedToId ?? '').trim().isNotEmpty)
              assignedToId!.trim(): (assignedToName ?? '').trim(),
          };
    await _postMissionSystemMessage(
      conversationId,
      text: 'Nouvelle mission: $title',
      event: 'mission_created',
      metadata: {
        'taskId': taskRef.id,
        'title': title,
        'instruction': instruction,
        'assignedMemberIds': isGroupAssignment
            ? cleanAssignedIds
            : <String>[
                if ((assignedToId ?? '').trim().isNotEmpty)
                  assignedToId!.trim(),
              ],
        'assignedMemberNames': resolvedAssignedNames,
        'createdById': createdById,
        'createdByName': createdByName,
      },
    );
  }

  Future<void> acceptTask(
    String conversationId,
    String taskId,
    String uid,
    String userName,
  ) {
    return _tasks(conversationId).doc(taskId).update({
      'status': 'accepted',
      'acceptedBy': uid,
      'acceptedByName': userName,
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeTask(
    String conversationId,
    String taskId, {
    String? uid,
    String? userName,
  }) async {
    final taskRef = _tasks(conversationId).doc(taskId);
    var shouldPostSystemMessage = false;
    var completionEvent = 'mission_completed';
    var systemText = '';
    var systemMetadata = <String, dynamic>{};
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(taskRef);
      final data = snapshot.data() ?? <String, dynamic>{};
      final assignedMemberIds = _readStringList(
        data['assignedMemberIds'],
      ).toSet().toList();

      if (assignedMemberIds.isEmpty) {
        transaction.update(taskRef, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        shouldPostSystemMessage = true;
        systemText = 'Mission terminee: ${(data['title'] as String?) ?? ''}';
        systemMetadata = {
          'taskId': taskId,
          'title': (data['title'] as String?) ?? '',
          'instruction': (data['instruction'] as String?) ?? '',
          'assignedMemberIds': <String>[
            if (((data['assignedToId'] as String?) ?? '').trim().isNotEmpty)
              (data['assignedToId'] as String).trim(),
          ],
          'assignedMemberNames': <String, String>{
            if (((data['assignedToId'] as String?) ?? '').trim().isNotEmpty)
              (data['assignedToId'] as String).trim():
                  ((data['assignedToName'] as String?) ?? '').trim(),
          },
          'completedBy': <String>[
            if ((uid ?? '').trim().isNotEmpty) uid!.trim(),
          ],
          'completedByNames': <String, String>{
            if ((uid ?? '').trim().isNotEmpty)
              uid!.trim(): (userName ?? '').trim(),
          },
          'progressLabel': '1/1',
        };
        return;
      }

      final workerId = uid?.trim() ?? '';
      if (workerId.isEmpty || !assignedMemberIds.contains(workerId)) {
        throw StateError('worker-not-assigned');
      }

      final completedBy = _readStringList(data['completedBy']).toSet();
      if (completedBy.contains(workerId)) return;

      completedBy.add(workerId);
      final completedByNamesRaw = data['completedByNames'];
      final completedByNames = completedByNamesRaw is Map
          ? completedByNamesRaw.map(
              (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
            )
          : <String, String>{};
      if ((userName ?? '').trim().isNotEmpty) {
        completedByNames[workerId] = userName!.trim();
      }

      final update = <String, dynamic>{
        'completedBy': completedBy.toList(),
        'completedByNames': completedByNames,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      shouldPostSystemMessage = true;
      completionEvent = completedBy.length >= assignedMemberIds.length
          ? 'mission_completed'
          : 'mission_progress';
      if (completedBy.length >= assignedMemberIds.length) {
        update['status'] = 'completed';
        update['completedAt'] = FieldValue.serverTimestamp();
      }
      final title = (data['title'] as String?) ?? '';
      systemText = completionEvent == 'mission_completed'
          ? 'Mission terminee: $title'
          : 'Progression mission: $title';
      systemMetadata = {
        'taskId': taskId,
        'title': title,
        'instruction': (data['instruction'] as String?) ?? '',
        'assignedMemberIds': assignedMemberIds,
        'assignedMemberNames': data['assignedMemberNames'] is Map
            ? Map<String, String>.from(
                (data['assignedMemberNames'] as Map).map(
                  (key, value) =>
                      MapEntry(key.toString(), value?.toString() ?? ''),
                ),
              )
            : <String, String>{},
        'completedBy': completedBy.toList(),
        'completedByNames': completedByNames,
        'progressLabel': '${completedBy.length}/${assignedMemberIds.length}',
      };
      transaction.update(taskRef, update);
    });
    if (!shouldPostSystemMessage) return;
    await _postMissionSystemMessage(
      conversationId,
      text: systemText,
      event: completionEvent,
      metadata: systemMetadata,
    );
  }

  Future<void> deleteTask(String conversationId, String taskId) async {
    final taskRef = _tasks(conversationId).doc(taskId);
    final snapshot = await taskRef.get();
    final data = snapshot.data() ?? <String, dynamic>{};
    await taskRef.update({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _postMissionSystemMessage(
      conversationId,
      text: 'Mission supprimee: ${(data['title'] as String?) ?? ''}',
      event: 'mission_removed',
      metadata: {
        'taskId': taskId,
        'title': (data['title'] as String?) ?? '',
        'instruction': (data['instruction'] as String?) ?? '',
        'assignedMemberIds': _readStringList(data['assignedMemberIds']),
        'assignedMemberNames': data['assignedMemberNames'] is Map
            ? Map<String, String>.from(
                (data['assignedMemberNames'] as Map).map(
                  (key, value) =>
                      MapEntry(key.toString(), value?.toString() ?? ''),
                ),
              )
            : <String, String>{},
      },
    );
  }
}
