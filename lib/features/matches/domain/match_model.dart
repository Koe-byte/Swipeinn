enum MatchStatus {
  active,
  expired,
  unmatched,
}

enum ViewingStatus {
  none,
  proposed,
  confirmed,
  declined,
}

enum MessageType {
  text,
  viewingProposal,
}

class MatchModel {
  final String id; // deterministic "${listingId}_${studentUid}"
  final String listingId;
  final String landlordUid;
  final String studentUid;
  final MatchStatus status;
  final DateTime matchedAt;

  /// Kept for the Phase 2 renewal flow. Match expiry is disabled in v1, so a
  /// conversation stays open until it is explicitly closed.
  final DateTime expiresAt;
  final int messagesCount;
  final ViewingStatus viewingStatus;
  final DateTime? viewingDate;

  const MatchModel({
    required this.id,
    required this.listingId,
    required this.landlordUid,
    required this.studentUid,
    this.status = MatchStatus.active,
    required this.matchedAt,
    required this.expiresAt,
    this.messagesCount = 0,
    this.viewingStatus = ViewingStatus.none,
    this.viewingDate,
  });

  bool get isExpired {
    if (status == MatchStatus.expired) return true;
    // v1 has no match-renewal flow, so a silent 24-hour timeout would kill
    // conversations mid-demo. Only an explicit status change ends a match.
    return false;
  }

  Duration get remainingTime {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'listingId': listingId,
      'landlordUid': landlordUid,
      'studentUid': studentUid,
      'status': status.name,
      'matchedAt': matchedAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'messagesCount': messagesCount,
      'viewingStatus': viewingStatus.name,
      'viewingDate': viewingDate?.millisecondsSinceEpoch,
    };
  }

  factory MatchModel.fromMap(Map<String, dynamic> map, String id) {
    return MatchModel(
      id: id,
      listingId: map['listingId'] ?? '',
      landlordUid: map['landlordUid'] ?? '',
      studentUid: map['studentUid'] ?? '',
      status: MatchStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MatchStatus.active,
      ),
      matchedAt: DateTime.fromMillisecondsSinceEpoch(
        map['matchedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        map['expiresAt'] ??
            DateTime.now()
                .add(const Duration(hours: 24))
                .millisecondsSinceEpoch,
      ),
      messagesCount: map['messagesCount'] ?? 0,
      viewingStatus: ViewingStatus.values.firstWhere(
        (e) => e.name == map['viewingStatus'],
        orElse: () => ViewingStatus.none,
      ),
      viewingDate: map['viewingDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['viewingDate'])
          : null,
    );
  }

  MatchModel copyWith({
    MatchStatus? status,
    int? messagesCount,
    ViewingStatus? viewingStatus,
    DateTime? viewingDate,
  }) {
    return MatchModel(
      id: id,
      listingId: listingId,
      landlordUid: landlordUid,
      studentUid: studentUid,
      status: status ?? this.status,
      matchedAt: matchedAt,
      expiresAt: expiresAt,
      messagesCount: messagesCount ?? this.messagesCount,
      viewingStatus: viewingStatus ?? this.viewingStatus,
      viewingDate: viewingDate ?? this.viewingDate,
    );
  }
}

class MessageModel {
  final String id;
  final String senderUid;
  final String text;
  final MessageType type;
  final DateTime? viewingDate;
  final String proposalStatus; // "pending", "accepted", "declined"
  final DateTime sentAt;

  const MessageModel({
    required this.id,
    required this.senderUid,
    required this.text,
    this.type = MessageType.text,
    this.viewingDate,
    this.proposalStatus = 'pending',
    required this.sentAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderUid': senderUid,
      'text': text,
      'type': type.name,
      'viewingDate': viewingDate?.millisecondsSinceEpoch,
      'proposalStatus': proposalStatus,
      'sentAt': sentAt.millisecondsSinceEpoch,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    return MessageModel(
      id: id,
      senderUid: map['senderUid'] ?? '',
      text: map['text'] ?? '',
      type: map['type'] == 'viewingProposal'
          ? MessageType.viewingProposal
          : MessageType.text,
      viewingDate: map['viewingDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['viewingDate'])
          : null,
      proposalStatus: map['proposalStatus'] ?? 'pending',
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        map['sentAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
