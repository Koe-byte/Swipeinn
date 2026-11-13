import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/listing_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_provider.dart';
import 'landlord_review_queue_screen.dart';

// State of all active listings
final listingsProvider =
    StateNotifierProvider<ListingsNotifier, List<ListingModel>>((ref) {
  return ListingsNotifier();
});

class ListingsNotifier extends StateNotifier<List<ListingModel>> {
  ListingsNotifier() : super([]);

  void addListing(ListingModel listing) {
    state = [listing, ...state];
  }

  void toggleStatus(String listingId, ListingStatus newStatus) {
    state = state.map((item) {
      if (item.id == listingId) {
        return item.copyWith(status: newStatus);
      }
      return item;
    }).toList();
  }
}

class LandlordStudioScreen extends ConsumerWidget {
  const LandlordStudioScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(listingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle,
                color: AppTheme.primaryAmber, size: 28),
            onPressed: () => _showAddListingSheet(context, ref),
          ),
        ],
      ),
      body: listings.isEmpty
          ? const Center(child: Text('No listings published yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: listings.length,
              itemBuilder: (context, index) {
                final listing = listings[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  clipBehavior: Clip.antiAlias,
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
                              color: listing.status == ListingStatus.available
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
                                  fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₱${listing.monthlyRent.toStringAsFixed(0)} / month • ${listing.roomType.name.toUpperCase()}',
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
                                    icon:
                                        const Icon(Icons.people_alt, size: 18),
                                    label: const Text('Review Queue'),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              LandlordReviewQueueScreen(
                                                  listing: listing),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<ListingStatus>(
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (status) {
                                    ref
                                        .read(listingsProvider.notifier)
                                        .toggleStatus(listing.id, status);
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
                );
              },
            ),
    );
  }

  void _showAddListingSheet(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final rentController = TextEditingController();
    RoomType selectedRoomType = RoomType.solo;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return ConstrainedBox(
              // Keeps the sheet on screen with the keyboard open; the form
              // scrolls instead of pushing the Publish button past the edge.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 24,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Publish New Listing Card',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Listing Title',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        hintText: 'What makes this place worth a look?',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rentController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Monthly Rent (₱)',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Property type',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: RoomType.values.map((type) {
                        return ChoiceChip(
                          label: Text(type.name[0].toUpperCase() +
                              type.name.substring(1)),
                          selected: selectedRoomType == type,
                          onSelected: (_) =>
                              setSheetState(() => selectedRoomType = type),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        final title = titleController.text.trim();
                        if (title.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text('Give the listing a title.')),
                          );
                          return;
                        }
                        final rent =
                            double.tryParse(rentController.text.trim()) ??
                                4000.0;
                        final description = descriptionController.text.trim();
                        final newListing = ListingModel(
                          id: 'listing_${DateTime.now().millisecondsSinceEpoch}',
                          landlordUid: ref.read(authStateProvider).user?.uid ??
                              'unknown',
                          title: title,
                          description: description.isEmpty
                              ? 'Newly posted listing.'
                              : description,
                          monthlyRent: rent,
                          roomType: selectedRoomType,
                          // No photo upload yet (Firebase Storage is unavailable),
                          // so the card shows its placeholder instead of a stock
                          // photo of a different unit.
                          photos: const [],
                          amenities: const [],
                          latitude: 14.6090,
                          longitude: 120.9890,
                          status: ListingStatus.available,
                          createdAt: DateTime.now(),
                        );
                        ref
                            .read(listingsProvider.notifier)
                            .addListing(newListing);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('"$title" is now in Discover.')),
                        );
                      },
                      child: const Text('Publish Listing Card'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
