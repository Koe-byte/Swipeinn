import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_service.dart';
import '../../matches/domain/match_model.dart';
import '../domain/listing_model.dart';

final listingsRepositoryProvider = Provider<ListingsRepository>((ref) {
  return SupabaseListingsRepository();
});

/// Listings, the likes attached to them, and the status of a published place.
abstract class ListingsRepository {
  /// Every published listing, including the signed-in account's own places and
  /// excluding soft-deleted ones. Screens remove their own places before
  /// showing a deck.
  Stream<List<ListingModel>> watchAllListings();

  Stream<List<ListingModel>> watchListingsByOwner(String ownerUid);

  /// One listing by ID, kept live. Emits `null` when the document is gone or
  /// has been soft-deleted.
  Stream<ListingModel?> watchListing(String listingId);

  /// Interest that has not been approved yet, oldest first.
  Stream<List<ListingLike>> watchPendingLikes(String listingId);

  Future<void> publish(ListingModel listing);

  /// Applies owner edits without replacing fields the editor did not touch.
  Future<void> updateListing(ListingModel listing);

  Future<void> updateStatus(String listingId, ListingStatus status);

  /// Soft-deletes the listing. The row, its likes and its conversations are
  /// kept. Returns `false` when the cloud update could not be confirmed.
  Future<bool> deleteListing(String listingId);

  /// Sends a pending like. Returns `false` when only the local mirror changed.
  Future<bool> like({
    required String listingId,
    required String requesterUid,
    required String requesterName,
  });

  /// Records a private "not for me" on one listing.
  ///
  /// Passes are stored in their own actor-private table, so the owner can never
  /// see who passed on their place. Returns `false` when only the local mirror
  /// changed.
  Future<bool> pass({
    required String listingId,
    required String requesterUid,
  });

  /// Removes a pass so the card can return to Discover.
  Future<bool> undoPass({
    required String listingId,
    required String requesterUid,
  });

  /// Listing IDs the account has passed on, live.
  Stream<Set<String>> watchPassedListingIds(String requesterUid);

  /// Listing IDs the account already liked, whatever the owner decided. A card
  /// with any interest row is never dealt again.
  Stream<Set<String>> watchLikedListingIds(String requesterUid);

  /// Rejects a pending like. The renter's Discover hides the card, but the row
  /// is kept so the decision is not lost.
  Future<bool> rejectInterest({
    required String listingId,
    required String requesterUid,
  });

  /// Moves a rejected like back into the owner's pending queue.
  Future<bool> reopenInterest({
    required String listingId,
    required String requesterUid,
  });

  /// Creates the match and closes the like in one database transaction.
  ///
  /// [match] is the snapshot the caller wants to cache locally. Returns `false`
  /// when only the local mirror changed.
  Future<bool> approveInterest({required MatchModel match});

  Future<void> markLikeApproved({
    required String listingId,
    required String requesterUid,
  });
}

class SupabaseListingsRepository implements ListingsRepository {
  final DatabaseService _db = DatabaseService.instance;

  static bool _isMissingRpc(PostgrestException error) {
    // PGRST202 is "function not found"; 42883 is the raw Postgres equivalent.
    return error.code == 'PGRST202' || error.code == '42883';
  }

  static String _rpcMessage(PostgrestException error) {
    final message = error.message.trim();
    return message.isEmpty ? 'The server rejected that request.' : message;
  }

  @override
  Stream<List<ListingModel>> watchAllListings() {
    return _db.streamCollection(collection: 'listings').map((docs) {
      final listings = docs
          .map((map) => ListingModel.fromMap(map, map['id'] as String? ?? ''))
          .where((listing) => listing.id.isNotEmpty && !listing.isDeleted)
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
          .where((listing) => listing.id.isNotEmpty && !listing.isDeleted)
          .toList();
      listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return listings;
    });
  }

