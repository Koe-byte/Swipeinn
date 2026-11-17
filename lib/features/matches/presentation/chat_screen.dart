import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/match_model.dart';
import 'matches_provider.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../../core/theme/app_theme.dart';

String _formatViewingDate(DateTime date) =>
    '${date.month}/${date.day}/${date.year}';

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
  final ScrollController _scrollController = ScrollController();

  /// The reversed list keeps offset 0 at the newest message. The pill only
  /// appears when the reader has scrolled up into history.
  bool _showJumpToLatest = false;

  final List<String> _icebreakers = [
    'Hi! I am looking for a January move-in—when can I view the unit?',
    'Hello! Are utilities included in the monthly rent?',
    'Hi! Is this unit still available for an ocular visit this weekend?',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 120;
    if (shouldShow == _showJumpToLatest) return;
    setState(() => _showJumpToLatest = shouldShow);
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

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
    final confirmedDate = currentMatch.viewingStatus == ViewingStatus.confirmed
        ? currentMatch.viewingDate
        : null;

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
          if (confirmedDate != null)
            Container(
              key: const Key('viewing_confirmed_banner'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.likeGreen.withOpacity(0.16),
              child: Row(
                children: [
                  const Icon(Icons.event_available,
                      color: AppTheme.likeGreen, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Viewing confirmed for ${_formatViewingDate(confirmedDate)}.',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Messages View
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.chat_bubble_outline,
                                    size: 48, color: AppTheme.textSecondary),
                                SizedBox(height: 12),
                                Text(
                                  'Say hello or propose a viewing time to get started. '
                                  'Either of you can send the first message.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          // Newest first in the scroll model, bottom of the
                          // screen in practice. Offset 0 is always the latest
                          // message, so incoming messages stay in view.
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[messages.length - 1 - index];
                            final isMe = msg.senderUid == (user?.uid ?? '');

                            if (msg.type == MessageType.viewingProposal) {
                              return _ViewingProposalBubble(
                                msg: msg,
                                isMine: isMe,
                                canRespond: isMatchActive &&
                                    !isMe &&
                                    msg.proposalStatus == 'pending',
                                onAccept: () =>
                                    _respondToProposal(msg, 'accepted'),
                                onDecline: () =>
                                    _respondToProposal(msg, 'declined'),
                              );
                            }

                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color:
                                      isMe ? AppTheme.primaryAmber : Colors.white,
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
                                    color: isMe
                                        ? AppTheme.navyDark
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_showJumpToLatest && messages.isNotEmpty)
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'chat_jump_latest',
                      tooltip: 'Jump to the latest message',
                      backgroundColor: AppTheme.primaryAmber,
                      foregroundColor: AppTheme.navyDark,
                      onPressed: _scrollToLatest,
                      child: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ),
              ],
            ),
          ),

          // Optional icebreakers for either side while the chat is empty.
          if (messages.isEmpty && isMatchActive)
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
                      enabled: isMatchActive,
                      decoration: InputDecoration(
                        hintText: isMatchActive
                            ? 'Type a message...'
                            : 'This conversation is closed.',
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
                    onPressed: isMatchActive
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

  void _showSyncNotice() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Saved on this device. It will sync once the connection is back.',
        ),
      ),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is StateError ? error.message : '$error';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('That did not go through: $message')),
    );
  }

  Future<void> _sendMessage(String text) async {
    final senderUid = _uid;
    if (senderUid == null) return;

    // Sending from history should return to the newest message rather than
    // leaving the new bubble off-screen.
    _scrollToLatest();

    final now = DateTime.now();
    final message = MessageModel(
      id: 'msg_${now.microsecondsSinceEpoch}_$senderUid',
      senderUid: senderUid,
      text: text,
      sentAt: now,
    );

    try {
      final synced = await ref.read(matchesRepositoryProvider).sendMessage(
            match: _currentMatch(),
            message: message,
          );
      if (!synced) _showSyncNotice();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _respondToProposal(MessageModel msg, String status) async {
    try {
      final synced = await ref.read(matchesRepositoryProvider).updateProposal(
            matchId: widget.match.id,
            messageId: msg.id,
            status: status,
            viewingDate: msg.viewingDate,
          );
      if (!synced) _showSyncNotice();
    } catch (error) {
      _showError(error);
    }
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

    // The database trigger moves the match to "proposed" when the proposal
    // message is inserted. There is no second client write that can fail.
    try {
      final synced = await ref.read(matchesRepositoryProvider).sendMessage(
            match: match,
            message: message,
          );
      if (!synced) _showSyncNotice();
    } catch (error) {
      _showError(error);
    }
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
                  final synced = await ref
                      .read(matchesRepositoryProvider)
                      .updateMatch(
                        _currentMatch().copyWith(status: MatchStatus.unmatched),
                      );
                  if (!context.mounted) return;
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  if (!synced) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Blocked on this device. It will sync once the '
                          'connection is back.',
                        ),
                      ),
                    );
                  }
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
  final bool isMine;
  final bool canRespond;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _ViewingProposalBubble({
    required this.msg,
    required this.isMine,
    required this.canRespond,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = msg.viewingDate != null
        ? _formatViewingDate(msg.viewingDate!)
        : 'Tomorrow';

    final Widget status;
    if (msg.proposalStatus == 'accepted') {
      status = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.likeGreen,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '✓ Viewing confirmed for $dateStr',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      );
    } else if (msg.proposalStatus == 'declined') {
      status = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.passRed,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Viewing declined',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      );
    } else if (canRespond) {
      status = Row(
        children: [
          OutlinedButton(
            key: Key('decline_proposal_${msg.id}'),
            onPressed: onDecline,
            child: const Text('Decline'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              key: Key('accept_proposal_${msg.id}'),
              onPressed: onAccept,
              child: const Text('Accept Viewing Date'),
            ),
          ),
        ],
      );
    } else if (isMine) {
      status = const Text(
        'Waiting for the other person to respond.',
        style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontStyle: FontStyle.italic),
      );
    } else {
      status = const Text(
        'This proposal can no longer be answered.',
        style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontStyle: FontStyle.italic),
      );
    }

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
          status,
        ],
      ),
    );
  }
}
