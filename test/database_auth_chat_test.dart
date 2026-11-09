import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rently/features/auth/domain/user_model.dart';
import 'package:rently/features/auth/presentation/auth_provider.dart';
import 'package:rently/features/matches/domain/match_model.dart';
import 'package:rently/features/matches/presentation/matches_provider.dart';

void main() {
  group('Database Auth and Chat verification', () {
    test('Auth user must be persisted in database and retrievable by UID', () async {
      final container = ProviderContainer();

      // Sign in user
      await container.read(authStateProvider.notifier).signInWithRole(
        email: 'test_student@ust.edu.ph',
        displayName: 'Test Student',
        role: UserRole.student,
      );

      final user = container.read(authStateProvider).value;
      expect(user, isNotNull);

      // Verify that user profile was persisted to the database layer
      final dbUser = await container.read(authDatabaseRepositoryProvider).fetchUserProfile(user!.uid);
      expect(dbUser, isNotNull, reason: 'User must be saved and retrievable from the database');
      expect(dbUser?.email, 'test_student@ust.edu.ph');
      expect(dbUser?.role, UserRole.student);
    });

    test('Chat messages and viewing proposals must be persisted in database and streamable', () async {
      final container = ProviderContainer();

      const matchId = 'listing_01_student_sample_1';

      // Send a message via chat provider
      await container.read(messagesProvider(matchId).notifier).sendMessage(
        senderUid: 'student_sample_1',
        text: 'Hello from persistent database test',
      );

      // Verify that the message is stored in the database layer for matches/{matchId}/messages
      final dbMessages = await container.read(chatDatabaseRepositoryProvider).fetchMessages(matchId);
      expect(dbMessages.any((m) => m.text == 'Hello from persistent database test'), isTrue,
          reason: 'Chat message must be written to the database under matches/{matchId}/messages');
    });

    test('Viewing proposals are recorded in database subcollection and update match status', () async {
      final container = ProviderContainer();
      const matchId = 'listing_01_student_sample_1';

      final inspectionDate = DateTime.now().add(const Duration(days: 3));

      await container.read(messagesProvider(matchId).notifier).sendMessage(
        senderUid: 'student_sample_1',
        text: 'Inspection proposal test',
        type: MessageType.viewingProposal,
        viewingDate: inspectionDate,
      );

      final dbMessages = await container.read(chatDatabaseRepositoryProvider).fetchMessages(matchId);
      final proposal = dbMessages.lastWhere((m) => m.type == MessageType.viewingProposal);
      expect(proposal.proposalStatus, 'pending');

      // Update proposal to accepted
      await container.read(messagesProvider(matchId).notifier).updateProposalStatus(
        proposal.id,
        'accepted',
        inspectionDate,
      );

      final updatedMatch = await container.read(chatDatabaseRepositoryProvider).fetchMatch(matchId);
      expect(updatedMatch?.viewingStatus, ViewingStatus.confirmed,
          reason: 'Match document in database must reflect confirmed viewing status');
    });
  });
}
