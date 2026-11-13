import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_provider.dart';
import '../data/matches_repository.dart';
import '../domain/match_model.dart';

export '../data/matches_repository.dart' show matchesRepositoryProvider;

/// Matches the signed-in account takes part in, on either side.
final matchesProvider = StreamProvider<List<MatchModel>>((ref) {
  final uid = ref.watch(authStateProvider).user?.uid;
  if (uid == null) return Stream.value(const <MatchModel>[]);
  return ref.watch(matchesRepositoryProvider).watchMatches(uid);
});

/// Live messages for one match.
final messagesProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, matchId) {
  return ref.watch(matchesRepositoryProvider).watchMessages(matchId);
});
