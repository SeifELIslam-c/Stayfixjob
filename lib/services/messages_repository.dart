import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'vps_media_service.dart';

class MessagesRepository {
  MessagesRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Map<String, ProfileSummary?> _profileCache =
      <String, ProfileSummary?>{};
  final Map<String, Future<ProfileSummary?>> _profileRequestCache =
      <String, Future<ProfileSummary?>>{};

  static const String _threadsCollectionName = 'conversations';
  static const String _itemsSubcollectionName = 'messages';

  String? get currentUserId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _threadsCollection =>
      _firestore.collection(_threadsCollectionName);

  Stream<List<ConversationSeed>> watchConversationSeeds(String userId) {
    return _threadsCollection.snapshots().map((snapshot) {
      final merged = <String, ConversationSeed>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final participants = _stringList(data['participants']);
        final workerId = _stringOrNull(data['workerId']);
        if (!participants.contains(userId) && workerId != userId) {
          continue;
        }
        merged[doc.id] = ConversationSeed(id: doc.id, data: data);
      }
      return merged.values.toList(growable: false);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
    String conversationId,
  ) {
    return _threadsCollection
        .doc(conversationId)
        .collection(_itemsSubcollectionName)
        .orderBy('createdAt')
        .snapshots();
  }

  Future<ProfileSummary?> loadCurrentProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final profile = await _loadProfile(uid);
    if (profile != null) return profile;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final fallbackName = user.displayName?.trim();
    return ProfileSummary(
      userId: uid,
      name: (fallbackName?.isNotEmpty == true) ? fallbackName! : 'Intervenant',
      photoUrl: user.photoURL,
      email: user.email,
    );
  }

  Future<String> ensureWorkerManagerConversation({
    required String managerId,
    required String managerName,
    required String managerSubtitle,
    String? managerPhotoUrl,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      throw StateError('Utilisateur non connecte');
    }

    final snapshot = await _threadsCollection
        .where('participants', arrayContains: uid)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final participants = _stringList(data['participants']);
      final workerId = _stringOrNull(data['workerId']);
      final storedManagerId = _stringOrNull(data['managerId']);
      if (participants.contains(managerId) &&
          (workerId == null || workerId == uid) &&
          (storedManagerId == null || storedManagerId == managerId)) {
        await doc.reference.set({
          'title': managerName,
          'subtitle': managerSubtitle,
          'photoUrl': managerPhotoUrl ?? '',
          'workerId': uid,
          'managerId': managerId,
          'type': 'intervenant',
          'isActive': true,
        }, SetOptions(merge: true));
        return doc.id;
      }
    }

