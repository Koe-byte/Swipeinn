import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listing photo storage.
///
/// The bucket and the object path are deliberately identical to the layout the
/// old Firebase Storage rules described, so nothing in the listing model has to
/// change and a future provider swap stays path-preserving:
///
///   users/{uid}/listings/{listingId}/{fileName}
///
/// The bucket is public for reads, which is what makes `ListingModel.photos`
/// plain URLs. Writes are restricted by storage RLS to the uploader's own
/// folder, images only, 5 MB per file.
class PhotoStorageService {
  static final PhotoStorageService instance = PhotoStorageService._internal();

  PhotoStorageService._internal();

  static const String bucket = 'listing-photos';
  static const int maxBytes = 5 * 1024 * 1024;

  SupabaseClient get _client => Supabase.instance.client;

  /// Uploads one photo and returns its public URL.
  Future<String> uploadListingPhoto({
    required String ownerUid,
    required String listingId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.lengthInBytes > maxBytes) {
      throw StateError('That photo is larger than 5 MB.');
    }

    final path = objectPath(
      ownerUid: ownerUid,
      listingId: listingId,
      fileName: fileName,
    );

    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentTypeFor(fileName),
            cacheControl: '3600',
            upsert: true,
          ),
        );

    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Deletes an object by the public URL stored on the listing.
  ///
  /// Failures are swallowed on purpose: a listing edit must not fail because a
  /// file was already gone. The cost of a missed delete is an orphaned object,
  /// not corrupt data.
  Future<void> deletePhotoByUrl(String publicUrl) async {
    final path = objectPathFromUrl(publicUrl);
    if (path == null) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (error) {
      debugPrint('[PhotoStorage] Could not delete $path: $error');
    }
  }

  static String objectPath({
    required String ownerUid,
    required String listingId,
    required String fileName,
  }) {
    return 'users/$ownerUid/listings/$listingId/$fileName';
  }

  /// Reverse of [objectPath], used when a listing is edited or deleted.
  static String? objectPathFromUrl(String publicUrl) {
    const marker = '/object/public/$bucket/';
    final index = publicUrl.indexOf(marker);
    if (index < 0) return null;
    final path = publicUrl.substring(index + marker.length);
    return path.isEmpty ? null : path;
  }

  static String contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
}
