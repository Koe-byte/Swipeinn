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

/// A conversation opened when an owner approves a requester's interest.
/// One deterministic match exists per listing and requester.
class MatchModel {
  final String id; // "${listingId}_${requesterUid}"
  final String listingId;

  /// Snapshot so both sides can render the match even though only the owner
  /// has the listing in their own listings stream.
  final String listingTitle;

  final String ownerUid;
  final String requesterUid;

  /// Stored so Firestore can answer "matches for me" with one array-contains
  /// query instead of two OR queries.
  final List<String> participantUids;

  final MatchStatus status;
  final DateTime matchedAt;

  /// Kept for a future renewal flow. Expiry is disabled in v1, so a
  /// conversation stays open until it is explicitly closed.
  final DateTime expiresAt;

  final int messagesCount;
  final String lastMessage;
  final ViewingStatus viewingStatus;
  final DateTime? viewingDate;

  const MatchModel({
    required this.id,
    required this.listingId,
    this.listingTitle = '',
    required this.ownerUid,
    required this.requesterUid,
    this.participantUids = const [],
    this.status = MatchStatus.active,
    required this.matchedAt,
    required this.expiresAt,
    this.messagesCount = 0,
    this.lastMessage = '',
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

  List<String> get resolvedParticipantUids =>
      participantUids.isEmpty ? [ownerUid, requesterUid] : participantUids;

  bool isParticipant(String? uid) =>
      uid != null && resolvedParticipantUids.contains(uid);

  String get displayTitle =>
      listingTitle.trim().isEmpty ? 'Listing' : listingTitle;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'listingId': listingId,
      'listingTitle': listingTitle,
      'ownerUid': ownerUid,
      'requesterUid': requesterUid,
      'participantUids': resolvedParticipantUids,
      'status': status.name,
      'matchedAt': matchedAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'messagesCount': messagesCount,
      'lastMessage': lastMessage,
      'viewingStatus': viewingStatus.name,
      'viewingDate': viewingDate?.millisecondsSinceEpoch,
    };
  }

  factory MatchModel.fromMap(Map<String, dynamic> map, String id) {
    // Demo-era documents used studentUid/landlordUid. Reading both keeps any
    // cached conversation from disappearing after the Phase 2 migration.
    final ownerUid =
        map['ownerUid'] as String? ?? map['landlordUid'] as String? ?? '';
    final requesterUid =
        map['requesterUid'] as String? ?? map['studentUid'] as String? ?? '';
    final participants = List<String>.from(
      map['participantUids'] ?? const <String>[],
    );

    return MatchModel(
      id: id,
      listingId: map['listingId'] as String? ?? '',
      listingTitle: map['listingTitle'] as String? ?? '',
      ownerUid: ownerUid,
      requesterUid: requesterUid,
      participantUids:
          participants.isEmpty ? [ownerUid, requesterUid] : participants,
      status: MatchStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MatchStatus.active,
      ),
      matchedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['matchedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (map['expiresAt'] as num?)?.toInt() ??
            DateTime.now()
                .add(const Duration(hours: 24))
                .millisecondsSinceEpoch,
      ),
      messagesCount: (map['messagesCount'] as num?)?.toInt() ?? 0,
      lastMessage: map['lastMessage'] as String? ?? '',
      viewingStatus: ViewingStatus.values.firstWhere(
        (e) => e.name == map['viewingStatus'],
        orElse: () => ViewingStatus.none,
      ),
      viewingDate: map['viewingDate'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['viewingDate'] as num).toInt())
          : null,
    );
  }

  MatchModel copyWith({
    MatchStatus? status,
    int? messagesCount,
    String? lastMessage,
    ViewingStatus? viewingStatus,
    DateTime? viewingDate,
  }) {
    return MatchModel(
      id: id,
      listingId: listingId,
      listingTitle: listingTitle,
      ownerUid: ownerUid,
      requesterUid: requesterUid,
      participantUids: participantUids,
      status: status ?? this.status,
      matchedAt: matchedAt,
      expiresAt: expiresAt,
      messagesCount: messagesCount ?? this.messagesCount,
      lastMessage: lastMessage ?? this.lastMessage,
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
      senderUid: map['senderUid'] as String? ?? '',
      text: map['text'] as String? ?? '',
      type: map['type'] == 'viewingProposal'
          ? MessageType.viewingProposal
          : MessageType.text,
      viewingDate: map['viewingDate'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['viewingDate'] as num).toInt())
          : null,
      proposalStatus: map['proposalStatus'] as String? ?? 'pending',
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        (map['sentAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
