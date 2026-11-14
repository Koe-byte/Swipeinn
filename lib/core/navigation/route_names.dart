import '../../features/listings/domain/listing_model.dart';

/// Named routes used by the account shell and the screens below it.
///
/// Arguments are typed wrappers instead of maps so a missing or wrong payload
/// fails at the route boundary rather than inside a screen build.
class AppRoutes {
  static const String listingDetail = '/listing';
  static const String listingEditor = '/listing/editor';
  static const String listingReviewQueue = '/listing/review';
  static const String preferencesEditor = '/preferences';
}

class ListingDetailArgs {
  final String listingId;

  const ListingDetailArgs({required this.listingId});
}

class ListingEditorArgs {
  /// Null starts a new listing; a model opens the editor in edit mode.
  final ListingModel? listing;

  const ListingEditorArgs({this.listing});
}

class ListingReviewQueueArgs {
  final ListingModel listing;

  const ListingReviewQueueArgs({required this.listing});
}
