import 'dart:async';

import 'package:swipeinn/features/listings/data/listings_repository.dart';
import 'package:swipeinn/features/listings/domain/listing_model.dart';
import 'package:swipeinn/features/matches/domain/match_model.dart';

/// In-memory listings and likes for offline widget tests.
class FakeListingsRepository implements ListingsRepository {
  final Map<String, ListingModel> listings = {};
  final Map<String, Map<String, ListingLike>> likes = {};

  /// requesterUid -> listing IDs they passed on.
  final Map<String, Set<String>> passes = {};

  /// Mirrors the database function that creates the match. The widget test app
  /// wires this to its [FakeMatchesRepository].
  Future<void> Function(MatchModel match)? onMatchCreated;

  /// Number of times a whole-table stream has been opened. Used to prove that
  /// Discover re-subscribes after an account switch.
  int watchAllSubscriptions = 0;

  final _listingsController = StreamController<void>.broadcast();
  final _likeEvents = StreamController<void>.broadcast();
  final _passEvents = StreamController<void>.broadcast();
  final Map<String, StreamController<void>> _likeControllers = {};

  void seedListing(ListingModel listing) {
    listings[listing.id] = listing;
    _listingsController.add(null);
  }

  void seedLike(ListingLike like) {
    likes.putIfAbsent(like.listingId, () => {})[like.requesterUid] = like;
    _likeController(like.listingId).add(null);
    _likeEvents.add(null);
  }

  StreamController<void> _likeController(String listingId) {
    return _likeControllers.putIfAbsent(
      listingId,
      () => StreamController<void>.broadcast(),
    );
  }

