import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_provider.dart';
import '../data/listings_repository.dart';
import '../domain/listing_model.dart';

export '../data/listings_repository.dart' show listingsRepositoryProvider;

/// Everything published by every account.
///
/// The provider is scoped to the signed-in account on purpose. Without the
/// [uid] dependency it survives a sign-out inside the same app session and
/// keeps the previous account's Realtime subscription and cached deck, so the
/// new account's Discover can stay stuck on the old feed.
final discoverListingsProvider =
    StreamProvider.autoDispose<List<ListingModel>>((ref) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(const <ListingModel>[]);
  return ref.watch(listingsRepositoryProvider).watchAllListings();
});

/// The signed-in account's published places.
final myListingsProvider =
    StreamProvider.autoDispose<List<ListingModel>>((ref) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(const <ListingModel>[]);
  return ref.watch(listingsRepositoryProvider).watchListingsByOwner(uid);
});

/// Pending interest for one listing, shown in the owner's Review Queue.
/// Scoped to the signed-in account so a previous owner's queue cannot linger
/// after an account switch.
final pendingLikesProvider = StreamProvider.autoDispose
    .family<List<ListingLike>, String>((ref, listingId) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(const <ListingLike>[]);
  return ref.watch(listingsRepositoryProvider).watchPendingLikes(listingId);
});

/// Listings the signed-in account already liked. Any status counts: pending
/// waits for the owner, approved became a match, rejected was closed. None of
/// them should be dealt again.
final likedListingIdsProvider =
    StreamProvider.autoDispose<Set<String>>((ref) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(const <String>{});
  return ref.watch(listingsRepositoryProvider).watchLikedListingIds(uid);
});

/// Listings the signed-in account passed on. Private: the owner never sees it.
final passedListingIdsProvider =
    StreamProvider.autoDispose<Set<String>>((ref) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(const <String>{});
  return ref.watch(listingsRepositoryProvider).watchPassedListingIds(uid);
});

/// One live listing, used by the detail and editor screens.
final listingProvider =
    StreamProvider.autoDispose.family<ListingModel?, String>((ref, listingId) {
  final uid = ref.watch(authStateProvider.select((state) => state.user?.uid));
  if (uid == null) return Stream.value(null);
  return ref.watch(listingsRepositoryProvider).watchListing(listingId);
});
