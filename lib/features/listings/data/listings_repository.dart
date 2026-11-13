import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/database_service.dart';
import '../domain/listing_model.dart';

final listingsRepositoryProvider = Provider<ListingsRepository>((ref) {
  return FirestoreListingsRepository();
});

/// Listings, the likes attached to them, and the status of a published place.
abstract class ListingsRepository {
  /// Every published listing. Screens remove their own places before showing a
  /// deck.
  Stream<List<ListingModel>> watchAllListings();

  Stream<List<ListingModel>> watchListingsByOwner(String ownerUid);

  /// Interest that has not been approved yet, oldest first.
  Stream<List<ListingLike>> watchPendingLikes(String listingId);

  Future<void> publish(ListingModel listing);

  Future<void> updateStatus(String listingId, ListingStatus status);

  Future<void> like({
    required String listingId,
    required String requesterUid,
    required String requesterName,
  });

  Future<void> markLikeApproved({
    required String listingId,
    required String requesterUid,
  });
}

class FirestoreListingsRepository implements ListingsRepository {
  final DatabaseService _db = DatabaseService.instance;

  @override
  Stream<List<ListingModel>> watchAllListings() {
    return _db.streamCollection(collection: 'listings').map((docs) {
      final listings = docs
          .map((map) => ListingModel.fromMap(map, map['id'] as String? ?? ''))
          .where((listing) => listing.id.isNotEmpty)
          .toList();
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return listings;
    });
  }

  @override
  Stream<List<ListingModel>> watchListingsByOwner(String ownerUid) {
    return _db
        .streamCollection(
      collection: 'listings',
      whereField: 'ownerUid',
      isEqualTo: ownerUid,
    )
        .map((docs) {
      final listings = docs
          .map((map) => ListingModel.fromMap(map, map['id'] as String? ?? ''))
          .where((listing) => listing.id.isNotEmpty)
          .toList();
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return listings;
    });
  }

  @override
  Stream<List<ListingLike>> watchPendingLikes(String listingId) {
    return _db
        .streamSubcollection(
      parentCollection: 'listings',
      parentId: listingId,
      subcollection: 'likes',
    )
        .map((docs) {
      final likes = docs
          .map((map) => ListingLike.fromMap(
                map,
                listingId,
                map['requesterUid'] as String? ?? '',
              ))
          .where((like) =>
              like.status == LikeStatus.pending && like.requesterUid.isNotEmpty)
          .toList();
      likes.sort((a, b) => a.likedAt.compareTo(b.likedAt));
      return likes;
    });
  }

  @override
  Future<void> publish(ListingModel listing) async {
    await _db.setDocument(
      collection: 'listings',
      docId: listing.id,
      data: {
        ...listing.toMap(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      merge: false,
    );
  }

  @override
  Future<void> updateStatus(String listingId, ListingStatus status) async {
    await _db.setDocument(
      collection: 'listings',
      docId: listingId,
      data: {
        'status': status.name,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<void> like({
    required String listingId,
    required String requesterUid,
    required String requesterName,
  }) async {
    final existing = await _db.getSubdocument(
      parentCollection: 'listings',
      parentId: listingId,
      subcollection: 'likes',
      docId: requesterUid,
    );
    // Re-liking an approved place must not put it back in the review queue.
    if (existing != null) return;

    await _db.setSubdocument(
      parentCollection: 'listings',
      parentId: listingId,
      subcollection: 'likes',
      docId: requesterUid,
      data: ListingLike(
        listingId: listingId,
        requesterUid: requesterUid,
        requesterName: requesterName,
        likedAt: DateTime.now(),
      ).toMap(),
    );
  }

  @override
  Future<void> markLikeApproved({
    required String listingId,
    required String requesterUid,
  }) async {
    await _db.setSubdocument(
      parentCollection: 'listings',
      parentId: listingId,
      subcollection: 'likes',
      docId: requesterUid,
      data: {
        'status': LikeStatus.approved.name,
        'approvedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
}
