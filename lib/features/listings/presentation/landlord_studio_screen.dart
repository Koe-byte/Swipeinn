import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/listing_model.dart';
import '../../../core/theme/app_theme.dart';
import 'landlord_review_queue_screen.dart';

// State of all active listings
final listingsProvider = StateNotifierProvider<ListingsNotifier, List<ListingModel>>((ref) {
  return ListingsNotifier();
});

class ListingsNotifier extends StateNotifier<List<ListingModel>> {
  ListingsNotifier() : super([]) {
    _initSampleData();
  }

  void _initSampleData() {
    state = [
      ListingModel(
        id: 'listing_01',
        landlordUid: 'landlord_101',
        title: 'Sunshine Dormitory (Unit 204)',
        description: 'Quiet study-friendly solo room, 3 mins walk to Gate 2. High-speed Wi-Fi included.',
        monthlyRent: 4500.0,
        roomType: RoomType.solo,
        photos: [
          'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=600&q=80',
          'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=600&q=80',
        ],
        amenities: ['Wi-Fi', 'Aircon', 'Curfew-free', 'Study Table'],
        latitude: 14.6095,
        longitude: 120.9897,
        status: ListingStatus.available,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      ListingModel(
        id: 'listing_02',
        landlordUid: 'landlord_101',
        title: 'University Suites - Bedspace A',
        description: 'Spacious bedspace in a 4-person air-conditioned room with personal lockers.',
        monthlyRent: 2800.0,
        roomType: RoomType.bedspace,
        photos: [
          'https://images.unsplash.com/photo-1555854877-bab0e564b8d5?auto=format&fit=crop&w=600&q=80',
        ],
        amenities: ['Wi-Fi', 'Aircon', 'CCTV Security', 'Kitchen Access'],
        latitude: 14.6080,
        longitude: 120.9910,
        status: ListingStatus.available,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ListingModel(
        id: 'listing_03',
        landlordUid: 'landlord_102',
        title: 'Espana Grand Residences (Studio)',
        description: 'Premium modern studio unit with balcony, gym, and swimming pool access.',
        monthlyRent: 8500.0,
        roomType: RoomType.studio,
        photos: [
          'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&w=600&q=80',
        ],
        amenities: ['Wi-Fi', 'Aircon', 'Swimming Pool', 'Gym', 'No Curfew'],
        latitude: 14.6105,
        longitude: 120.9880,
        status: ListingStatus.available,
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      ),
    ];
  }

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
        title: const Text('Landlord Studio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppTheme.primaryAmber, size: 28),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                                    icon: const Icon(Icons.people_alt, size: 18),
                                    label: const Text('Review Queue'),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => LandlordReviewQueueScreen(listing: listing),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<ListingStatus>(
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (status) {
                                    ref.read(listingsProvider.notifier).toggleStatus(listing.id, status);
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
    final rentController = TextEditingController();
    RoomType selectedRoomType = RoomType.solo;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Listing Title',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rentController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Monthly Rent (₱)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      if (titleController.text.isNotEmpty) {
                        final rent = double.tryParse(rentController.text) ?? 4000.0;
                        final newListing = ListingModel(
                          id: 'listing_${DateTime.now().millisecondsSinceEpoch}',
                          landlordUid: 'current_landlord',
                          title: titleController.text,
                          description: 'Newly posted campus listing.',
                          monthlyRent: rent,
                          roomType: selectedRoomType,
                          photos: [
                            'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=600&q=80',
                          ],
                          amenities: ['Wi-Fi', 'Aircon'],
                          latitude: 14.6090,
                          longitude: 120.9890,
                          status: ListingStatus.available,
                          createdAt: DateTime.now(),
                        );
                        ref.read(listingsProvider.notifier).addListing(newListing);
                        Navigator.pop(ctx);
                      }
                    },
                    child: const Text('Publish Listing Card'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
