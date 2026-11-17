import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_provider.dart';
import '../data/matches_repository.dart';
import '../domain/match_model.dart';

export '../data/matches_repository.dart' show matchesRepositoryProvider;

/// Matches the signed-in account takes part in, on either side.
final matchesProvider = StreamProvider.autoDispose<List<MatchModel>>((ref) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(const <MatchModel>[]);
  return ref.watch(matchesRepositoryProvider).watchMatches(uid);
});

/// Live messages for one match, scoped to the signed-in account so a sign-out
/// inside the same app session cannot keep streaming the previous chat.
final messagesProvider = StreamProvider.autoDispose
    .family<List<MessageModel>, String>((ref, matchId) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(const <MessageModel>[]);
  return ref.watch(matchesRepositoryProvider).watchMessages(matchId);
});
