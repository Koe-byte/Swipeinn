import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/listing_model.dart';
import 'listings_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_provider.dart';

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
  PropertyType? _selectedPropertyTypeFilter;

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
    final listingsAsync = ref.watch(discoverListingsProvider);
    final currentUid = ref.watch(authStateProvider).user?.uid;
    final allListings = listingsAsync.valueOrNull ?? const <ListingModel>[];

    // Filter available listings based on active status and filter criteria
    final listings = allListings.where((l) {
      if (l.status != ListingStatus.available) return false;
      if (l.monthlyRent > _maxRentFilter) return false;
      if (_selectedPropertyTypeFilter != null &&
          l.propertyType != _selectedPropertyTypeFilter) {
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
      body: listingsAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : allListings.isEmpty
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
                          'No places to discover yet',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Places published here show up in Discover. Add your own from My Listings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.textSecondary, height: 1.4),
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
                              isMine: listings[_currentIndex].ownerUid ==
                                  currentUid,
                              onPass: () {
                                setState(() => _currentIndex++);
                              },
                              onLike: listings[_currentIndex].ownerUid ==
                                      currentUid
                                  ? _handleOwnListing
                                  : () => _likeListing(listings[_currentIndex]),
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
                                onPressed: listings[_currentIndex].ownerUid ==
                                        currentUid
                                    ? _handleOwnListing
                                    : () =>
                                        _likeListing(listings[_currentIndex]),
                                child: const Icon(Icons.favorite, size: 32),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  void _handleOwnListing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'That is your listing. Interest shows up in My Listings → Review Queue.',
        ),
      ),
    );
  }

  Future<void> _likeListing(ListingModel listing) async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    try {
      await ref.read(listingsRepositoryProvider).like(
            listingId: listing.id,
            requesterUid: user.uid,
            requesterName: user.displayName,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Liked "${listing.title}"! Sent to the owner.'),
          duration: const Duration(seconds: 1),
          backgroundColor: AppTheme.navyDark,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send that like: $error')),
      );
    }
    if (mounted) setState(() => _currentIndex++);
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
                    max: 50000,
                    divisions: 48,
                    activeColor: AppTheme.primaryAmber,
                    onChanged: (val) {
                      setSheetState(() => _maxRentFilter = val);
                      setState(() => _maxRentFilter = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Property Type:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _selectedPropertyTypeFilter == null,
                        onSelected: (selected) {
                          setSheetState(
                              () => _selectedPropertyTypeFilter = null);
                          setState(() => _selectedPropertyTypeFilter = null);
                        },
                      ),
                      ...PropertyType.values.map(
                        (type) => ChoiceChip(
                          label: Text(type.label),
                          selected: _selectedPropertyTypeFilter == type,
                          onSelected: (selected) {
                            setSheetState(
                              () => _selectedPropertyTypeFilter =
                                  selected ? type : null,
                            );
                            setState(
                              () => _selectedPropertyTypeFilter =
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
  final bool isMine;
  final VoidCallback onPass;
  final VoidCallback onLike;

  const _SwipeListingCard({
    required this.listing,
    required this.isMine,
    required this.onPass,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
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
          if (isMine)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.navyDark.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'YOUR LISTING',
                  style: TextStyle(
                    color: AppTheme.primaryAmber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
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
                  '₱${listing.monthlyRent.toStringAsFixed(0)} / mo • ${listing.propertyType.label.toUpperCase()}',
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
    );

    // Swiping your own card would trigger the like callback and be immediately
    // undone by the owner check, which looks like a broken gesture. Preview it
    // without the swipe layer instead.
    if (isMine) return card;

    return Dismissible(
      key: Key(listing.id),
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onPass();
        } else {
          onLike();
        }
      },
      child: card,
    );
  }
}
