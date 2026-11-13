import '../../../core/domain/property_type.dart';

export '../../../core/domain/property_type.dart';

enum ListingStatus {
  available,
  reserved,
  full,
}

/// A place an account has published. Any account can own listings; there is no
/// separate owner account type.
class ListingModel {
  final String id;
  final String ownerUid;
  final String title;
  final String description;
  final double monthlyRent;
  final PropertyType propertyType;
  final List<String> photos;
  final List<String> amenities;
  final double latitude;
  final double longitude;
  final ListingStatus status;
  final DateTime createdAt;

  const ListingModel({
    required this.id,
    required this.ownerUid,
    required this.title,
    required this.description,
    required this.monthlyRent,
    required this.propertyType,
    this.photos = const [],
    this.amenities = const [],
    required this.latitude,
    required this.longitude,
    this.status = ListingStatus.available,
    required this.createdAt,
  });

  bool isOwnedBy(String? uid) => uid != null && uid == ownerUid;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerUid': ownerUid,
      'title': title,
      'description': description,
      'monthlyRent': monthlyRent,
      'propertyType': propertyType.name,
      'photos': photos,
      'amenities': amenities,
      'latitude': latitude,
      'longitude': longitude,
      'status': status.name,
      'createdAt': createdAt.millisecondsSinceEpoch,
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
    );
  }

  ListingModel copyWith({
    String? title,
    String? description,
    double? monthlyRent,
    PropertyType? propertyType,
    List<String>? photos,
    List<String>? amenities,
    ListingStatus? status,
  }) {
    return ListingModel(
      id: id,
      ownerUid: ownerUid,
      title: title ?? this.title,
      description: description ?? this.description,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      propertyType: propertyType ?? this.propertyType,
      photos: photos ?? this.photos,
      amenities: amenities ?? this.amenities,
      latitude: latitude,
      longitude: longitude,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}

enum LikeStatus {
  pending,
  approved,
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
