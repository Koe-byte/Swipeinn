enum ListingStatus {
  available,
  reserved,
  full,
}

enum RoomType {
  solo,
  studio,
  bedspace,
}

class ListingModel {
  final String id;
  final String landlordUid;
  final String title;
  final String description;
  final double monthlyRent;
  final RoomType roomType;
  final List<String> photos;
  final List<String> amenities;
  final double latitude;
  final double longitude;
  final ListingStatus status;
  final DateTime createdAt;

  const ListingModel({
    required this.id,
    required this.landlordUid,
    required this.title,
    required this.description,
    required this.monthlyRent,
    required this.roomType,
    this.photos = const [],
    this.amenities = const [],
    required this.latitude,
    required this.longitude,
    this.status = ListingStatus.available,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'landlordUid': landlordUid,
      'title': title,
      'description': description,
      'monthlyRent': monthlyRent,
      'roomType': roomType.name,
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
      landlordUid: map['landlordUid'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      monthlyRent: (map['monthlyRent'] as num?)?.toDouble() ?? 0.0,
      roomType: RoomType.values.firstWhere(
        (e) => e.name == map['roomType'],
        orElse: () => RoomType.solo,
      ),
      photos: List<String>.from(map['photos'] ?? []),
      amenities: List<String>.from(map['amenities'] ?? []),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 14.6091,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 120.9899,
      status: ListingStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ListingStatus.available,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  ListingModel copyWith({
    String? title,
    String? description,
    double? monthlyRent,
    RoomType? roomType,
    List<String>? photos,
    List<String>? amenities,
    ListingStatus? status,
  }) {
    return ListingModel(
      id: id,
      landlordUid: landlordUid,
      title: title ?? this.title,
      description: description ?? this.description,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      roomType: roomType ?? this.roomType,
      photos: photos ?? this.photos,
      amenities: amenities ?? this.amenities,
      latitude: latitude,
      longitude: longitude,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
