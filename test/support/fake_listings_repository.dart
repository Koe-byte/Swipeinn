import 'dart:async';

import 'package:swipeinn/features/listings/data/listings_repository.dart';
import 'package:swipeinn/features/listings/domain/listing_model.dart';

/// In-memory listings and likes for offline widget tests.
class FakeListingsRepository implements ListingsRepository {
  final Map<String, ListingModel> listings = {};
  final Map<String, Map<String, ListingLike>> likes = {};

  final _listingsController = StreamController<void>.broadcast();
  final Map<String, StreamController<void>> _likeControllers = {};

  void seedListing(ListingModel listing) {
    listings[listing.id] = listing;
    _listingsController.add(null);
  }

  void seedLike(ListingLike like) {
    likes.putIfAbsent(like.listingId, () => {})[like.requesterUid] = like;
    _likeController(like.listingId).add(null);
  }

  StreamController<void> _likeController(String listingId) {
    return _likeControllers.putIfAbsent(
      listingId,
      () => StreamController<void>.broadcast(),
    );
  }

  List<ListingModel> _sorted(Iterable<ListingModel> source) {
    final result = source.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Stream<List<ListingModel>> watchAllListings() async* {
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
    ListingModel? current() => listings[listingId];

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
    listings.remove(listingId);
    _listingsController.add(null);
    return true;
  }

  @override
  Future<void> like({
    required String listingId,
    required String requesterUid,
    required String requesterName,
  }) async {
    if (likes[listingId]?.containsKey(requesterUid) == true) return;
    seedLike(
      ListingLike(
        listingId: listingId,
        requesterUid: requesterUid,
        requesterName: requesterName,
        likedAt: DateTime(2026, 1, 1),
      ),
    );
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
  }

  void dispose() {
    _listingsController.close();
    for (final controller in _likeControllers.values) {
      controller.close();
    }
  }
}
