import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipeinn/features/auth/domain/user_model.dart';
import 'package:swipeinn/features/auth/presentation/auth_provider.dart';
import 'package:swipeinn/features/matches/presentation/matches_provider.dart';
import 'package:swipeinn/features/matches/presentation/chat_screen.dart';
import 'package:swipeinn/core/services/database_service.dart';

void main() {
  setUp(() {
    DatabaseService.instance.resetForTesting();
  });

  tearDown(() {
    DatabaseService.instance.resetForTesting();
  });

  testWidgets('Chat screen message alignment: Student messages on right for student, on left for landlord', (tester) async {
    final container = ProviderContainer();

    // 1. Student signs in
    await container.read(authStateProvider.notifier).signInWithRole(
      email: 'student@ust.edu.ph',
      displayName: 'Alex Cruz',
      role: UserRole.student,
    );

    final match = container.read(matchesProvider).first;

    // Pump ChatScreen for Student
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ChatScreen(match: match, listingTitle: 'Sunshine Dormitory'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // msg_1 was sent by student
    final msg1Finder = find.text('Hi! I am looking for a November move-in—when can I view the unit?');
    expect(msg1Finder, findsOneWidget);

    final alignFinder = find.ancestor(of: msg1Finder, matching: find.byType(Align));
    expect(alignFinder, findsWidgets);
    final Align alignWidget = tester.widget(alignFinder.first);

    // Student should see student messages on the right
    expect(alignWidget.alignment, Alignment.centerRight,
        reason: 'Student message should appear on the right side for a student user');
  });

  testWidgets('Chat screen message alignment: Landlord sees student messages on left, replies on right', (tester) async {
    final container = ProviderContainer();

    // Landlord signs in
    await container.read(authStateProvider.notifier).signInWithRole(
      email: 'host@rently.ph',
      displayName: 'Sunshine Host',
      role: UserRole.landlord,
    );

    final match = container.read(matchesProvider).first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ChatScreen(match: match, listingTitle: 'Sunshine Dormitory'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // msg_1 was sent by student: for landlord, this must be on the left
    final msg1Finder = find.text('Hi! I am looking for a November move-in—when can I view the unit?');
    expect(msg1Finder, findsOneWidget);

    final alignFinder = find.ancestor(of: msg1Finder, matching: find.byType(Align));
    final Align alignWidget = tester.widget(alignFinder.first);
    expect(alignWidget.alignment, Alignment.centerLeft,
        reason: 'Student message should appear on the left side for a landlord user');

    // Landlord sends a reply
    final textField = find.byType(TextField);
    await tester.enterText(textField, 'Yes! You can view it this Saturday at 2 PM.');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final landlordReplyFinder = find.text('Yes! You can view it this Saturday at 2 PM.');
    expect(landlordReplyFinder, findsOneWidget);

    final replyAlignFinder = find.ancestor(of: landlordReplyFinder, matching: find.byType(Align));
    final Align replyAlignWidget = tester.widget(replyAlignFinder.first);
    expect(replyAlignWidget.alignment, Alignment.centerRight,
        reason: 'Landlord reply should appear on the right side for landlord');
  });

  testWidgets('Chat screen dynamically unlocks when First Move is sent', (tester) async {
    final container = ProviderContainer();

    // Create a new match with 0 messages
    container.read(matchesProvider.notifier).createBilateralMatch(
      listingId: 'listing_02',
      landlordUid: 'landlord_101',
      studentUid: 'student_sample_1',
    );

    final match = container.read(matchesProvider).firstWhere((m) => m.id == 'listing_02_student_sample_1');
    expect(match.messagesCount, 0);

    // Sign in as student
    await container.read(authStateProvider.notifier).signInWithRole(
      email: 'student@ust.edu.ph',
      displayName: 'Alex Cruz',
      role: UserRole.student,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ChatScreen(match: match, listingTitle: 'University Suites'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Banner should be visible initially
    expect(find.text('You have 24 hours to send the first message to unlock this chat.'), findsOneWidget);

    // Send a message using the text field
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    await tester.enterText(textFieldFinder, 'Hello Landlord! Interested in viewing.');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // Banner should now be gone because First Move was made!
    expect(find.text('You have 24 hours to send the first message to unlock this chat.'), findsNothing,
        reason: 'First move banner should disappear once a message is sent');
  });

  testWidgets('Chat screen does not expose a role switcher in the AppBar', (tester) async {
    final container = ProviderContainer();

    await container.read(authStateProvider.notifier).signInWithRole(
      email: 'student@ust.edu.ph',
      displayName: 'Alex Cruz',
      role: UserRole.student,
    );

    final match = container.read(matchesProvider).first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ChatScreen(match: match, listingTitle: 'Sunshine Dormitory'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Users must not be able to switch Student/Landlord roles inside a chat.
    expect(find.byIcon(Icons.swap_horiz), findsNothing);

    // Student still sees their own message on the right.
    final msg1Finder = find.text('Hi! I am looking for a November move-in—when can I view the unit?');
    final Align alignWidget = tester.widget(find.ancestor(of: msg1Finder, matching: find.byType(Align)).first);
    expect(alignWidget.alignment, Alignment.centerRight);
  });
}
