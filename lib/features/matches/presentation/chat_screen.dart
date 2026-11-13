import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/match_model.dart';
import 'matches_provider.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final MatchModel match;
  final String listingTitle;

  const ChatScreen({
    Key? key,
    required this.match,
    required this.listingTitle,
  }) : super(key: key);

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();

  final List<String> _icebreakers = [
    'Hi! I am looking for a January move-in—when can I view the unit?',
    'Hello! Are utilities included in the monthly rent?',
    'Hi! Is this unit still available for an ocular visit this weekend?',
  ];

  MatchModel _currentMatch() {
    final matches = ref.read(matchesProvider).valueOrNull ?? const [];
    return matches.firstWhere(
      (m) => m.id == widget.match.id,
      orElse: () => widget.match,
    );
  }

  String? get _uid => ref.read(authStateProvider).user?.uid;

  @override
  Widget build(BuildContext context) {
    final matchesAsync = ref.watch(matchesProvider);
    final currentMatch =
        (matchesAsync.valueOrNull ?? const <MatchModel>[]).firstWhere(
      (m) => m.id == widget.match.id,
      orElse: () => widget.match,
    );
    final messagesAsync = ref.watch(messagesProvider(widget.match.id));
    final messages = messagesAsync.valueOrNull ?? const <MessageModel>[];
    final user = ref.watch(authStateProvider).user;
    final isRequester = user != null && user.uid == currentMatch.requesterUid;
    final isMatchActive =
        currentMatch.status == MatchStatus.active && !currentMatch.isExpired;
    final needsFirstMove = currentMatch.messagesCount == 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              isRequester
                  ? 'Owner • ${widget.listingTitle}'
                  : 'Renter • ${widget.listingTitle}',
              style: const TextStyle(fontSize: 15),
            ),
            Text(
              isRequester ? 'Direct with owner' : 'Direct with renter',
              style:
                  const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          // Role switching is intentionally unavailable inside an active chat.
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => _showSafetySheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // First-move banner: the requester opens the conversation.
          if (needsFirstMove)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.primaryAmber.withOpacity(0.18),
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined,
                      color: AppTheme.navyDark, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isRequester
                          ? 'Send the first message to open this chat.'
                          : 'Waiting for the renter to send the first message.',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Messages View
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_outline,
                              size: 48, color: AppTheme.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            isRequester
                                ? 'Tap a quick icebreaker below or send a message to break the ice!'
                                : 'The renter must make the first move.',
                            textAlign: TextAlign.center,
                            style:
                                const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.senderUid == (user?.uid ?? '');

                      if (msg.type == MessageType.viewingProposal) {
                        return _ViewingProposalBubble(
                          msg: msg,
                          isLandlord: !isRequester,
                          onAccept: () => _acceptProposal(msg),
                        );
                      }

                      return Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isMe ? AppTheme.primaryAmber : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Text(
                            msg.text,
                            style: TextStyle(
                              color: isMe ? AppTheme.navyDark : Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Requester icebreaker chips.
          if (isRequester && needsFirstMove)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _icebreakers
                    .map(
                      (prompt) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          backgroundColor: Colors.amber.shade100,
                          label: Text(
                            prompt,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.navyDark),
                          ),
                          onPressed: () {
                            _sendMessage(prompt);
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          // Composer
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.event_available,
                        color: AppTheme.primaryDarkAmber),
                    tooltip: 'Schedule Viewing',
                    onPressed: isMatchActive
                        ? () => _showScheduleViewingDialog(context)
                        : null,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled:
                          isMatchActive && (!needsFirstMove || isRequester),
                      decoration: InputDecoration(
                        hintText: needsFirstMove && !isRequester
                            ? 'Waiting for the renter...'
                            : 'Type a message...',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppTheme.navyDark),
                    onPressed: isMatchActive && (!needsFirstMove || isRequester)
                        ? () {
                            final text = _messageController.text.trim();
                            if (text.isNotEmpty) {
                              _sendMessage(text);
                              _messageController.clear();
                            }
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage(String text) async {
    final senderUid = _uid;
    if (senderUid == null) return;

    final now = DateTime.now();
    final message = MessageModel(
      id: 'msg_${now.microsecondsSinceEpoch}_$senderUid',
      senderUid: senderUid,
      text: text,
      sentAt: now,
    );

    await ref.read(matchesRepositoryProvider).sendMessage(
          match: _currentMatch(),
          message: message,
        );
  }

  Future<void> _acceptProposal(MessageModel msg) async {
    await ref.read(matchesRepositoryProvider).updateProposal(
          matchId: widget.match.id,
          messageId: msg.id,
          status: 'accepted',
          viewingDate: msg.viewingDate,
        );
  }

  Future<void> _showScheduleViewingDialog(BuildContext context) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (pickedDate == null) return;

    final senderUid = _uid;
    if (senderUid == null) return;

    final match = _currentMatch();
    final now = DateTime.now();
    final message = MessageModel(
      id: 'msg_${now.microsecondsSinceEpoch}_$senderUid',
      senderUid: senderUid,
      text: 'In-person inspection requested',
      type: MessageType.viewingProposal,
      viewingDate: pickedDate,
      sentAt: now,
    );

    await ref.read(matchesRepositoryProvider).updateMatch(
          match.copyWith(
            viewingStatus: ViewingStatus.proposed,
            viewingDate: pickedDate,
          ),
        );
    await ref.read(matchesRepositoryProvider).sendMessage(
          match: match,
          message: message,
        );
  }

  void _showSafetySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Safety & Match Options',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.block, color: AppTheme.passRed),
                title: const Text('Unmatch & Block User',
                    style: TextStyle(color: AppTheme.passRed)),
                subtitle: const Text(
                    'Instantly closes this chat and prevents future card appearances.'),
                onTap: () async {
                  await ref.read(matchesRepositoryProvider).updateMatch(
                        _currentMatch().copyWith(status: MatchStatus.unmatched),
                      );
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewingProposalBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isLandlord;
  final VoidCallback onAccept;

  const _ViewingProposalBubble({
    required this.msg,
    required this.isLandlord,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = msg.viewingDate != null
        ? '${msg.viewingDate!.month}/${msg.viewingDate!.day}/${msg.viewingDate!.year}'
        : 'Tomorrow';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryAmber, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.calendar_month, color: AppTheme.navyDark, size: 20),
              SizedBox(width: 8),
              Text(
                'Viewing Proposal',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Proposed Viewing Date: $dateStr'),
          const SizedBox(height: 12),
          if (msg.proposalStatus == 'accepted')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.likeGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '✓ Viewing Confirmed',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            )
          else if (isLandlord)
            ElevatedButton(
              onPressed: onAccept,
              child: const Text('Accept Viewing Date'),
            )
          else
            const Text(
              'Awaiting Landlord Confirmation...',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}
