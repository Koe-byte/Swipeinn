/// What kind of home a renter is looking for.
enum PropertyType {
  room('Room'),
  bedspace('Bedspace'),
  studio('Studio'),
  apartment('Apartment'),
  condo('Condo'),
  house('House');

  const PropertyType(this.label);

  final String label;

  static PropertyType? fromName(Object? value) {
    if (value is! String) return null;
    for (final type in PropertyType.values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// How soon a renter wants to move in.
enum MoveInWindow {
  asap('As soon as possible'),
  withinMonth('Within a month'),
  oneToThreeMonths('In 1–3 months'),
  flexible('Flexible');

  const MoveInWindow(this.label);

  final String label;

  static MoveInWindow? fromName(Object? value) {
    if (value is! String) return null;
    for (final window in MoveInWindow.values) {
      if (window.name == value) return window;
    }
    return null;
  }
}

/// The two-step onboarding answers. Every account has one, whether the person
/// is browsing, listing a place, or both.
class RenterPreferences {
  final List<PropertyType> propertyTypes;
  final int budgetMin;
  final int budgetMax;
  final List<String> areas;
  final MoveInWindow moveInWindow;

  const RenterPreferences({
    this.propertyTypes = const [],
    this.budgetMin = 3000,
    this.budgetMax = 15000,
    this.areas = const [],
    this.moveInWindow = MoveInWindow.flexible,
  });

  bool get isComplete => propertyTypes.isNotEmpty && budgetMax > 0;

  Map<String, dynamic> toMap() {
    return {
      'propertyTypes': propertyTypes.map((type) => type.name).toList(),
      'budgetMin': budgetMin,
      'budgetMax': budgetMax,
      'areas': areas,
      'moveInWindow': moveInWindow.name,
    };
  }

  factory RenterPreferences.fromMap(Map<String, dynamic> map) {
    return RenterPreferences(
      propertyTypes: (map['propertyTypes'] as List? ?? const [])
          .map(PropertyType.fromName)
          .whereType<PropertyType>()
          .toList(),
      budgetMin: (map['budgetMin'] as num?)?.toInt() ?? 3000,
      budgetMax: (map['budgetMax'] as num?)?.toInt() ?? 15000,
      areas: List<String>.from(map['areas'] ?? const []),
      moveInWindow:
          MoveInWindow.fromName(map['moveInWindow']) ?? MoveInWindow.flexible,
    );
  }

  RenterPreferences copyWith({
    List<PropertyType>? propertyTypes,
    int? budgetMin,
    int? budgetMax,
    List<String>? areas,
    MoveInWindow? moveInWindow,
  }) {
    return RenterPreferences(
      propertyTypes: propertyTypes ?? this.propertyTypes,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      areas: areas ?? this.areas,
      moveInWindow: moveInWindow ?? this.moveInWindow,
    );
  }
}

/// A Swipeinn account. One account can browse places and publish listings; the
/// only trust distinction is the admin-granted owner badge.
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String photoUrl;
  final String authProvider;

  /// Granted manually by an admin to property owners. This is a trust signal,
  /// never a permission gate: any account can publish a listing without it.
  final bool isOwnerVerified;

  final bool hasCompletedOnboarding;
  final RenterPreferences? preferences;
  final int createdAt;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl = '',
    this.authProvider = 'password',
    this.isOwnerVerified = false,
    this.hasCompletedOnboarding = false,
    this.preferences,
    this.createdAt = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'authProvider': authProvider,
      'isOwnerVerified': isOwnerVerified,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'preferences': preferences?.toMap(),
      'createdAt': createdAt,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    final preferences = map['preferences'];
    return UserModel(
      uid: id,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      authProvider: map['authProvider'] as String? ?? 'password',
      isOwnerVerified: map['isOwnerVerified'] as bool? ?? false,
      hasCompletedOnboarding: map['hasCompletedOnboarding'] as bool? ?? false,
      preferences: preferences is Map
          ? RenterPreferences.fromMap(Map<String, dynamic>.from(preferences))
          : null,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? authProvider,
    bool? isOwnerVerified,
    bool? hasCompletedOnboarding,
    RenterPreferences? preferences,
    int? createdAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      authProvider: authProvider ?? this.authProvider,
      isOwnerVerified: isOwnerVerified ?? this.isOwnerVerified,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      preferences: preferences ?? this.preferences,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
