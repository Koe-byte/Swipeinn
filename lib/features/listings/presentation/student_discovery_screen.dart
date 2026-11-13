import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/listing_model.dart';
import 'landlord_studio_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_provider.dart';

// Tracks like intent on listings for the current session.
final studentLikesProvider = StateProvider<Map<String, Set<String>>>((ref) => {
      // listingId -> Set of user uids who liked it
    });

class StudentDiscoveryScreen extends ConsumerStatefulWidget {
  const StudentDiscoveryScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<StudentDiscoveryScreen> createState() =>
      _StudentDiscoveryScreenState();
}

class _StudentDiscoveryScreenState
    extends ConsumerState<StudentDiscoveryScreen> {
  int _currentIndex = 0;
  double _maxRentFilter = 10000.0;
  RoomType? _selectedRoomTypeFilter;

  @override
  void initState() {
    super.initState();
    final preferences = ref.read(authStateProvider).user?.preferences;
    if (preferences == null) return;

    // Seed the first deck with the onboarding budget. Type preferences are
    // stored for Phase 2 ranking but do not hard-filter the deck in v1.
    _maxRentFilter = preferences.budgetMax.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final allListings = ref.watch(listingsProvider);

    // Filter available listings based on active status and filter criteria
    final listings = allListings.where((l) {
      if (l.status != ListingStatus.available) return false;
      if (l.monthlyRent > _maxRentFilter) return false;
      if (_selectedRoomTypeFilter != null &&
          l.roomType != _selectedRoomTypeFilter) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover rentals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: allListings.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.home_work_outlined,
                        size: 64, color: AppTheme.textSecondary),
                    const SizedBox(height: 16),
                    const Text(
                      'No listings yet',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Places posted here show up in Discover. Create the first one from My Listings.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: AppTheme.textSecondary, height: 1.4),
                    ),
                  ],
                ),
              ),
            )
          : listings.isEmpty || _currentIndex >= listings.length
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.done_all,
                          size: 64, color: AppTheme.textSecondary),
                      const SizedBox(height: 16),
                      const Text(
                        "You've reviewed every listing that matches your filters.",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                          'Check back later or widen your budget filter.'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() => _currentIndex = 0),
                        child: const Text('Reset Deck'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _SwipeListingCard(
                          listing: listings[_currentIndex],
                          onPass: () {
                            setState(() => _currentIndex++);
                          },
                          onLike: () {
                            final currentListing = listings[_currentIndex];
                            final user = ref.read(authStateProvider).user;
                            final studentUid = user?.uid;
                            if (studentUid == null) return;
                            // Record like intent in state
                            final likesMap = ref.read(studentLikesProvider);
                            final set = likesMap[currentListing.id] ?? {};
                            set.add(studentUid);
                            likesMap[currentListing.id] = set;
                            ref.read(studentLikesProvider.notifier).state =
                                Map.from(likesMap);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Liked "${currentListing.title}"! Sent to the owner.'),
                                duration: const Duration(seconds: 1),
                                backgroundColor: AppTheme.navyDark,
                              ),
                            );
                            setState(() => _currentIndex++);
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Pass Button
                          FloatingActionButton(
                            heroTag: 'pass_btn',
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.passRed,
                            elevation: 4,
                            onPressed: () {
                              setState(() => _currentIndex++);
                            },
                            child: const Icon(Icons.close, size: 32),
                          ),
                          // Info Button
                          FloatingActionButton.small(
                            heroTag: 'info_btn',
                            backgroundColor: Colors.grey.shade100,
                            foregroundColor: AppTheme.navyDark,
                            elevation: 2,
                            onPressed: () {
                              _showListingDetailsModal(
                                  context, listings[_currentIndex]);
                            },
                            child: const Icon(Icons.info_outline),
                          ),
                          // Like Button
                          FloatingActionButton(
                            heroTag: 'like_btn',
                            backgroundColor: AppTheme.primaryAmber,
                            foregroundColor: AppTheme.navyDark,
                            elevation: 4,
                            onPressed: () {
                              final currentListing = listings[_currentIndex];
                              final user = ref.read(authStateProvider).user;
                              final studentUid = user?.uid;
                              if (studentUid == null) return;
                              final likesMap = ref.read(studentLikesProvider);
                              final set = likesMap[currentListing.id] ?? {};
                              set.add(studentUid);
                              likesMap[currentListing.id] = set;
                              ref.read(studentLikesProvider.notifier).state =
                                  Map.from(likesMap);

                              setState(() => _currentIndex++);
                            },
                            child: const Icon(Icons.favorite, size: 32),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Discovery Filters',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  Text('Max Monthly Budget: ₱${_maxRentFilter.round()}'),
                  Slider(
                    value: _maxRentFilter,
                    min: 2000,
                    max: 15000,
                    divisions: 13,
                    activeColor: AppTheme.primaryAmber,
                    onChanged: (val) {
                      setSheetState(() => _maxRentFilter = val);
                      setState(() => _maxRentFilter = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Room Type:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _selectedRoomTypeFilter == null,
                        onSelected: (selected) {
                          setSheetState(() => _selectedRoomTypeFilter = null);
                          setState(() => _selectedRoomTypeFilter = null);
                        },
                      ),
                      ...RoomType.values.map(
                        (type) => ChoiceChip(
                          label: Text(type.name.toUpperCase()),
                          selected: _selectedRoomTypeFilter == type,
                          onSelected: (selected) {
                            setSheetState(
                              () => _selectedRoomTypeFilter =
                                  selected ? type : null,
                            );
                            setState(
                              () => _selectedRoomTypeFilter =
                                  selected ? type : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Center(child: Text('Apply Filters')),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showListingDetailsModal(BuildContext context, ListingModel listing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₱${listing.monthlyRent.toStringAsFixed(0)} / month',
                    style: const TextStyle(
                      color: AppTheme.primaryDarkAmber,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(height: 32),
                  const Text('Description',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(listing.description),
                  const SizedBox(height: 16),
                  const Text('Included Amenities',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: listing.amenities
                        .map((a) => Chip(
                              label: Text(a),
                              backgroundColor: Colors.amber.shade50,
                            ))
                        .toList(),
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

class _SwipeListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback onPass;
  final VoidCallback onLike;

  const _SwipeListingCard({
    required this.listing,
    required this.onPass,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(listing.id),
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onPass();
        } else {
          onLike();
        }
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (listing.photos.isNotEmpty)
              Image.network(
                listing.photos.first,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: Colors.white70, size: 36),
                ),
              )
            else
              Container(color: Colors.grey.shade300),
            // Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.1),
                    Colors.transparent,
                    Colors.black.withOpacity(0.85),
                  ],
                ),
              ),
            ),
            // Info Content
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${listing.monthlyRent.toStringAsFixed(0)} / mo • ${listing.roomType.name.toUpperCase()}',
                    style: const TextStyle(
                      color: AppTheme.primaryAmber,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: listing.amenities
                        .take(3)
                        .map((a) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                a,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
