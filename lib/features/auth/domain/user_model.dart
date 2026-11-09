enum UserRole {
  student,
  landlord,
}

class StudentDemographics {
  final int paxCount;
  final bool isGroupSearch;
  final String genderPolicy; // 'any', 'female_only', 'male_only', 'mixed'
  final List<String> houseRules;
  final List<String> nearbyEssentials;

  const StudentDemographics({
    this.paxCount = 1,
    this.isGroupSearch = false,
    this.genderPolicy = 'any',
    this.houseRules = const [],
    this.nearbyEssentials = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'paxCount': paxCount,
      'isGroupSearch': isGroupSearch,
      'genderPolicy': genderPolicy,
      'houseRules': houseRules,
      'nearbyEssentials': nearbyEssentials,
    };
  }

  factory StudentDemographics.fromMap(Map<String, dynamic> map) {
    return StudentDemographics(
      paxCount: map['paxCount'] as int? ?? 1,
      isGroupSearch: map['isGroupSearch'] as bool? ?? false,
      genderPolicy: map['genderPolicy'] as String? ?? 'any',
      houseRules: List<String>.from(map['houseRules'] ?? []),
      nearbyEssentials: List<String>.from(map['nearbyEssentials'] ?? []),
    );
  }

  StudentDemographics copyWith({
    int? paxCount,
    bool? isGroupSearch,
    String? genderPolicy,
    List<String>? houseRules,
    List<String>? nearbyEssentials,
  }) {
    return StudentDemographics(
      paxCount: paxCount ?? this.paxCount,
      isGroupSearch: isGroupSearch ?? this.isGroupSearch,
      genderPolicy: genderPolicy ?? this.genderPolicy,
      houseRules: houseRules ?? this.houseRules,
      nearbyEssentials: nearbyEssentials ?? this.nearbyEssentials,
    );
  }
}

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String photoUrl;
  final UserRole role;
  final bool isVerified;
  final String school;
  final double budgetMax;
  final List<String> lifestyleTags;
  final String bio;
  final String authProvider;
  final bool hasCompletedOnboarding;
  final StudentDemographics? demographics;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl = '',
    required this.role,
    this.isVerified = false,
    this.school = '',
    this.budgetMax = 5000.0,
    this.lifestyleTags = const [],
    this.bio = '',
    this.authProvider = 'email',
    this.hasCompletedOnboarding = true,
    this.demographics,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role.name,
      'isVerified': isVerified,
      'school': school,
      'budgetMax': budgetMax,
      'lifestyleTags': lifestyleTags,
      'bio': bio,
      'authProvider': authProvider,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'demographics': demographics?.toMap(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      uid: id,
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
      role: map['role'] == 'landlord' ? UserRole.landlord : UserRole.student,
      isVerified: map['isVerified'] ?? false,
      school: map['school'] ?? '',
      budgetMax: (map['budgetMax'] as num?)?.toDouble() ?? 5000.0,
      lifestyleTags: List<String>.from(map['lifestyleTags'] ?? []),
      bio: map['bio'] ?? '',
      authProvider: map['authProvider'] ?? 'email',
      hasCompletedOnboarding: map['hasCompletedOnboarding'] ?? true,
      demographics: map['demographics'] != null
          ? StudentDemographics.fromMap(Map<String, dynamic>.from(map['demographics']))
          : null,
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    UserRole? role,
    bool? isVerified,
    String? school,
    double? budgetMax,
    List<String>? lifestyleTags,
    String? bio,
    String? authProvider,
    bool? hasCompletedOnboarding,
    StudentDemographics? demographics,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      school: school ?? this.school,
      budgetMax: budgetMax ?? this.budgetMax,
      lifestyleTags: lifestyleTags ?? this.lifestyleTags,
      bio: bio ?? this.bio,
      authProvider: authProvider ?? this.authProvider,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      demographics: demographics ?? this.demographics,
    );
  }
}
