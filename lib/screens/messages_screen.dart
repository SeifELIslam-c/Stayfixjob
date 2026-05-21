import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons_flutter.dart';

import '../services/messages_repository.dart';
import 'chat_detail_screen.dart';
import 'home_screen.dart';
import 'offers_screen.dart';
import 'profile_screen.dart';

const kMessagesBlue = Color(0xFF0F63FF);
const kMessagesDeepBlue = Color(0xFF2563EB);
const kMessagesPageBg = Color(0xFFF7FAFF);
const kMessagesText = Color(0xFF0F172A);
const kMessagesMuted = Color(0xFF64748B);
const kMessagesBody = Color(0xFF475569);
const kMessagesBorder = Color(0xFFE2E8F0);
const kMessagesSoftBlue = Color(0xFFEFF6FF);
const kMessagesCard = Colors.white;
const kMessagesSuccess = Color(0xFF22C55E);
const kMessagesWarning = Color(0xFFF97316);
const kMessagesDanger = Color(0xFFDC2626);

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final MessagesRepository _repository = MessagesRepository();
  final TextEditingController _searchController = TextEditingController();

  ProfileSummary? _currentProfile;
  bool _loadingProfile = true;
  bool _unreadOnly = false;
  _ConversationCategory _activeCategory = _ConversationCategory.all;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
    _searchController.addListener(_handleSearchChange);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChange)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProfile() async {
    final profile = await _repository.loadCurrentProfile();
    if (!mounted) return;
    setState(() {
      _currentProfile = profile;
      _loadingProfile = false;
    });
  }

  void _handleSearchChange() {
    if (mounted) setState(() {});
  }

  void _openHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen(requireAuth: false)),
    );
  }

  void _openOffers() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const OffersScreen()));
  }

  void _openProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7E4FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const Text(
                  'Filtres',
                  style: TextStyle(
                    color: kMessagesText,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  value: _unreadOnly,
                  activeThumbColor: kMessagesBlue,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Afficher uniquement les non lus',
                    style: TextStyle(
                      color: kMessagesText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Masque les conversations deja lues',
                    style: TextStyle(color: kMessagesMuted),
                  ),
                  onChanged: (value) {
                    setState(() => _unreadOnly = value);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openConversationActions(
    ConversationSummary conversation,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7E4FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                _SheetActionTile(
                  icon: LucideIcons.eye,
                  title: 'Ouvrir la conversation',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatDetailScreen(conversationId: conversation.id),
                      ),
                    );
                  },
                ),
                if (conversation.otherParticipantId != null &&
                    !conversation.isTeam) ...[
                  const SizedBox(height: 10),
                  _SheetActionTile(
                    icon: LucideIcons.userX,
                    title: 'Bloquer ce manager',
                    onTap: () async {
                      Navigator.pop(context);
                      final confirmed = await _confirmAction(
                        title: 'Bloquer ce manager',
                        message:
                            'Ce contact sera ajoute a vos utilisateurs bloques et ce chat disparaitra de votre liste.',
                      );
                      if (confirmed != true) return;
                      await _repository.blockUser(
                        conversationId: conversation.id,
                        blockedUserId: conversation.otherParticipantId!,
                      );
                      await _loadCurrentProfile();
                      if (!mounted) return;
                      _showSnack('Manager bloque');
                    },
                  ),
                ],
                const SizedBox(height: 10),
                _SheetActionTile(
                  icon: LucideIcons.trash2,
                  title: 'Supprimer definitivement',
                  destructive: true,
                  onTap: () async {
                    Navigator.pop(context);
                    final confirmed = await _confirmAction(
                      title: 'Supprimer la conversation',
                      message:
                          'Cette suppression sera definitive dans Firebase, y compris tous les messages du fil.',
                    );
                    if (confirmed != true) return;
                    await _repository.deleteConversationPermanently(
                      conversation.id,
                    );
                    if (!mounted) return;
                    _showSnack('Conversation supprimee');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmAction({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kMessagesBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmer'),
            ),
          ],
        );
      },
    );
  }

  List<ConversationSummary> _applyFilters(
    List<ConversationSummary> conversations,
    String currentUserId,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final blockedIds = _currentProfile?.blockedUserIds ?? const <String>[];

    return conversations.where((conversation) {
      if (conversation.blockedParticipantIds.contains(currentUserId)) {
        return false;
      }
      if (conversation.otherParticipantId != null &&
          blockedIds.contains(conversation.otherParticipantId)) {
        return false;
      }
      if (_unreadOnly && conversation.unreadCount <= 0) return false;

      final categoryMatch = switch (_activeCategory) {
        _ConversationCategory.all => true,
        _ConversationCategory.missions => conversation.isMission,
        _ConversationCategory.team => conversation.isTeam,
        _ConversationCategory.direct => conversation.isDirect,
      };
      if (!categoryMatch) return false;

      if (query.isEmpty) return true;

      final haystack = <String>[
        conversation.title,
        conversation.subtitle,
        conversation.preview,
        conversation.contextTitle,
        conversation.contextSubtitle,
        conversation.otherProfile?.department ?? '',
        ...?conversation.otherProfile?.specialties,
        ...conversation.memberProfiles.map((member) => member.name),
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList()..sort((a, b) {
      final aDate = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Scaffold(
        backgroundColor: kMessagesPageBg,
        body: Center(
          child: Text(
            'Connexion requise',
            style: TextStyle(color: kMessagesText, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kMessagesPageBg,
      floatingActionButton: FloatingActionButton(
        onPressed: _openOffers,
        backgroundColor: kMessagesBlue,
        foregroundColor: Colors.white,
        elevation: 10,
        child: const Icon(LucideIcons.briefcase, size: 22),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _MessagesBottomNav(
        onHomeTap: _openHome,
        onOffersTap: _openOffers,
        onMessagesTap: () {},
        onProfileTap: _openProfile,
      ),
      body: SafeArea(
        child: StreamBuilder<List<ConversationSeed>>(
          stream: _repository.watchConversationSeeds(currentUserId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessagesErrorState(
                message: 'Impossible de charger la messagerie depuis Firebase.',
                onBackHome: _openHome,
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: kMessagesBlue),
              );
            }

            return FutureBuilder<List<ConversationSummary>>(
              future: Future.wait(
                snapshot.data!.map(
                  (seed) => _repository.hydrateConversation(
                    currentUserId: currentUserId,
                    conversationId: seed.id,
                    data: seed.data,
                  ),
                ),
              ),
              builder: (context, hydratedSnapshot) {
                if (hydratedSnapshot.hasError) {
                  return _MessagesErrorState(
                    message:
                        'Les discussions existent, mais leur lecture detaillee a echoue.',
                    onBackHome: _openHome,
                  );
                }

                if (!hydratedSnapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: kMessagesBlue),
                  );
                }

                final allConversations = hydratedSnapshot.data!;
                final filteredConversations = _applyFilters(
                  allConversations,
                  currentUserId,
                );
                final unreadCount = allConversations.fold<int>(
                  0,
                  (total, conversation) => total + conversation.unreadCount,
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 116),
                  children: [
                    _MessagesHeader(
                      profile: _currentProfile,
                      loadingProfile: _loadingProfile,
                      hasUnread: unreadCount > 0,
                      onNotificationTap: () =>
                          _showSnack('Aucune notification supplementaire'),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _SearchField(controller: _searchController),
                        ),
                        const SizedBox(width: 12),
                        _RoundIconButton(
                          icon: LucideIcons.slidersHorizontal,
                          onTap: _openFilterSheet,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 46,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _CategoryChip(
                            label: 'Tous',
                            icon: LucideIcons.messageCircle,
                            active:
                                _activeCategory == _ConversationCategory.all,
                            onTap: () => setState(
                              () => _activeCategory = _ConversationCategory.all,
                            ),
                          ),
                          _CategoryChip(
                            label: 'Missions',
                            icon: LucideIcons.briefcase,
                            active:
                                _activeCategory ==
                                _ConversationCategory.missions,
                            onTap: () => setState(
                              () => _activeCategory =
                                  _ConversationCategory.missions,
                            ),
                          ),
                          _CategoryChip(
                            label: 'Equipe',
                            icon: LucideIcons.users,
                            active:
                                _activeCategory == _ConversationCategory.team,
                            onTap: () => setState(
                              () =>
                                  _activeCategory = _ConversationCategory.team,
                            ),
                          ),
                          _CategoryChip(
                            label: 'Direct',
                            icon: LucideIcons.user,
                            active:
                                _activeCategory == _ConversationCategory.direct,
                            onTap: () => setState(
                              () => _activeCategory =
                                  _ConversationCategory.direct,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text(
                          'Conversations',
                          style: TextStyle(
                            color: kMessagesText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: unreadCount > 0
                                ? kMessagesSoftBlue
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: kMessagesBorder),
                          ),
                          child: Text(
                            'Non lues $unreadCount',
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? kMessagesBlue
                                  : kMessagesMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (allConversations.isEmpty)
                      _MessagesEmptyState(onActionTap: _openOffers)
                    else if (filteredConversations.isEmpty)
                      const _FilteredEmptyState()
                    else
                      ...filteredConversations.map(
                        (conversation) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ConversationCard(
                            conversation: conversation,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatDetailScreen(
                                    conversationId: conversation.id,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () =>
                                _openConversationActions(conversation),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({
    required this.profile,
    required this.loadingProfile,
    required this.hasUnread,
    required this.onNotificationTap,
  });

  final ProfileSummary? profile;
  final bool loadingProfile;
  final bool hasUnread;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AvatarCircle(profile: profile, loading: loadingProfile, size: 52),
        const Expanded(
          child: Text(
            'Messages',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMessagesText,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _RoundIconButton(icon: LucideIcons.bell, onTap: onNotificationTap),
            if (hasUnread)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: kMessagesWarning,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({this.profile, this.loading = false, this.size = 50});

  final ProfileSummary? profile;
  final bool loading;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: kMessagesBorder),
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: kMessagesBlue,
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kMessagesBlue, kMessagesDeepBlue],
        ),
        shape: BoxShape.circle,
      ),
      child: CircleAvatar(
        backgroundColor: Colors.white,
        backgroundImage: profile?.avatarImage,
        child: profile?.avatarImage == null
            ? Text(
                profile?.initials ?? 'S',
                style: TextStyle(
                  color: kMessagesBlue,
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.w800,
                ),
              )
            : null,
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

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
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kMessagesBorder),
          ),
          child: Icon(icon, color: kMessagesBlue, size: 20),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Rechercher une conversation...',
        hintStyle: const TextStyle(color: kMessagesMuted),
        prefixIcon: const Icon(
          LucideIcons.search,
          color: kMessagesMuted,
          size: 18,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: kMessagesBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: kMessagesBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: kMessagesBlue, width: 1.2),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: active ? kMessagesBlue : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? kMessagesBlue : kMessagesBorder),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: active ? Colors.white : kMessagesMuted,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : kMessagesMuted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });

  final ConversationSummary conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kMessagesCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kMessagesBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C0F172A),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ConversationAvatar(conversation: conversation),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kMessagesText,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatConversationTime(conversation.updatedAt),
                        style: const TextStyle(
                          color: kMessagesMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conversation.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kMessagesBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    conversation.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kMessagesBody,
                      fontSize: 13.8,
                      height: 1.42,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              children: [
                if (conversation.unreadCount > 0)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: kMessagesBlue,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${conversation.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const Icon(
                  LucideIcons.moreVertical,
                  color: kMessagesMuted,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    if (conversation.isTeam) {
      return Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: kMessagesSoftBlue,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFBDD5FF)),
        ),
        child: const Icon(LucideIcons.users, color: kMessagesBlue, size: 24),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _AvatarCircle(profile: conversation.otherProfile, size: 58),
        if (conversation.isAvailable)
          Positioned(
            right: 0,
            bottom: 2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: kMessagesSuccess,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessagesEmptyState extends StatelessWidget {
  const _MessagesEmptyState({required this.onActionTap});

  final VoidCallback onActionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kMessagesBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: kMessagesSoftBlue,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              LucideIcons.messageSquare,
              color: kMessagesBlue,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune conversation',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMessagesText,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vos discussions professionnelles apparaitront ici. En attendant, vous pouvez parcourir les offres disponibles.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMessagesBody,
              fontSize: 13.8,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onActionTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: kMessagesBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'Parcourir les offres',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kMessagesBorder),
      ),
      child: const Column(
        children: [
          Icon(LucideIcons.searchX, color: kMessagesBlue, size: 28),
          SizedBox(height: 14),
          Text(
            'Aucun resultat pour ce filtre',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMessagesText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Essayez un autre onglet ou retirez la recherche pour revoir toutes les conversations disponibles.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kMessagesBody,
              fontSize: 13.6,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesErrorState extends StatelessWidget {
  const _MessagesErrorState({required this.message, required this.onBackHome});

  final String message;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: kMessagesBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.alertCircle,
                color: kMessagesWarning,
                size: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                'Messagerie indisponible',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kMessagesText,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kMessagesBody,
                  fontSize: 13.8,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onBackHome,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMessagesBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: const Text('Retour a l accueil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetActionTile extends StatelessWidget {
  const _SheetActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive ? kMessagesDanger : kMessagesText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0xFFFFF1F2)
              : const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: destructive ? const Color(0xFFFECACA) : kMessagesBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              color: destructive ? kMessagesDanger : kMessagesMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesBottomNav extends StatelessWidget {
  const _MessagesBottomNav({
    required this.onHomeTap,
    required this.onOffersTap,
    required this.onMessagesTap,
    required this.onProfileTap,
  });

  final VoidCallback onHomeTap;
  final VoidCallback onOffersTap;
  final VoidCallback onMessagesTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kMessagesBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x08071A3D),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.home,
                  label: 'Accueil',
                  active: false,
                  onTap: onHomeTap,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.briefcase,
                  label: 'Offres',
                  active: false,
                  onTap: onOffersTap,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.messageCircle,
                  label: 'Messages',
                  active: true,
                  onTap: onMessagesTap,
                ),
              ),
              Expanded(
                child: _BottomNavItem(
                  icon: LucideIcons.user,
                  label: 'Profil',
                  active: false,
                  onTap: onProfileTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? kMessagesBlue : kMessagesMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: active ? 26 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: kMessagesBlue,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatConversationTime(DateTime? date) {
  if (date == null) return '--';
  final now = DateTime.now();
  final local = date.toLocal();
  final isToday =
      now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  if (isToday) return DateFormat('HH:mm').format(local);
  final isYesterday =
      now.difference(DateTime(local.year, local.month, local.day)).inDays == 1;
  if (isYesterday) return 'Hier';
  return DateFormat('dd/MM').format(local);
}

enum _ConversationCategory { all, missions, team, direct }
