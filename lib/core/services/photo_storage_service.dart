import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Raised when Storage refuses an upload.
///
/// The message is written for the person using the app, so screens can show it
/// in a snackbar as-is; the provider's technical detail goes to the debug log.
class PhotoUploadException implements Exception {
  final String message;

  const PhotoUploadException(this.message);

  @override
  String toString() => message;
}

/// Photo storage for listings and profile pictures.
///
/// Both buckets are public for reads, which is what makes the URLs stored in
/// Postgres plain `https://...` strings. Writes are restricted by storage RLS
/// to the uploader's own folder:
///
///   listing-photos -> users/{uid}/listings/{listingId}/{fileName}
///   avatars        -> users/{uid}/avatar_{timestamp}.{ext}
///
/// The two paths differ only by bucket, so a single path-based policy checks
/// element 2 of `storage.foldername(name)` in both.
class PhotoStorageService {
  static final PhotoStorageService instance = PhotoStorageService._internal();

  PhotoStorageService._internal();

  static const String listingBucket = 'listing-photos';
  static const String avatarBucket = 'avatars';
  static const int maxBytes = 5 * 1024 * 1024;

  SupabaseClient get _client => Supabase.instance.client;

  /// Uploads one listing photo and returns its public URL.
  Future<String> uploadListingPhoto({
    required String ownerUid,
    required String listingId,
    required Uint8List bytes,
    required String fileName,
  }) {
    return _upload(
      bucket: listingBucket,
      path: objectPath(
        ownerUid: ownerUid,
        listingId: listingId,
        fileName: fileName,
      ),
      bytes: bytes,
      fileName: fileName,
      upsert: true,
    );
  }

  /// Uploads a profile picture under a fresh file name and returns its URL.
  ///
  /// A new name every time avoids serving a stale image from the CDN after an
  /// update; the previous object is deleted by the caller once the new URL is
  /// saved on the profile.
  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  }) {
    final name = avatarFileName(fileName);
    return _upload(
      bucket: avatarBucket,
      path: 'users/$uid/$name',
      bytes: bytes,
      fileName: name,
      upsert: false,
    );
  }

  Future<String> _upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String fileName,
    required bool upsert,
  }) async {
    if (bytes.lengthInBytes > maxBytes) {
      throw const PhotoUploadException('That photo is larger than 5 MB.');
    }

    try {
      await _client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentTypeFor(fileName),
              cacheControl: '3600',
              upsert: upsert,
            ),
          );
    } on StorageException catch (error) {
      throw _friendlyError(error, bucket: bucket, path: path);
    } on Exception catch (error) {
      debugPrint('[PhotoStorage] Upload failed ($bucket/$path): $error');
      throw const PhotoUploadException(
        'Could not upload the photo. Check your connection and try again.',
      );
    }

    return _client.storage.from(bucket).getPublicUrl(path);
  }

  static PhotoUploadException _friendlyError(
    StorageException error, {
    required String bucket,
    required String path,
  }) {
    debugPrint('[PhotoStorage] $bucket/$path rejected: $error');

    final status = int.tryParse(error.statusCode ?? '');
    if (status == 403 || error.error == 'Unauthorized') {
      return const PhotoUploadException(
        'Storage rejected the photo (permission denied). Apply '
        'supabase/migrations/0004_storage_avatars.sql, then try again.',
      );
    }
    if (status == 413 || error.message.toLowerCase().contains('too large')) {
      return const PhotoUploadException(
        'That photo is larger than the 5 MB limit.',
      );
    }
    return const PhotoUploadException(
      'Could not upload the photo. Check your connection and try again.',
    );
  }

  /// Deletes an object by the public URL stored on a listing or profile.
  ///
  /// Failures are swallowed on purpose: a save must not fail because a file was
  /// already gone. The cost of a missed delete is an orphaned object, not
  /// corrupt data.
  Future<void> deleteByUrl(
    String publicUrl, {
    String bucket = listingBucket,
  }) async {
    final path = objectPathFromUrl(publicUrl, bucket: bucket);
    if (path == null) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (error) {
      debugPrint('[PhotoStorage] Could not delete $bucket/$path: $error');
    }
  }

  Future<void> deletePhotoByUrl(String publicUrl) {
    return deleteByUrl(publicUrl);
  }

  Future<void> deleteAvatarByUrl(String publicUrl) {
    return deleteByUrl(publicUrl, bucket: avatarBucket);
  }

  static String objectPath({
    required String ownerUid,
    required String listingId,
    required String fileName,
  }) {
    return 'users/$ownerUid/listings/$listingId/$fileName';
  }

  /// Unique object name for an avatar. Mirrors the listing editor's naming so
  /// two picks in the same session cannot collide.
  static String avatarFileName(String original) {
    final dot = original.lastIndexOf('.');
    final extension = dot >= 0 ? original.substring(dot).toLowerCase() : '.jpg';
    return 'avatar_${DateTime.now().microsecondsSinceEpoch}$extension';
  }

  /// Reverse of [objectPath], used when a listing or avatar is replaced.
  static String? objectPathFromUrl(
    String publicUrl, {
    String bucket = listingBucket,
  }) {
    final marker = '/object/public/$bucket/';
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
