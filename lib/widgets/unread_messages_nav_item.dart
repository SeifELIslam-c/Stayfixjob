import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class UnreadMessagesNavItem extends StatefulWidget {
  const UnreadMessagesNavItem({
    super.key,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.indicatorColor,
    required this.onTap,
    this.iconSize = 21,
    this.label = 'Messages',
  });

  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final Color indicatorColor;
  final VoidCallback onTap;
  final double iconSize;
  final String label;

  @override
  State<UnreadMessagesNavItem> createState() => _UnreadMessagesNavItemState();
}

class _UnreadMessagesNavItemState extends State<UnreadMessagesNavItem> {
  late final String _uid;
  late final Stream<QuerySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _stream = _uid.isEmpty
        ? const Stream.empty()
        : FirebaseFirestore.instance
              .collection('conversations')
              .where('participants', arrayContains: _uid)
              .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? widget.activeColor : widget.inactiveColor;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: _stream,
              builder: (context, snapshot) {
                bool hasUnread = false;
                if (snapshot.hasData) {
                  hasUnread = snapshot.data!.docs.any((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final lastMessageAt = data['lastMessageAt'];
                    if (lastMessageAt is! Timestamp) return false;
                    final lastReadAt = data['lastReadAt'];
                    if (lastReadAt is! Map) return true;
                    final myLastRead = lastReadAt[_uid];
                    if (myLastRead is! Timestamp) return true;
                    return lastMessageAt.compareTo(myLastRead) > 0;
                  });
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      LucideIcons.messageCircle,
                      color: color,
                      size: widget.iconSize,
                    ),
                    if (hasUnread)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF3B30),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: widget.active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: widget.active ? 26 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: widget.indicatorColor,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