  List<ListingModel> _sorted(Iterable<ListingModel> source) {
    final result = source.where((listing) => !listing.isDeleted).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Stream<List<ListingModel>> watchAllListings() async* {
    watchAllSubscriptions++;
    yield _sorted(listings.values);
    await for (final _ in _listingsController.stream) {
      yield _sorted(listings.values);
    }
  }

  @override
  Stream<List<ListingModel>> watchListingsByOwner(String ownerUid) async* {
    List<ListingModel> mine() => _sorted(
        listings.values.where((listing) => listing.ownerUid == ownerUid));

    yield mine();
    await for (final _ in _listingsController.stream) {
      yield mine();
    }
  }

  @override
  Stream<ListingModel?> watchListing(String listingId) async* {
    ListingModel? current() {
      final listing = listings[listingId];
      return listing == null || listing.isDeleted ? null : listing;
    }

    yield current();
    await for (final _ in _listingsController.stream) {
      yield current();
    }
  }

  @override
  Stream<List<ListingLike>> watchPendingLikes(String listingId) async* {
    List<ListingLike> pending() {
      final queue = likes[listingId]?.values ?? const <ListingLike>[];
      final result = queue
          .where((like) => like.status == LikeStatus.pending)
          .toList()
        ..sort((a, b) => a.likedAt.compareTo(b.likedAt));
      return result;
    }

    yield pending();
    await for (final _ in _likeController(listingId).stream) {
      yield pending();
    }
  }

  @override
  Future<void> publish(ListingModel listing) async {
    seedListing(listing);
  }

  @override
  Future<void> updateStatus(String listingId, ListingStatus status) async {
    final existing = listings[listingId];
    if (existing == null) return;
    listings[listingId] = existing.copyWith(status: status);
    _listingsController.add(null);
  }

  @override
  Future<void> updateListing(ListingModel listing) async {
    listings[listing.id] = listing;
    _listingsController.add(null);
  }

  @override
  Future<bool> deleteListing(String listingId) async {
    final existing = listings[listingId];
    if (existing == null) return false;
    listings[listingId] = existing.copyWith(deletedAt: DateTime(2026, 1, 2));
    _listingsController.add(null);
    return true;
  }

  @override
  Future<bool> like({
    required String listingId,
    required String requesterUid,
    required String requesterName,
  }) async {
    if (likes[listingId]?.containsKey(requesterUid) == true) return true;
    seedLike(
      ListingLike(
        listingId: listingId,
        requesterUid: requesterUid,
        requesterName: requesterName,
        likedAt: DateTime(2026, 1, 1),
      ),
    );
    return true;
  }

  @override
  Stream<Set<String>> watchLikedListingIds(String requesterUid) async* {
    Set<String> liked() => likes.entries
        .where((entry) => entry.value.containsKey(requesterUid))
        .map((entry) => entry.key)
        .toSet();

    yield liked();
    await for (final _ in _likeEvents.stream) {
      yield liked();
    }
  }

  @override
  Stream<Set<String>> watchPassedListingIds(String requesterUid) async* {
    Set<String> passed() => {...?passes[requesterUid]};

    yield passed();
    await for (final _ in _passEvents.stream) {
      yield passed();
    }
  }

  @override
  Future<bool> pass({
    required String listingId,
    required String requesterUid,
  }) async {
    passes.putIfAbsent(requesterUid, () => <String>{}).add(listingId);
    _passEvents.add(null);
    return true;
  }

  @override
  Future<bool> undoPass({
    required String listingId,
    required String requesterUid,
  }) async {
    passes[requesterUid]?.remove(listingId);
    _passEvents.add(null);
    return true;
  }

  @override
  Future<bool> rejectInterest({
    required String listingId,
    required String requesterUid,
  }) async {
    final existing = likes[listingId]?[requesterUid];
    if (existing == null) return false;
    likes[listingId]![requesterUid] = _withStatus(existing, LikeStatus.rejected);
    _likeController(listingId).add(null);
    _likeEvents.add(null);
    return true;
  }

  @override
  Future<bool> reopenInterest({
    required String listingId,
    required String requesterUid,
  }) async {
    final existing = likes[listingId]?[requesterUid];
    if (existing == null) return false;
    likes[listingId]![requesterUid] = _withStatus(existing, LikeStatus.pending);
    _likeController(listingId).add(null);
    _likeEvents.add(null);
    return true;
  }

  ListingLike _withStatus(ListingLike like, LikeStatus status) {
    return ListingLike(
      listingId: like.listingId,
      requesterUid: like.requesterUid,
      requesterName: like.requesterName,
      likedAt: like.likedAt,
      status: status,
      approvedAt: status == LikeStatus.approved ? DateTime(2026, 1, 2) : null,
    );
  }

  @override
  Future<bool> approveInterest({required MatchModel match}) async {
    final existing = likes[match.listingId]?[match.requesterUid];
    if (existing == null) return false;

    likes[match.listingId]![match.requesterUid] = ListingLike(
      listingId: existing.listingId,
      requesterUid: existing.requesterUid,
      requesterName: existing.requesterName,
      likedAt: existing.likedAt,
      status: LikeStatus.approved,
      approvedAt: DateTime(2026, 1, 2),
    );
    _likeController(match.listingId).add(null);
    _likeEvents.add(null);

    await onMatchCreated?.call(match);
    return true;
  }

  @override
  Future<void> markLikeApproved({
    required String listingId,
    required String requesterUid,
  }) async {
    final existing = likes[listingId]?[requesterUid];
    if (existing == null) return;
    likes[listingId]![requesterUid] = ListingLike(
      listingId: existing.listingId,
      requesterUid: existing.requesterUid,
      requesterName: existing.requesterName,
      likedAt: existing.likedAt,
      status: LikeStatus.approved,
      approvedAt: DateTime(2026, 1, 2),
    );
    _likeController(listingId).add(null);
    _likeEvents.add(null);
  }

  void dispose() {
    _listingsController.close();
    _likeEvents.close();
    _passEvents.close();
    for (final controller in _likeControllers.values) {
      controller.close();
    }
  }
}
