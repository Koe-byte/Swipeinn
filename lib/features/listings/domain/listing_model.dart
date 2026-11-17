import '../../../core/domain/property_type.dart';

export '../../../core/domain/property_type.dart';

enum ListingStatus {
  available,
  reserved,
  full,
}

/// Amenities the publish/edit form offers. Stored as free-form strings, so the
/// list can grow without a schema change.
const List<String> listingAmenityOptions = [
  'Wi-Fi',
  'Aircon',
  'Water included',
  'Furnished',
  'Parking',
  'Laundry area',
  'Kitchen',
  'Private CR',
  'Pet friendly',
];

/// A place an account has published. Any account can own listings; there is no
/// separate owner account type.
class ListingModel {
  final String id;
  final String ownerUid;
  final String title;
  final String description;
  final double monthlyRent;
  final PropertyType propertyType;

  /// How many people the place can accommodate. Old rows predate the field and
  /// read as 1 so the card always has something honest to show.
  final int capacity;

  final List<String> photos;
  final List<String> amenities;
  final double latitude;
  final double longitude;
  final ListingStatus status;
  final DateTime createdAt;

  /// Set when the owner removes the place. The row stays so existing matches,
  /// messages and viewing history keep working.
  final DateTime? deletedAt;

  const ListingModel({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.description,
    required this.monthlyRent,
    required this.propertyType,
    this.capacity = 1,
    this.photos = const [],
    this.amenities = const [],
    required this.latitude,
    required this.longitude,
    this.status = ListingStatus.available,
    required this.createdAt,
    this.deletedAt,
  });

  bool isOwnedBy(String? uid) => uid != null && uid == ownerUid;

  bool get isDeleted => deletedAt != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerUid': ownerUid,
      'title': title,
      'description': description,
      'monthlyRent': monthlyRent,
      'propertyType': propertyType.name,
      'capacity': capacity,
      'photos': photos,
      'amenities': amenities,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.name,
      'createdAt': createdAt.millisecondsSinceEpoch,
      if (deletedAt != null) 'deletedAt': deletedAt!.millisecondsSinceEpoch,
    };
  }

  factory ListingModel.fromMap(Map<String, dynamic> map, String id) {
    return ListingModel(
      id: id,
      // `landlordUid` is the demo-era name; read it so cached cards survive.
      ownerUid:
          map['ownerUid'] as String? ?? map['landlordUid'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      monthlyRent: (map['monthlyRent'] as num?)?.toDouble() ?? 0.0,
      propertyType: PropertyType.fromLegacy(
        map['propertyType'],
        map['roomType'],
      ),
      capacity: (map['capacity'] as num?)?.toInt() ?? 1,
      photos: List<String>.from(map['photos'] ?? const []),
      amenities: List<String>.from(map['amenities'] ?? const []),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 14.6091,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 120.9899,
      status: ListingStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ListingStatus.available,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      deletedAt: map['deletedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['deletedAt'] as num).toInt())
          : null,
    );
  }

  ListingModel copyWith({
    String? title,
    String? description,
    double? monthlyRent,
    PropertyType? propertyType,
    int? capacity,
    List<String>? photos,
    List<String>? amenities,
    ListingStatus? status,
    DateTime? deletedAt,
  }) {
    return ListingModel(
      id: id,
      ownerUid: ownerUid,
      title: title ?? this.title,
      description: description ?? this.description,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      propertyType: propertyType ?? this.propertyType,
      capacity: capacity ?? this.capacity,
      photos: photos ?? this.photos,
      amenities: amenities ?? this.amenities,
      latitude: latitude,
      longitude: longitude,
      status: status ?? this.status,
      createdAt: createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

enum LikeStatus {
  pending,
  approved,
  rejected,
}

/// One account's interest in one listing. The document ID is the requester's
/// UID, so a person can only express interest once per place.
class ListingLike {
  final String listingId;
  final String requesterUid;
  final String requesterName;
  final DateTime likedAt;
  final LikeStatus status;
  final DateTime? approvedAt;

  const ListingLike({
    required this.listingId,
    required this.requesterUid,
    required this.requesterName,
    required this.likedAt,
    this.status = LikeStatus.pending,
    this.approvedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'listingId': listingId,
      'requesterUid': requesterUid,
      'requesterName': requesterName,
      'likedAt': likedAt.millisecondsSinceEpoch,
      'status': status.name,
      'approvedAt': approvedAt?.millisecondsSinceEpoch,
    };
  }

  factory ListingLike.fromMap(
    Map<String, dynamic> map,
    String listingId,
    String requesterUid,
  ) {
    return ListingLike(
      listingId: listingId,
      requesterUid: map['requesterUid'] as String? ?? requesterUid,
      requesterName: map['requesterName'] as String? ?? '',
      likedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['likedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      status: LikeStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => LikeStatus.pending,
      ),
      approvedAt: map['approvedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['approvedAt'] as num).toInt())
          : null,
    );
  }

  String get displayName {
    if (requesterName.trim().isNotEmpty) return requesterName.trim();
    return requesterUid.length > 12
        ? 'Renter ${requesterUid.substring(requesterUid.length - 6)}'
        : requesterUid;
  }
}

/// A private "not for me" decision on one listing.
///
/// Passes never reach the owner: ADR 0003 keeps left swipes in an actor-private
/// store, unlike a like which is mirrored into the listing's review queue. The
/// document id is deterministic so [DatabaseService] can address it as a normal
/// single-key row.
class ListingPass {
  final String listingId;
  final String requesterUid;
  final DateTime passedAt;

  const ListingPass({
    required this.listingId,
    required this.requesterUid,
    required this.passedAt,
  });

  static String idFor(String listingId, String requesterUid) =>
      '${listingId}_$requesterUid';

  String get id => idFor(listingId, requesterUid);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'listingId': listingId,
      'requesterUid': requesterUid,
      'passedAt': passedAt.millisecondsSinceEpoch,
    };
  }
}
