import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/match_model.dart';
import '../data/chat_repository.dart';

export '../data/chat_repository.dart'
    show chatDatabaseRepositoryProvider, ChatDatabaseRepository;

final matchesProvider =
    StateNotifierProvider<MatchesNotifier, List<MatchModel>>((ref) {
  final chatRepo = ref.watch(chatDatabaseRepositoryProvider);
  return MatchesNotifier(chatRepo);
});

class MatchesNotifier extends StateNotifier<List<MatchModel>> {
  final ChatDatabaseRepository _chatRepo;

  MatchesNotifier(this._chatRepo) : super([]);

  // Create deterministic bilateral match: ${listingId}_${studentUid}
  void createBilateralMatch({
    required String listingId,
    required String landlordUid,
    required String studentUid,
  }) {
    final matchId = '${listingId}_$studentUid';

    // Prevent duplicate matches (Idempotency)
    if (state.any((m) => m.id == matchId)) return;

    final now = DateTime.now();
    final newMatch = MatchModel(
      id: matchId,
      listingId: listingId,
      landlordUid: landlordUid,
      studentUid: studentUid,
      status: MatchStatus.active,
      matchedAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      messagesCount: 0,
      viewingStatus: ViewingStatus.none,
    );

    state = [newMatch, ...state];
    _chatRepo.saveMatch(newMatch);
  }

  void incrementMessageCount(String matchId) {
    state = state.map((m) {
      if (m.id == matchId) {
        final updated = m.copyWith(messagesCount: m.messagesCount + 1);
        _chatRepo.saveMatch(updated);
        return updated;
      }
      return m;
    }).toList();
  }

  void updateViewingStatus(String matchId, ViewingStatus status,
      [DateTime? date]) {
    state = state.map((m) {
      if (m.id == matchId) {
        final updated = m.copyWith(viewingStatus: status, viewingDate: date);
        _chatRepo.saveMatch(updated);
        return updated;
      }
      return m;
    }).toList();
  }

  void unmatchAndBlock(String matchId) {
    state = state.map((m) {
      if (m.id == matchId) {
        final updated = m.copyWith(status: MatchStatus.unmatched);
        _chatRepo.saveMatch(updated);
        return updated;
      }
      return m;
    }).toList();
  }
}

// Active messages stream per match
final messagesProvider =
    StateNotifierProvider.family<MessagesNotifier, List<MessageModel>, String>(
        (ref, matchId) {
  final chatRepo = ref.watch(chatDatabaseRepositoryProvider);
  return MessagesNotifier(matchId, chatRepo);
});

class MessagesNotifier extends StateNotifier<List<MessageModel>> {
  final String matchId;
  final ChatDatabaseRepository _chatRepo;
  StreamSubscription<List<MessageModel>>? _sub;

  MessagesNotifier(this.matchId, this._chatRepo) : super([]) {
    _initMessages();
  }

  void _initMessages() {
    _sub = _chatRepo.streamMessages(matchId).listen((messages) {
      if (messages.isNotEmpty) {
        state = messages;
      }
    });
  }

  Future<void> sendMessage({
    required String senderUid,
    required String text,
    MessageType type = MessageType.text,
    DateTime? viewingDate,
  }) async {
    final msg = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderUid: senderUid,
      text: text,
      type: type,
      viewingDate: viewingDate,
      proposalStatus: 'pending',
      sentAt: DateTime.now(),
    );
    // Optimistic UI update
    state = [...state, msg];
    // Write to Firestore database
    await _chatRepo.saveMessage(matchId, msg);
  }

  Future<void> updateProposalStatus(String msgId, String newStatus,
      [DateTime? date]) async {
    state = state.map((m) {
      if (m.id == msgId) {
        return MessageModel(
          id: m.id,
          senderUid: m.senderUid,
          text: m.text,
          type: m.type,
          viewingDate: date ?? m.viewingDate,
          proposalStatus: newStatus,
          sentAt: m.sentAt,
        );
      }
      return m;
    }).toList();

    await _chatRepo.updateViewingProposalStatus(
      matchId: matchId,
      messageId: msgId,
      newStatus: newStatus,
      viewingDate: date,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
