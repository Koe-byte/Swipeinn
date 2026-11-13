import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_provider.dart';
import '../data/listings_repository.dart';
import '../domain/listing_model.dart';

export '../data/listings_repository.dart' show listingsRepositoryProvider;

/// Everything published by every account. Discover filters out the current
/// account's own places before showing the deck.
final discoverListingsProvider = StreamProvider<List<ListingModel>>((ref) {
  return ref.watch(listingsRepositoryProvider).watchAllListings();
});

/// The signed-in account's published places.
final myListingsProvider = StreamProvider<List<ListingModel>>((ref) {
  final uid = ref.watch(authStateProvider).user?.uid;
  if (uid == null) return Stream.value(const <ListingModel>[]);
  return ref.watch(listingsRepositoryProvider).watchListingsByOwner(uid);
});

/// Pending interest for one listing, shown in the owner's Review Queue.
final pendingLikesProvider =
    StreamProvider.family<List<ListingLike>, String>((ref, listingId) {
  return ref.watch(listingsRepositoryProvider).watchPendingLikes(listingId);
});
