import 'package:flutter/material.dart';

import '../../features/auth/presentation/preferences_onboarding_screen.dart';
import '../../features/listings/presentation/landlord_review_queue_screen.dart';
import '../../features/listings/presentation/listing_detail_screen.dart';
import '../../features/listings/presentation/listing_editor_screen.dart';
import 'route_names.dart';

/// Central route factory. Screens push by name so the shell stays the only
/// place that knows how a destination is constructed.
class AppRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.listingDetail:
        final args = settings.arguments;
        if (args is! ListingDetailArgs) {
          return _invalid(settings, 'This listing link is incomplete.');
        }
        return _page<bool>(
          settings,
          ListingDetailScreen(listingId: args.listingId),
        );

      case AppRoutes.listingEditor:
        final args = settings.arguments;
        if (args != null && args is! ListingEditorArgs) {
          return _invalid(settings, 'This listing editor link is incomplete.');
        }
        return _page(
          settings,
          ListingEditorScreen(listing: (args as ListingEditorArgs?)?.listing),
        );

      case AppRoutes.listingReviewQueue:
        final args = settings.arguments;
        if (args is! ListingReviewQueueArgs) {
          return _invalid(settings, 'This review queue link is incomplete.');
        }
        return _page(
          settings,
          LandlordReviewQueueScreen(listing: args.listing),
        );

      case AppRoutes.preferencesEditor:
        return _page<bool>(
          settings,
          const PreferencesOnboardingScreen(editing: true),
        );

      default:
        return null;
    }
  }

  /// Routes that report a result are built with that result type: a typed
  /// `pushNamed<bool>` casts the pushed route to `Route<bool>`, so the page
  /// must be `MaterialPageRoute<bool>` or the cast throws at runtime.
  static MaterialPageRoute<T> _page<T>(
    RouteSettings settings,
    Widget child,
  ) {
    return MaterialPageRoute<T>(
      settings: settings,
      builder: (_) => child,
    );
  }

  static MaterialPageRoute<dynamic> _invalid(
    RouteSettings settings,
    String message,
  ) {
    return _page(settings, _InvalidRouteScreen(message: message));
  }
}

class _InvalidRouteScreen extends StatelessWidget {
  final String message;

  const _InvalidRouteScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link unavailable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Go to Swipeinn'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