  @override
  Stream<ListingModel?> watchListing(String listingId) {
    return _db
        .streamDocument(collection: 'listings', docId: listingId)
        .map((map) {
      if (map == null) return null;
      final listing = ListingModel.fromMap(map, listingId);
      if (listing.id.isEmpty || listing.isDeleted) return null;
      return listing;
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
  Future<void> updateListing(ListingModel listing) async {
    await _db.setDocument(
      collection: 'listings',
      docId: listing.id,
      data: {
        ...listing.toMap(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
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
  Future<bool> deleteListing(String listingId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.setDocument(
      collection: 'listings',
      docId: listingId,
      data: {
        'deletedAt': now,
        'updatedAt': now,
      },
    );
  }

  @override
  Future<bool> like({
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
    if (existing != null) return true;

    final like = ListingLike(
      listingId: listingId,
      requesterUid: requesterUid,
      requesterName: requesterName,
      likedAt: DateTime.now(),
    );
    final synced = await _db.setSubdocument(
      parentCollection: 'listings',
      parentId: listingId,
      subcollection: 'likes',
      docId: requesterUid,
      data: like.toMap(),
    );

    // The discover deck reads the root table, while the owner queue reads the
    // subcollection view. Mirror the row so both agree offline and after a
    // restart.
    await _db.cacheDocumentLocally(
      collection: 'listing_likes',
      docId: listingId,
      data: {
        ...like.toMap(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
    return synced;
  }

  @override
  Future<bool> pass({
    required String listingId,
    required String requesterUid,
  }) {
    final pass = ListingPass(
      listingId: listingId,
      requesterUid: requesterUid,
      passedAt: DateTime.now(),
    );
    return _db.setDocument(
      collection: 'listing_passes',
      docId: pass.id,
      data: pass.toMap(),
      merge: false,
    );
  }

  @override
  Future<bool> undoPass({
    required String listingId,
    required String requesterUid,
  }) {
    return _db.deleteDocument(
      collection: 'listing_passes',
      docId: ListingPass.idFor(listingId, requesterUid),
    );
  }

  @override
  Stream<Set<String>> watchPassedListingIds(String requesterUid) {
    return _db
        .streamCollection(
      collection: 'listing_passes',
      whereField: 'requesterUid',
      isEqualTo: requesterUid,
    )
        .map((docs) {
      return docs
          .map((map) => map['listingId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    });
  }

  @override
  Stream<Set<String>> watchLikedListingIds(String requesterUid) {
    return _db
        .streamCollection(
      collection: 'listing_likes',
      whereField: 'requesterUid',
      isEqualTo: requesterUid,
    )
        .map((docs) {
      return docs
          .map((map) => map['listingId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    });
  }

  @override
  Future<bool> rejectInterest({
    required String listingId,
    required String requesterUid,
  }) {
    return _db.setSubdocument(
      parentCollection: 'listings',
      parentId: listingId,
      subcollection: 'likes',
      docId: requesterUid,
      data: {'status': LikeStatus.rejected.name},
    );
  }

  @override
  Future<bool> reopenInterest({
    required String listingId,
    required String requesterUid,
  }) {
    return _db.setSubdocument(
      parentCollection: 'listings',
      parentId: listingId,
      subcollection: 'likes',
      docId: requesterUid,
      data: {'status': LikeStatus.pending.name},
    );
  }

  @override
  Future<bool> approveInterest({required MatchModel match}) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    Future<void> cacheApproved() async {
      await _db.cacheDocumentLocally(
        collection: 'matches',
        docId: match.id,
        data: {
          ...match.toMap(),
          'updatedAt': now,
        },
      );
      _db.cacheSubdocumentLocally(
        parentCollection: 'listings',
        parentId: match.listingId,
        subcollection: 'likes',
        docId: match.requesterUid,
        data: {
          'status': LikeStatus.approved.name,
          'approvedAt': now,
        },
      );
    }

    if (_db.isSupabaseAvailable) {
      try {
        await _db.callRpc('approve_interest', params: {
          'p_listing_id': match.listingId,
          'p_requester_uid': match.requesterUid,
        });
        await cacheApproved();
        return true;
      } on PostgrestException catch (error) {
        if (!_isMissingRpc(error)) {
          throw StateError(_rpcMessage(error));
        }
        debugPrint(
          '[ListingsRepository] approve_interest is missing; falling back to '
          'separate writes. Apply 0006 to make approval atomic.',
        );
      } catch (error) {
        debugPrint(
          '[ListingsRepository] approve_interest failed; queuing the local '
          'writes: $error',
        );
      }
    }

    // Legacy/unmigrated path. It still caches locally and queues both writes,
    // but the two rows can drift until the queued replay completes.
    final created = await _db.setDocument(
      collection: 'matches',
      docId: match.id,
      data: {
        ...match.toMap(),
        'updatedAt': now,
      },
    );
    final approved = await _db.setSubdocument(
      parentCollection: 'listings',
      parentId: match.listingId,
      subcollection: 'likes',
      docId: match.requesterUid,
      data: {
        'status': LikeStatus.approved.name,
        'approvedAt': now,
      },
    );
    return created && approved;
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
