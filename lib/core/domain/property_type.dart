/// The kinds of home Swipeinn supports. One enum is shared by onboarding
/// preferences and published listings so a filter can never drift from what an
/// owner is allowed to publish.
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

  /// Reads the Phase 2 field first and falls back to the demo-era `roomType`
  /// values (`solo`, `studio`, `bedspace`) so cached documents still load.
  static PropertyType fromLegacy(Object? propertyType, Object? roomType) {
    final current = fromName(propertyType);
    if (current != null) return current;
    if (roomType == 'solo') return PropertyType.room;
    return fromName(roomType) ?? PropertyType.room;
  }
}
