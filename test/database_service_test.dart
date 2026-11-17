import 'package:flutter_test/flutter_test.dart';
import 'package:swipeinn/core/services/database_service.dart';

void main() {
  late DatabaseService db;

  setUp(() {
    db = DatabaseService.instance;
    db.resetForTesting();
  });

  test('partial subdocument writes preserve the rest of the message', () async {
    const matchId = 'listing-1_uid-2';
    const messageId = 'proposal-1';

    await db.setSubdocument(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
      docId: messageId,
      data: {
        'id': messageId,
        'matchId': matchId,
        'senderUid': 'uid-2',
        'text': 'In-person inspection requested',
        'type': 'viewingProposal',
        'viewingDate': 1767571200000,
        'proposalStatus': 'pending',
        'sentAt': 1767268800000,
      },
    );

    await db.setSubdocument(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
      docId: messageId,
      data: {'proposalStatus': 'accepted'},
    );

    final message = await db.getSubdocument(
      parentCollection: 'matches',
      parentId: matchId,
      subcollection: 'messages',
      docId: messageId,
    );

    expect(message?['proposalStatus'], 'accepted');
    expect(message?['text'], 'In-person inspection requested');
    expect(message?['senderUid'], 'uid-2');
    expect(message?['type'], 'viewingProposal');
    expect(message?['sentAt'], 1767268800000);
  });

  test('sign-out clears private chats but keeps public listings', () async {
    await db.setDocument(
      collection: 'listings',
      docId: 'listing-1',
      data: {'id': 'listing-1', 'title': 'Lahug Studio'},
    );
    await db.setDocument(
      collection: 'matches',
      docId: 'listing-1_uid-2',
      data: {'id': 'listing-1_uid-2', 'messagesCount': 1},
    );
    await db.setSubdocument(
      parentCollection: 'matches',
      parentId: 'listing-1_uid-2',
      subcollection: 'messages',
      docId: 'message-1',
      data: {'id': 'message-1', 'text': 'See you Saturday.'},
    );

    await db.clearPrivateState();

    expect(
      await db.getLocalDocument(
          collection: 'matches', docId: 'listing-1_uid-2'),
      isNull,
    );
    expect(
      await db.getSubcollection(
        parentCollection: 'matches',
        parentId: 'listing-1_uid-2',
        subcollection: 'messages',
      ),
      isEmpty,
    );
    expect(
      await db.getLocalDocument(collection: 'listings', docId: 'listing-1'),
      isNotNull,
    );
  });
}
