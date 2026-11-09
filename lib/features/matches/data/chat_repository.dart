import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/match_model.dart';
import '../../../core/services/database_service.dart';

final chatDatabaseRepositoryProvider = Provider<ChatDatabaseRepository>((ref) {
  return ChatDatabaseRepository();
});

class ChatDatabaseRepository {
  final DatabaseService _db = DatabaseService.instance;

  Future<void> saveMatch(MatchModel match) async {
    await _db.setDocument(
      collection: 'matches',
      docId: match.id,
      data: match.toMap(),
    );
  }

  Future<MatchModel?> fetchMatch(String matchId) async {
    final data = await _db.getDocument(collection: 'matches', docId: matchId);
    if (data == null) return null;
    return MatchModel.fromMap(data, matchId);
  }

  Stream<MatchModel?> streamMatch(String matchId) {
    return _db.streamDocument(collection: 'matches', docId: matchId).map((data) {
      if (data == null) return null;
      return MatchModel.fromMap(data, matchId);
    });
  }

  Future<void> saveMessage(String matchId, MessageModel message) async {
    // 1. Save message inside subcollection matches/{matchId}/messages/{messageId}
    await _db.setSubdocument(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
      docId: message.id,
      data: message.toMap(),
    );

    // 2. Update match root document stats
    final match = await fetchMatch(matchId);
    final count = (match?.messagesCount ?? 0) + 1;
    await _db.setDocument(
      collection: 'matches',
      docId: matchId,
      data: {
        'messagesCount': count,
        'lastMessage': message.text,
        'lastMessageSentAt': message.sentAt.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      merge: true,
    );
  }

  Future<List<MessageModel>> fetchMessages(String matchId) async {
    final list = await _db.getSubcollection(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
    );
    final messages = list.map((map) => MessageModel.fromMap(map, map['id'] ?? '')).toList();
    messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return messages;
  }

  Stream<List<MessageModel>> streamMessages(String matchId) {
    return _db
        .streamSubcollection(
          parentCollection: 'matches',
          parentId: matchId,
          subcollection: 'messages',
        )
        .map((list) {
      final messages = list.map((map) => MessageModel.fromMap(map, map['id'] ?? '')).toList();
      messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      return messages;
    });
  }

  Future<void> updateViewingProposalStatus({
    required String matchId,
    required String messageId,
    required String newStatus,
    DateTime? viewingDate,
  }) async {
    await _db.setSubdocument(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
      docId: messageId,
      data: {
        'proposalStatus': newStatus,
        if (viewingDate != null) 'viewingDate': viewingDate.millisecondsSinceEpoch,
      },
    );

    final viewingStatus = newStatus == 'accepted'
        ? ViewingStatus.confirmed
        : (newStatus == 'declined' ? ViewingStatus.declined : ViewingStatus.proposed);

    await _db.setDocument(
      collection: 'matches',
      docId: matchId,
      data: {
        'viewingStatus': viewingStatus.name,
        if (viewingDate != null) 'viewingDate': viewingDate.millisecondsSinceEpoch,
      },
      merge: true,
    );
  }
}
