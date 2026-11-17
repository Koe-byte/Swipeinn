import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/route_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../domain/listing_model.dart';
import 'listings_provider.dart';

/// The signed-in account's published places. Any account can own listings.
class LandlordStudioScreen extends ConsumerWidget {
  const LandlordStudioScreen({Key? key}) : super(key: key);

  void _openEditor(BuildContext context) {
    Navigator.of(context).pushNamed(
      AppRoutes.listingEditor,
      arguments: const ListingEditorArgs(),
    );
  }

  void _openListing(BuildContext context, ListingModel listing) {
    Navigator.of(context).pushNamed(
      AppRoutes.listingDetail,
      arguments: ListingDetailArgs(listingId: listing.id),
    );
  }

  void _openReviewQueue(BuildContext context, ListingModel listing) {
    Navigator.of(context).pushNamed(
      AppRoutes.listingReviewQueue,
      arguments: ListingReviewQueueArgs(listing: listing),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(myListingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle,
                color: AppTheme.primaryAmber, size: 28),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: listingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Could not load your listings. Pull to retry from Discover.\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
        data: (listings) => listings.isEmpty
            ? EmptyStateView(
                icon: Icons.apartment_outlined,
                title: 'No listings published yet.',
                message: 'Publish a place and it appears in Discover for every '
                    'other account.',
                action: FilledButton.icon(
                  onPressed: () => _openEditor(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Publish a place'),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: listings.length,
                itemBuilder: (context, index) {
                  final listing = listings[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _openListing(context, listing),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 140,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              image: listing.photos.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(listing.photos.first),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      listing.status == ListingStatus.available
                                          ? AppTheme.likeGreen
                                          : Colors.orange,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  listing.status.name.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  listing.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₱${listing.monthlyRent.toStringAsFixed(0)} / month • '
                                  '${listing.propertyType.label.toUpperCase()} • '
                                  'FITS ${listing.capacity}',
                                  style: const TextStyle(
                                    color: AppTheme.primaryDarkAmber,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.navyDark,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.people_alt,
                                            size: 18),
                                        label: const Text('Review Queue'),
                                        onPressed: () =>
                                            _openReviewQueue(context, listing),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PopupMenuButton<ListingStatus>(
                                      icon: const Icon(Icons.more_vert),
                                      onSelected: (status) async {
                                        await ref
                                            .read(listingsRepositoryProvider)
                                            .updateStatus(listing.id, status);
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Status set to ${status.name}.',
                                            ),
                                          ),
                                        );
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: ListingStatus.available,
                                          child: Text('Mark Available'),
                                        ),
                                        const PopupMenuItem(
                                          value: ListingStatus.reserved,
                                          child: Text('Mark Reserved'),
                                        ),
                                        const PopupMenuItem(
                                          value: ListingStatus.full,
                                          child: Text('Mark Full / Hide'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
