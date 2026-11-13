import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/database_service.dart';
import '../domain/match_model.dart';

final matchesRepositoryProvider = Provider<MatchesRepository>((ref) {
  return FirestoreMatchesRepository();
});

/// Bilateral conversations and their messages.
abstract class MatchesRepository {
  Stream<List<MatchModel>> watchMatches(String uid);

  Stream<List<MessageModel>> watchMessages(String matchId);

  Future<void> createMatch(MatchModel match);

  Future<void> updateMatch(MatchModel match);

  Future<void> sendMessage({
    required MatchModel match,
    required MessageModel message,
  });

  Future<void> updateProposal({
    required String matchId,
    required String messageId,
    required String status,
    DateTime? viewingDate,
  });
}

class FirestoreMatchesRepository implements MatchesRepository {
  final DatabaseService _db = DatabaseService.instance;

  @override
  Stream<List<MatchModel>> watchMatches(String uid) {
    return _db
        .streamCollection(
      collection: 'matches',
      arrayContainsField: 'participantUids',
      arrayContainsValue: uid,
    )
        .map((docs) {
      final matches = docs
          .map((map) => MatchModel.fromMap(map, map['id'] as String? ?? ''))
          .where((match) => match.id.isNotEmpty)
          .toList();
      matches.sort((a, b) => b.matchedAt.compareTo(a.matchedAt));
      return matches;
    });
  }

  @override
  Stream<List<MessageModel>> watchMessages(String matchId) {
    return _db
        .streamSubcollection(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
    )
        .map((docs) {
      final messages = docs
          .map((map) => MessageModel.fromMap(map, map['id'] as String? ?? ''))
          .toList();
      messages.sort((a, b) {
        final byTime = a.sentAt.compareTo(b.sentAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
      return messages;
    });
  }

  @override
  Future<void> createMatch(MatchModel match) async {
    await _db.setDocument(
      collection: 'matches',
      docId: match.id,
      data: {
        ...match.toMap(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<void> updateMatch(MatchModel match) async {
    await _db.setDocument(
      collection: 'matches',
      docId: match.id,
      data: {
        ...match.toMap(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<void> sendMessage({
    required MatchModel match,
    required MessageModel message,
  }) async {
    await _db.setSubdocument(
      parentCollection: 'matches',
      parentId: match.id,
      subcollection: 'messages',
      docId: message.id,
      data: message.toMap(),
    );

    await _db.setDocument(
      collection: 'matches',
      docId: match.id,
      data: {
        'messagesCount': match.messagesCount + 1,
        'lastMessage': message.text,
        'lastMessageSentAt': message.sentAt.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<void> updateProposal({
    required String matchId,
    required String messageId,
    required String status,
    DateTime? viewingDate,
  }) async {
    await _db.setSubdocument(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
      docId: messageId,
      data: {
        'proposalStatus': status,
        if (viewingDate != null)
          'viewingDate': viewingDate.millisecondsSinceEpoch,
      },
    );

    final viewingStatus = status == 'accepted'
        ? ViewingStatus.confirmed
        : (status == 'declined'
            ? ViewingStatus.declined
            : ViewingStatus.proposed);

    await _db.setDocument(
      collection: 'matches',
      docId: matchId,
      data: {
        'viewingStatus': viewingStatus.name,
        if (viewingDate != null)
          'viewingDate': viewingDate.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
}
