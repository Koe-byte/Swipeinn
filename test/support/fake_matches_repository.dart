import 'dart:async';

import 'package:swipeinn/features/matches/data/matches_repository.dart';
import 'package:swipeinn/features/matches/domain/match_model.dart';

/// In-memory matches and messages for offline widget tests.
class FakeMatchesRepository implements MatchesRepository {
  final Map<String, MatchModel> matches = {};
  final Map<String, Map<String, MessageModel>> messages = {};

  final _matchesController = StreamController<void>.broadcast();
  final Map<String, StreamController<void>> _messageControllers = {};

  StreamController<void> _messageController(String matchId) {
    return _messageControllers.putIfAbsent(
      matchId,
      () => StreamController<void>.broadcast(),
    );
  }

  @override
  Stream<List<MatchModel>> watchMatches(String uid) async* {
    List<MatchModel> mine() {
      final result = matches.values
          .where((match) => match.isParticipant(uid))
          .toList()
        ..sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
      return result;
    }

    yield mine();
    await for (final _ in _matchesController.stream) {
      yield mine();
    }
  }

  @override
  Stream<List<MessageModel>> watchMessages(String matchId) async* {
    List<MessageModel> current() {
      final result =
          (messages[matchId]?.values ?? const <MessageModel>[]).toList()
            ..sort((a, b) {
              final byTime = a.sentAt.compareTo(b.sentAt);
              return byTime != 0 ? byTime : a.id.compareTo(b.id);
            });
      return result;
    }

    yield current();
    await for (final _ in _messageController(matchId).stream) {
      yield current();
    }
  }

  @override
  Future<bool> createMatch(MatchModel match) async {
    matches[match.id] = match;
    _matchesController.add(null);
    return true;
  }

  @override
  Future<bool> updateMatch(MatchModel match) async {
    matches[match.id] = match;
    _matchesController.add(null);
    return true;
  }

  @override
  Future<bool> sendMessage({
    required MatchModel match,
    required MessageModel message,
  }) async {
    messages.putIfAbsent(match.id, () => {})[message.id] = message;
    _messageController(match.id).add(null);

    // Mirrors the database trigger: one insert updates the summary and, for a
    // proposal, moves the match to "proposed" at the same time.
    final updated = match.copyWith(
      messagesCount: match.messagesCount + 1,
      lastMessage: message.text,
      viewingStatus: message.type == MessageType.viewingProposal
          ? ViewingStatus.proposed
          : null,
      viewingDate: message.type == MessageType.viewingProposal
          ? message.viewingDate
          : null,
    );
    matches[match.id] = updated;
    _matchesController.add(null);
    return true;
  }

  @override
  Future<bool> updateProposal({
    required String matchId,
    required String messageId,
    required String status,
    DateTime? viewingDate,
  }) async {
    final message = messages[matchId]?[messageId];
    if (message != null) {
      messages[matchId]![messageId] = MessageModel(
        id: message.id,
        senderUid: message.senderUid,
        text: message.text,
        type: message.type,
        viewingDate: viewingDate ?? message.viewingDate,
        proposalStatus: status,
        sentAt: message.sentAt,
      );
      _messageController(matchId).add(null);
    }

    final match = matches[matchId];
    if (match != null) {
      matches[matchId] = match.copyWith(
        viewingStatus: status == 'accepted'
            ? ViewingStatus.confirmed
            : (status == 'declined'
                ? ViewingStatus.declined
                : ViewingStatus.proposed),
        viewingDate: viewingDate,
      );
      _matchesController.add(null);
    }
    return true;
  }

  void dispose() {
    _matchesController.close();
    for (final controller in _messageControllers.values) {
      controller.close();
    }
  }
}
