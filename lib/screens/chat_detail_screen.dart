import 'package:flutter/material.dart';

import '../services/messages_repository.dart';
import 'messages_screen.dart';
import 'worker_chat_thread_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final MessagesRepository _repository = MessagesRepository();

  ConversationSummary? _conversation;
  bool _loading = true;
  bool _accessDenied = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final summary = await _repository.loadConversationSummary(
        widget.conversationId,
      );
      final currentUid = _repository.currentUserId;
      if (currentUid == null || !summary.participantIds.contains(currentUid)) {
        if (!mounted) return;
        setState(() {
          _accessDenied = true;
          _loading = false;
        });
        return;
      }

      await _repository.markConversationAsRead(widget.conversationId);

      if (!mounted) return;
      setState(() {
        _conversation = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kMessagesPageBg,
        body: Center(child: CircularProgressIndicator(color: kMessagesBlue)),
      );
    }

    if (_accessDenied) {
      return _ChatStatusState(
        title: 'Acces non autorise',
        message:
            'Cette conversation n est pas liee au compte courant ou les participants n ont pas pu etre verifies.',
      );
    }

    final conversation = _conversation;
    if (conversation == null) {
      return _ChatStatusState(
        title: 'Conversation indisponible',
        message: 'Le detail du fil n a pas pu etre charge. ${_loadError ?? ''}'
            .trim(),
      );
    }

    return WorkerChatThreadScreen(
      conversationId: conversation.id,
      title: conversation.otherProfile?.name ?? conversation.title,
      subtitle: conversation.otherProfile?.roleLabel ?? conversation.subtitle,
      avatarBase64: conversation.otherProfile?.photoBase64,
      avatarUrl: conversation.otherProfile?.photoUrl,
      isAvailable:
          conversation.otherProfile?.isAvailable ?? conversation.isAvailable,
      initialBannerText: conversation.rawData['systemBannerText']?.toString(),
    );
  }
}

class _ChatStatusState extends StatelessWidget {
  const _ChatStatusState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kMessagesPageBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: kMessagesBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: kMessagesWarning,
                    size: 34,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kMessagesText,
                      fontSize: 21,
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
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kMessagesBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text('Retour'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
