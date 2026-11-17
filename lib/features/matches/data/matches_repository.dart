import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_service.dart';
import '../domain/match_model.dart';

final matchesRepositoryProvider = Provider<MatchesRepository>((ref) {
  return SupabaseMatchesRepository();
});

/// Bilateral conversations and their messages.
abstract class MatchesRepository {
  Stream<List<MatchModel>> watchMatches(String uid);

  Stream<List<MessageModel>> watchMessages(String matchId);

  Future<bool> createMatch(MatchModel match);

  Future<bool> updateMatch(MatchModel match);

  /// Inserts the message. The database trigger updates the match summary in
  /// the same transaction, so there is no second client write to fail.
  /// Returns `false` when only the local mirror changed.
  Future<bool> sendMessage({
    required MatchModel match,
    required MessageModel message,
  });

  /// Accepts or declines [messageId] through one database function.
  ///
  /// Only the recipient of a pending proposal may respond; the function also
  /// checks that the match still exists and is active. Returns `false` when
  /// only the local mirror changed.
  Future<bool> updateProposal({
    required String matchId,
    required String messageId,
    required String status,
    DateTime? viewingDate,
  });
}

class SupabaseMatchesRepository implements MatchesRepository {
  final DatabaseService _db = DatabaseService.instance;

  static bool _isMissingRpc(PostgrestException error) {
    // PGRST202 is "function not found"; 42883 is the raw Postgres equivalent.
    return error.code == 'PGRST202' || error.code == '42883';
  }

  static String _rpcMessage(PostgrestException error) {
    final message = error.message.trim();
    return message.isEmpty ? 'The server rejected that request.' : message;
  }

  static ViewingStatus _viewingStatusFor(String status) {
    switch (status) {
      case 'accepted':
        return ViewingStatus.confirmed;
      case 'declined':
        return ViewingStatus.declined;
      default:
        return ViewingStatus.proposed;
    }
  }

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
  Future<bool> createMatch(MatchModel match) {
    return _db.setDocument(
      collection: 'matches',
      docId: match.id,
      data: {
        ...match.toMap(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<bool> updateMatch(MatchModel match) {
    return _db.setDocument(
      collection: 'matches',
      docId: match.id,
      data: {
        ...match.toMap(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<bool> sendMessage({
    required MatchModel match,
    required MessageModel message,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isProposal = message.type == MessageType.viewingProposal;

    // Optimistic local summary. The database trigger performs the same update
    // in the cloud, which is what the other account receives over Realtime.
    await _db.cacheDocumentLocally(
      collection: 'matches',
      docId: match.id,
      data: {
        'messagesCount': match.messagesCount + 1,
        'lastMessage': message.text,
        if (isProposal) ...{
          'viewingStatus': ViewingStatus.proposed.name,
          'viewingDate': message.viewingDate?.millisecondsSinceEpoch,
        },
        'updatedAt': now,
      },
    );

    return _db.setSubdocument(
      parentCollection: 'matches',
      parentId: match.id,
      subcollection: 'messages',
      docId: message.id,
      data: message.toMap(),
    );
  }

  @override
  Future<bool> updateProposal({
    required String matchId,
    required String messageId,
    required String status,
    DateTime? viewingDate,
  }) async {
    if (_db.isSupabaseAvailable) {
      try {
        await _db.callRpc('respond_to_viewing_proposal', params: {
          'p_match_id': matchId,
          'p_message_id': messageId,
          'p_status': status,
        });
        _applyProposalLocally(
          matchId: matchId,
          messageId: messageId,
          status: status,
          viewingDate: viewingDate,
        );
        return true;
      } on PostgrestException catch (error) {
        if (!_isMissingRpc(error)) {
          throw StateError(_rpcMessage(error));
        }
        debugPrint(
          '[MatchesRepository] respond_to_viewing_proposal is missing; '
          'falling back to separate writes. Apply 0006 to make responses '
          'recipient-only and atomic.',
        );
      } catch (error) {
        debugPrint(
          '[MatchesRepository] Proposal response failed; queuing the local '
          'writes: $error',
        );
      }
    }

    return _legacyUpdateProposal(
      matchId: matchId,
      messageId: messageId,
      status: status,
      viewingDate: viewingDate,
    );
  }

  void _applyProposalLocally({
    required String matchId,
    required String messageId,
    required String status,
    DateTime? viewingDate,
  }) {
    _db.cacheSubdocumentLocally(
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

    final viewingStatus = _viewingStatusFor(status);
    _db.cacheDocumentLocally(
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

  /// Works with a database that has not applied 0006 yet. Both writes still
  /// merge locally, and both queue for replay when the network is down.
  Future<bool> _legacyUpdateProposal({
    required String matchId,
    required String messageId,
    required String status,
    DateTime? viewingDate,
  }) async {
    final messageSaved = await _db.setSubdocument(
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

    final viewingStatus = _viewingStatusFor(status);
    final matchSaved = await _db.setDocument(
      collection: 'matches',
      docId: matchId,
      data: {
        'viewingStatus': viewingStatus.name,
        if (viewingDate != null)
          'viewingDate': viewingDate.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );

    return messageSaved && matchSaved;
  }
}
