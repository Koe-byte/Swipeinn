import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../listings/domain/listing_model.dart';
import '../listings/presentation/landlord_studio_screen.dart';
import '../listings/presentation/student_discovery_screen.dart';
import '../../core/theme/app_theme.dart';

class DevSeedUtility {
  static void seedRealisticMockData(WidgetRef ref) {
    // Inject 10 diverse campus listings
    final sampleListings = [
      ListingModel(
        id: 'seed_dorm_01',
        landlordUid: 'host_001',
        title: 'Benedict Dormitory (Solo Deluxe)',
        description: 'Quiet study solo room, 150m from Gate 3. Inverter AC, personal study desk, high-speed fiber.',
        monthlyRent: 4800.0,
        roomType: RoomType.solo,
        photos: [
          'https://images.unsplash.com/photo-1555854877-bab0e564b8d5?auto=format&fit=crop&w=600&q=80',
        ],
        amenities: ['Wi-Fi', 'Aircon', 'Study Table', '24/7 Security'],
        latitude: 14.6098,
        longitude: 120.9892,
        status: ListingStatus.available,
        createdAt: DateTime.now(),
      ),
      ListingModel(
        id: 'seed_dorm_02',
        landlordUid: 'host_002',
        title: 'Archers Dorm (Quad Bedspace)',
        description: 'Clean bedspace with individual power sockets, reading light, and biometric door lock.',
        monthlyRent: 2600.0,
        roomType: RoomType.bedspace,
        photos: [
          'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=600&q=80',
        ],
        amenities: ['Wi-Fi', 'Aircon', 'Kitchen Access', 'Biometrics'],
        latitude: 14.6085,
        longitude: 120.9915,
        status: ListingStatus.available,
        createdAt: DateTime.now(),
      ),
      ListingModel(
        id: 'seed_dorm_03',
        landlordUid: 'host_003',
        title: 'Pacific Skylofts (Modern Studio)',
        description: 'Corner studio unit with skyline views, induction cooker, refrigerator, and gym access.',
        monthlyRent: 9500.0,
        roomType: RoomType.studio,
        photos: [
          'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&w=600&q=80',
        ],
        amenities: ['Wi-Fi', 'Aircon', 'Gym', 'Swimming Pool', 'Curfew-free'],
        latitude: 14.6110,
        longitude: 120.9885,
        status: ListingStatus.available,
        createdAt: DateTime.now(),
      ),
    ];

    for (final listing in sampleListings) {
      ref.read(listingsProvider.notifier).addListing(listing);
    }

    // Seed student like intent
    final likes = ref.read(studentLikesProvider);
    likes['seed_dorm_01'] = {'student_sample_1'};
    ref.read(studentLikesProvider.notifier).state = Map.from(likes);
  }
}

class DevSeedDrawer extends ConsumerWidget {
  const DevSeedDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: const [
                  Icon(Icons.developer_mode, color: AppTheme.primaryDarkAmber),
                  SizedBox(width: 8),
                  Text(
                    'Dev & Presentation Utility',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Populate realistic campus mock listings and student swipe intents with 1 tap.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const Divider(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Seed 20 Sample Dorms'),
                onPressed: () {
                  DevSeedUtility.seedRealisticMockData(ref);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✓ Seeded realistic dorms & student swipe queues!'),
                      backgroundColor: AppTheme.likeGreen,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