    final ref = _threadsCollection.doc();
    await ref.set({
      'type': 'intervenant',
      'title': managerName,
      'subtitle': managerSubtitle,
      'participants': <String>[uid, managerId],
      'workerId': uid,
      'managerId': managerId,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadBy': <String, int>{uid: 0, managerId: 0},
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'isActive': true,
      'blockedBy': <String>[],
      'blockedParticipantIds': <String>[],
      'photoUrl': managerPhotoUrl ?? '',
    });
    return ref.id;
  }

  Future<List<ProfileSummary>> loadEligibleGroupParticipants() async {
    final uid = currentUserId;
    if (uid == null) return const <ProfileSummary>[];

    final snapshot = await _threadsCollection
        .where('participants', arrayContains: uid)
        .get();

    final seen = <String>{};
    final participantIds = <String>[];

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = _resolveConversationType(data);
      if (type == 'team' || type == 'group' || type == 'system') continue;

      for (final participantId in _stringList(data['participants'])) {
        if (participantId == uid || !seen.add(participantId)) continue;
        participantIds.add(participantId);
      }
    }

    final participants = await _loadProfiles(participantIds);

    participants.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return participants;
  }

  Future<String> createGroupConversation({
    required String groupName,
    required List<String> participantIds,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Utilisateur non connecte');

    final trimmedName = groupName.trim();
    if (trimmedName.isEmpty) {
      throw StateError('Le nom du groupe est requis');
    }

    final creatorProfile = await loadCurrentProfile();
    final participants = <String>{uid, ...participantIds}.toList();
    final unreadBy = <String, int>{for (final id in participants) id: 0};
    final threadRef = _threadsCollection.doc();
    final now = FieldValue.serverTimestamp();

    await threadRef.set({
      'type': 'team',
      'title': trimmedName,
      'subtitle': 'Equipe',
      'participants': participants,
      'createdBy': uid,
      'createdAt': now,
      'updatedAt': now,
      'lastMessage': 'Groupe cree',
      'lastMessageAt': now,
      'unreadBy': unreadBy,
      'memberCount': participants.length,
      'blockedParticipantIds': <String>[],
      'blockedBy': <String>[],
      'isActive': true,
    });

    await threadRef.collection(_itemsSubcollectionName).add({
      'senderId': uid,
      'senderName': creatorProfile?.name ?? 'Utilisateur',
      'senderRole': creatorProfile?.roleLabel,
      'senderAccountType': creatorProfile?.accountType,
      'senderPhotoUrl': creatorProfile?.photoUrl,
      'senderPhotoBase64': creatorProfile?.photoBase64,
      'text': '${creatorProfile?.name ?? 'Utilisateur'} a cree le groupe.',
      'type': 'system',
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': [uid],
      'deliveredTo': [uid],
      'metadata': {'event': 'group_created', 'groupName': trimmedName},
    });

    return threadRef.id;
  }

  Future<ConversationSummary> hydrateConversation({
    required String currentUserId,
    required String conversationId,
    required Map<String, dynamic> data,
  }) async {
    final participants = _stringList(data['participants']);
    final resolvedOtherParticipantId = _resolveOtherParticipantId(
      data: data,
      currentUserId: currentUserId,
      participants: participants,
    );
    final otherParticipantIds = resolvedOtherParticipantId == null
        ? participants
              .where((participantId) => participantId != currentUserId)
              .toList()
        : <String>[resolvedOtherParticipantId];
    final type = _resolveConversationType(data);
    final managerId = _stringOrNull(data['managerId']);
    final workerId = _stringOrNull(data['workerId']);
    final isWorkerDirectView =
        type != 'team' &&
        type != 'group' &&
        workerId == currentUserId &&
        managerId != null &&
        managerId.isNotEmpty;

    ProfileSummary? otherProfile;
    List<ProfileSummary> memberProfiles = const <ProfileSummary>[];

    if (type == 'team' || type == 'group') {
      memberProfiles = await _loadProfiles(otherParticipantIds);
    } else if (isWorkerDirectView) {
      otherProfile = await _resolveWorkerManagerProfile(data);
    } else if (otherParticipantIds.isNotEmpty) {
      otherProfile = await _loadProfile(otherParticipantIds.first);
    }

    final latestMessage = _shouldLoadLatestMessageFallback(data)
        ? await _loadLatestMessageFallback(conversationId)
        : null;
    final unreadCount = _unreadCountForUser(data['unreadBy'], currentUserId);
    final title = _resolveConversationTitle(
      data: data,
      type: type,
      otherProfile: otherProfile,
      members: memberProfiles,
    );
    final subtitle = _resolveConversationSubtitle(
      data: data,
      type: type,
      otherProfile: otherProfile,
      membersCount: participants.length,
    );
    final preview = _firstNonEmptyString([
      data['lastMessage'],
      latestMessage?.previewText,
      data['systemBannerText'],
      data['preview'],
    ]);

    final effectivePreview = preview.isNotEmpty
        ? preview
        : _defaultConversationPreview(
            data: data,
            currentUserId: currentUserId,
            type: type,
          );

    return ConversationSummary(
      id: conversationId,
      type: type,
      title: title.isEmpty ? 'Conversation' : title,
      subtitle: subtitle,
      preview: effectivePreview,
      unreadCount: unreadCount,
      otherParticipantId: otherParticipantIds.isNotEmpty
          ? otherParticipantIds.first
          : null,
      otherProfile: otherProfile,
      memberProfiles: memberProfiles,
      participantIds: participants,
      blockedParticipantIds: _stringList(
        data['blockedParticipantIds'] ?? data['blockedBy'],
      ),
      updatedAt:
          _timestampToDateTime(
            data['lastMessageAt'] ?? data['updatedAt'] ?? data['createdAt'],
          ) ??
          latestMessage?.createdAt,
      lastMessageAt: _timestampToDateTime(data['lastMessageAt']),
      contextTitle: _firstNonEmptyString([
        data['propertyName'],
        data['offerTitle'],
        data['relatedTitle'],
      ]),
      contextSubtitle: _firstNonEmptyString([
        data['propertyAddress'],
        data['offerLocation'],
        data['contextSubtitle'],
      ]),
      relatedOfferId: _stringOrNull(data['relatedOfferId'] ?? data['offerId']),
      relatedPropertyId: _stringOrNull(
        data['relatedPropertyId'] ?? data['propertyId'],
      ),
      rawData: data,
    );
  }

  Future<ConversationSummary> loadConversationSummary(
    String conversationId,
  ) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Utilisateur non connecte');

    final doc = await _threadsCollection.doc(conversationId).get();
    if (!doc.exists || doc.data() == null) {
      throw StateError('Conversation introuvable');
    }

    return hydrateConversation(
      currentUserId: uid,
      conversationId: conversationId,
      data: doc.data()!,
    );
  }

  Future<void> markConversationAsRead(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _threadsCollection.doc(conversationId).update({
      'unreadBy.$uid': 0,
      'lastReadAt.$uid': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final unreadSnapshot = await _threadsCollection
        .doc(conversationId)
        .collection(_itemsSubcollectionName)
        .get();
    if (unreadSnapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unreadSnapshot.docs) {
      final data = doc.data();
      if (data['senderId'] == uid) continue;
      batch.set(doc.reference, {
        'deliveredTo': FieldValue.arrayUnion([uid]),
        'seenBy': FieldValue.arrayUnion([uid]),
        'seenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> touchLastReadAt(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await _threadsCollection.doc(conversationId).update({
        'unreadBy.$uid': 0,
        'lastReadAt.$uid': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> sendTextMessage({
    required String conversationId,
    required String text,
  }) async {
    final uid = currentUserId;
    final trimmed = text.trim();
    if (uid == null || trimmed.isEmpty) return;
    final currentProfile = await loadCurrentProfile();
    await sendConversationMessage(
      conversationId: conversationId,
      messageData: {
        'type': 'text',
        'text': trimmed,
        'senderName': currentProfile?.name ?? 'Utilisateur',
        'senderRole': currentProfile?.roleLabel,
        'senderAccountType': currentProfile?.accountType,
        'senderPhotoUrl': currentProfile?.photoUrl,
        'senderPhotoBase64': currentProfile?.photoBase64,
        'seenAt': FieldValue.serverTimestamp(),
      },
      lastMessage: trimmed,
    );
  }

  Future<void> sendConversationMessage({
    required String conversationId,
    required Map<String, dynamic> messageData,
    required String lastMessage,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    final conversationRef = _threadsCollection.doc(conversationId);
    final conversationSnapshot = await conversationRef.get();
    final conversationData =
        conversationSnapshot.data() ?? const <String, dynamic>{};
    final participants = _stringList(conversationData['participants']);
    final messagesRef = conversationRef.collection(_itemsSubcollectionName);
    final messageRef = messagesRef.doc();
    final batch = _firestore.batch();

    final cleanMessageData = <String, dynamic>{
      for (final entry in messageData.entries)
        if (entry.value != null) entry.key: entry.value,
    };

    batch.set(messageRef, <String, dynamic>{
      ...cleanMessageData,
      'senderId': uid,
      'deliveredTo': [uid],
      'seenBy': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.set(conversationRef, {
      'lastMessage': lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadBy.$uid': 0,
      'lastReadAt.$uid': FieldValue.serverTimestamp(),
      for (final participantId in participants)
        if (participantId != uid)
          'unreadBy.$participantId': FieldValue.increment(1),
      'systemBannerText': FieldValue.delete(),
      'systemBannerAt': FieldValue.delete(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> deleteMessagePermanently({
    required String conversationId,
    required String messageId,
  }) async {
    final threadRef = _threadsCollection.doc(conversationId);
    final messageRef = threadRef
        .collection(_itemsSubcollectionName)
        .doc(messageId);
    final message = await messageRef.get();
    final data = message.data() ?? const <String, dynamic>{};
    final fileIds = _stringList(data['fileIds']);

    await messageRef.delete();
    if (fileIds.isNotEmpty) {
      await VpsMediaService.deleteFiles(fileIds);
    }

    final latestSnapshot = await threadRef
        .collection(_itemsSubcollectionName)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (latestSnapshot.docs.isEmpty) {
      await threadRef.set({
        'lastMessage': '',
        'lastMessageAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final latest = MessageSummary.fromDocument(latestSnapshot.docs.first);
    await threadRef.set({
      'lastMessage': latest.previewText,
      'lastMessageAt': latest.createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(latest.createdAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteConversationPermanently(String conversationId) async {
    final threadRef = _threadsCollection.doc(conversationId);
    final snapshot = await threadRef.collection(_itemsSubcollectionName).get();
    final fileIds = <String>[];
    for (final doc in snapshot.docs) {
      fileIds.addAll(_stringList(doc.data()['fileIds']));
    }
    await _deleteSubcollection(threadRef.collection(_itemsSubcollectionName));
    await threadRef.delete();
    if (fileIds.isNotEmpty) {
      await VpsMediaService.deleteFiles(fileIds);
    }
  }

  Future<void> blockUser({
    required String conversationId,
    required String blockedUserId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _firestore.collection('profiles').doc(uid).set({
      'blockedUserIds': FieldValue.arrayUnion([blockedUserId]),
    }, SetOptions(merge: true));
    _clearProfileCache(uid);

    await _threadsCollection.doc(conversationId).set({
      'blockedParticipantIds': FieldValue.arrayUnion([blockedUserId, uid]),
      'blockedBy': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unblockUser({
    required String conversationId,
    required String unblockedUserId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _firestore.collection('profiles').doc(uid).set({
      'blockedUserIds': FieldValue.arrayRemove([unblockedUserId]),
    }, SetOptions(merge: true));
    _clearProfileCache(uid);

    await _threadsCollection.doc(conversationId).set({
      'blockedParticipantIds': FieldValue.arrayRemove([unblockedUserId, uid]),
      'blockedBy': FieldValue.arrayRemove([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> reportConversationAbuse({
    required String conversationId,
    required String reason,
    String details = '',
    String? messageId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Utilisateur non connecte');

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw StateError('Le motif du signalement est requis');
    }

    final threadSnapshot = await _threadsCollection.doc(conversationId).get();
    final threadData = threadSnapshot.data() ?? const <String, dynamic>{};
    final participants = _stringList(threadData['participants']);
    final reportedUserId = participants.firstWhere(
      (participantId) => participantId != uid,
      orElse: () => '',
    );

    await _firestore.collection('conversation_reports').add({
      'conversationId': conversationId,
      'messageId': messageId?.trim().isNotEmpty == true ? messageId!.trim() : null,
      'reportedBy': uid,
      'reportedUserId': reportedUserId,
      'reason': trimmedReason,
      'details': details.trim(),
      'conversationType': _stringOrNull(threadData['type']) ?? 'intervenant',
      'conversationTitle': _stringOrNull(threadData['title']) ?? '',
      'participants': participants,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  Future<ProfileSummary?> loadProfileById(String userId) =>
      _loadProfile(userId);

  Future<ProfileSummary?> _resolveWorkerManagerProfile(
    Map<String, dynamic> data,
  ) async {
    final managerId = _stringOrNull(data['managerId']);
    final managerProfile = managerId == null
        ? null
        : await _loadProfile(managerId);

    final managerDisplayName = _firstNonEmptyString([
      data['managerDisplayName'],
      managerProfile?.name,
      data['title'],
    ]);
    if (managerDisplayName.isEmpty) return managerProfile;

    final managerSubtitle = _firstNonEmptyString([
      data['managerSubtitle'],
      managerProfile?.roleLabel,
      data['subtitle'],
    ]);
    final managerPhotoUrl = _normalizeConversationMediaUrl(
      _firstNonEmptyString([
        data['managerPhotoUrl'],
        data['photoUrl'],
        managerProfile?.photoUrl,
      ]),
    );
    final managerPhotoBase64 = _firstNonEmptyString([
      data['managerPhotoBase64'],
      data['photoBase64'],
      managerProfile?.photoBase64,
    ]);

    return ProfileSummary(
      userId: managerId ?? managerProfile?.userId ?? '',
      name: managerDisplayName,
      department: managerSubtitle.isEmpty
          ? managerProfile?.department
          : managerSubtitle,
      specialties: const <String>[],
      blockedUserIds: managerProfile?.blockedUserIds ?? const <String>[],
      isAvailable: managerProfile?.isAvailable ?? false,
      photoBase64: managerPhotoBase64.isEmpty ? null : managerPhotoBase64,
      photoUrl: managerPhotoUrl.isEmpty ? null : managerPhotoUrl,
      phone: managerProfile?.phone,
      email: managerProfile?.email,
    );
  }

  Future<ProfileSummary?> _loadProfile(String userId) async {
    if (_profileCache.containsKey(userId)) {
      return _profileCache[userId];
    }

    final pendingRequest = _profileRequestCache[userId];
    if (pendingRequest != null) {
      return pendingRequest;
    }

    final request = _loadProfileFromFirestore(userId);
    _profileRequestCache[userId] = request;
    try {
      final profile = await request;
      _profileCache[userId] = profile;
      return profile;
    } finally {
      _profileRequestCache.remove(userId);
    }
  }

  Future<List<ProfileSummary>> _loadProfiles(List<String> ids) async {
    final profiles = await Future.wait(ids.map(_loadProfile));
    return profiles.whereType<ProfileSummary>().toList(growable: false);
  }

  Future<ProfileSummary?> _loadProfileFromFirestore(String userId) async {
    final snapshot = await _firestore.collection('profiles').doc(userId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;

    final data = snapshot.data()!;
    final userMeta =
        (await _firestore.collection('users').doc(userId).get()).data() ??
        const <String, dynamic>{};
    final authUser = FirebaseAuth.instance.currentUser;
    final authName = authUser != null && authUser.uid == userId
        ? authUser.displayName?.trim()
        : null;
    final authPhotoUrl = authUser != null && authUser.uid == userId
        ? authUser.photoURL
        : null;
    return ProfileSummary(
      userId: userId,
      name:
          _firstNonEmptyString([
            data['username'],
            data['name'],
            authName,
          ]).isEmpty
          ? 'Intervenant'
          : _firstNonEmptyString([data['username'], data['name'], authName]),
      department: _stringOrNull(data['department']),
      specialties: _stringList(data['specialties']),
      blockedUserIds: _stringList(data['blockedUserIds']),
      isAvailable: data['isAvailable'] == true,
      photoBase64: _stringOrNull(data['photoBase64']),
      photoUrl: VpsMediaService.resolveProfileImageUrl(data) ?? authPhotoUrl,
      phone: _stringOrNull(data['phone']),
      email: _stringOrNull(data['email']),
      accountType: _stringOrNull(
        userMeta['accountType'] ?? data['accountType'],
      ),
      stayfixBadgeLabel: _stringOrNull(data['stayfixBadgeLabel']),
      apartmentName: _stringOrNull(data['apartmentName']),
    );
  }

  void _clearProfileCache(String userId) {
    _profileCache.remove(userId);
    _profileRequestCache.remove(userId);
  }

  Future<MessageSummary?> _loadLatestMessageFallback(
    String conversationId,
  ) async {
    final snapshot = await _threadsCollection
        .doc(conversationId)
        .collection(_itemsSubcollectionName)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return MessageSummary.fromDocument(snapshot.docs.first);
  }

  Future<void> _deleteSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(200).get();
      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  static String _resolveConversationType(Map<String, dynamic> data) {
    final type = _stringOrNull(data['type'])?.toLowerCase();
    if (type != null && type.isNotEmpty) return type;
    if (data['memberCount'] != null) return 'team';
    if (data['relatedOfferId'] != null || data['offerId'] != null) {
      return 'mission';
    }
    if (data['workerId'] != null || data['managerId'] != null) {
      return 'direct';
    }
    return 'direct';
  }

  static String _resolveConversationTitle({
    required Map<String, dynamic> data,
    required String type,
    required ProfileSummary? otherProfile,
    required List<ProfileSummary> members,
  }) {
    if (type != 'team' && type != 'group' && otherProfile != null) {
      return otherProfile.name;
    }

    final directTitle = _firstNonEmptyString([
      data['title'],
      data['name'],
      otherProfile?.name,
    ]);
    if (directTitle.isNotEmpty) return directTitle;

    if (type == 'team' || type == 'group') {
      if (members.isNotEmpty) {
        return members.take(2).map((member) => member.name).join(', ');
      }
      return 'Equipe';
    }

    switch (type) {
      case 'mission':
        return 'Mission StayFix Job';
      default:
        return 'Conversation StayFix Job';
    }
  }

  static String _resolveConversationSubtitle({
    required Map<String, dynamic> data,
    required String type,
    required ProfileSummary? otherProfile,
    required int membersCount,
  }) {
    if (type == 'team' || type == 'group') {
      return 'Equipe · $membersCount membres';
    }

    final profileRole = otherProfile?.roleLabel ?? '';
    if (profileRole.isNotEmpty) return profileRole;

    final explicitSubtitle = _firstNonEmptyString([
      data['subtitle'],
      data['role'],
      data['contextType'],
    ]);
    if (explicitSubtitle.isNotEmpty) return explicitSubtitle;

    switch (type) {
      case 'mission':
        return 'Discussion de mission';
      default:
        return 'Canal direct';
    }
  }

  static String? _resolveOtherParticipantId({
    required Map<String, dynamic> data,
    required String currentUserId,
    required List<String> participants,
  }) {
    final managerId = _stringOrNull(data['managerId']);
    final workerId = _stringOrNull(data['workerId']);

    if (workerId != null &&
        managerId != null &&
        currentUserId == workerId &&
        managerId != currentUserId) {
      return managerId;
    }

    if (workerId != null &&
        managerId != null &&
        currentUserId == managerId &&
        workerId != currentUserId) {
      return workerId;
    }

    for (final participantId in participants) {
      if (participantId != currentUserId) return participantId;
    }
    return null;
  }

  static String _defaultConversationPreview({
    required Map<String, dynamic> data,
    required String currentUserId,
    required String type,
  }) {
    final workerId = _stringOrNull(data['workerId']);
    final managerId = _stringOrNull(data['managerId']);
    if (type != 'team' &&
        type != 'group' &&
        workerId == currentUserId &&
        managerId != null &&
        managerId.isNotEmpty) {
      return 'Un manager vous a choisi pour cette discussion.';
    }
    return 'Aucun message pour le moment';
  }

  static bool _shouldLoadLatestMessageFallback(Map<String, dynamic> data) {
    final storedPreview = _firstNonEmptyString([
      data['lastMessage'],
      data['systemBannerText'],
      data['preview'],
    ]);
    if (storedPreview.isEmpty) return true;

    final storedTimestamp = _timestampToDateTime(
      data['lastMessageAt'] ?? data['updatedAt'] ?? data['createdAt'],
    );
    return storedTimestamp == null;
  }

  static int _unreadCountForUser(dynamic unreadBy, String userId) {
    if (unreadBy is Map) {
      final value = unreadBy[userId];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static DateTime? _timestampToDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final stringValue = _stringOrNull(value);
      if (stringValue != null && stringValue.trim().isNotEmpty) {
        return stringValue.trim();
      }
    }
    return '';
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final stringValue = value.toString().trim();
    return stringValue.isEmpty ? null : stringValue;
  }

  static String _normalizeConversationMediaUrl(String value) {
    if (value.trim().isEmpty) return '';
    return VpsMediaService.normalizeMediaUrlSync(value);
  }

  static List<String> _stringList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  static List<int> _intList(dynamic value) {
    if (value is Iterable) {
      return value.map((item) => (item as num?)?.toInt() ?? 0).toList();
    }
    return const <int>[];
  }
}

class ConversationSeed {
  const ConversationSeed({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class ConversationSummary {
  ConversationSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.unreadCount,
    required this.rawData,
    this.otherParticipantId,
    this.otherProfile,
    this.memberProfiles = const <ProfileSummary>[],
    this.participantIds = const <String>[],
    this.blockedParticipantIds = const <String>[],
    this.updatedAt,
    this.lastMessageAt,
    this.contextTitle = '',
    this.contextSubtitle = '',
    this.relatedOfferId,
    this.relatedPropertyId,
  });

  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String preview;
  final int unreadCount;
  final String? otherParticipantId;
  final ProfileSummary? otherProfile;
  final List<ProfileSummary> memberProfiles;
  final List<String> participantIds;
  final List<String> blockedParticipantIds;
  final DateTime? updatedAt;
  final DateTime? lastMessageAt;
  final String contextTitle;
  final String contextSubtitle;
  final String? relatedOfferId;
  final String? relatedPropertyId;
  final Map<String, dynamic> rawData;

  bool get isMission =>
      type == 'mission' || relatedOfferId != null || relatedPropertyId != null;
  bool get isTeam => type == 'team' || type == 'group';
  bool get isDirect => !isTeam && !isMission;
  bool get isAvailable => otherProfile?.isAvailable == true;
  int get memberCount {
    final storedCount = rawData['memberCount'];
    if (storedCount is num) return storedCount.toInt();
    if (participantIds.isNotEmpty) return participantIds.length;
    return memberProfiles.length;
  }
}

class ProfileSummary {
  ProfileSummary({
    required this.userId,
    required this.name,
    this.department,
    this.specialties = const <String>[],
    this.blockedUserIds = const <String>[],
    this.isAvailable = false,
    this.photoBase64,
    this.photoUrl,
    this.phone,
    this.email,
    this.accountType,
    this.stayfixBadgeLabel,
    this.apartmentName,
  });

  final String userId;
  final String name;
  final String? department;
  final List<String> specialties;
  final List<String> blockedUserIds;
  final bool isAvailable;
  final String? photoBase64;
  final String? photoUrl;
  final String? phone;
  final String? email;
  final String? accountType;
  final String? stayfixBadgeLabel;
  final String? apartmentName;

  String get initials {
    final parts = name
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'S';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  String get roleLabel {
    if (specialties.isNotEmpty) return specialties.first;
    return department?.trim().isNotEmpty == true
        ? department!.trim()
        : 'Role non renseigne';
  }

  bool get isStayFixConcierge =>
      accountType == 'concierge' || accountType == 'stayfix_job';

  String get badgeLabel {
    if (stayfixBadgeLabel?.trim().isNotEmpty == true) {
      return stayfixBadgeLabel!.trim();
    }
    return roleLabel;
  }

  ImageProvider<Object>? get avatarImage {
    if (photoUrl?.isNotEmpty == true) {
      return NetworkImage(photoUrl!);
    }
    final base64 = photoBase64;
    if (base64 == null || base64.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(base64));
    } catch (_) {
      return null;
    }
  }
}

class MessageSummary {
  MessageSummary({
    required this.id,
    required this.text,
    required this.senderId,
    required this.type,
    this.createdAt,
    this.senderName,
    this.readBy = const <String>[],
    this.metadata = const <String, dynamic>{},
    this.imageUrl,
    this.audioUrl,
    this.address,
    this.deliveredTo = const <String>[],
    this.reaction,
    this.audioDurationMs,
    this.audioWaveform = const <int>[],
    this.fileIds = const <String>[],
  });

  factory MessageSummary.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return MessageSummary(
      id: doc.id,
      text: MessagesRepository._firstNonEmptyString([
        data['text'],
        data['message'],
      ]),
      senderId: MessagesRepository._firstNonEmptyString([data['senderId']]),
      senderName: MessagesRepository._stringOrNull(data['senderName']),
      type: MessagesRepository._firstNonEmptyString([data['type']]).isEmpty
          ? 'text'
          : MessagesRepository._firstNonEmptyString([data['type']]),
      createdAt: MessagesRepository._timestampToDateTime(data['createdAt']),
      readBy: MessagesRepository._stringList(data['seenBy']),
      metadata: data['metadata'] is Map<String, dynamic>
          ? data['metadata'] as Map<String, dynamic>
          : const <String, dynamic>{},
      imageUrl: MessagesRepository._stringOrNull(data['imageUrl']),
      audioUrl: MessagesRepository._stringOrNull(data['audioUrl']),
      address: MessagesRepository._stringOrNull(data['address']),
      deliveredTo: MessagesRepository._stringList(data['deliveredTo']),
      reaction: MessagesRepository._stringOrNull(data['reaction']),
      audioDurationMs: (data['audioDurationMs'] as num?)?.toInt(),
      audioWaveform: MessagesRepository._intList(data['audioWaveform']),
      fileIds: MessagesRepository._stringList(data['fileIds']),
    );
  }

  final String id;
  final String text;
  final String senderId;
  final String? senderName;
  final String type;
  final DateTime? createdAt;
  final List<String> readBy;
  final Map<String, dynamic> metadata;
  final String? imageUrl;
  final String? audioUrl;
  final String? address;
  final List<String> deliveredTo;
  final String? reaction;
  final int? audioDurationMs;
  final List<int> audioWaveform;
  final List<String> fileIds;

  bool get isImage => type == 'image' || (imageUrl?.isNotEmpty ?? false);
  bool get isAudio => type == 'audio' || (audioUrl?.isNotEmpty ?? false);
  bool get isAddress => type == 'address' || (address?.isNotEmpty ?? false);
  String get previewText {
    if (isImage) return 'Photo';
    if (isAudio) return 'Note vocale';
    if (isAddress) return 'Adresse partagee';
    return text;
  }
}
