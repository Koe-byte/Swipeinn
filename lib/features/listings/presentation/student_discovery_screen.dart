import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/listing_model.dart';
import 'listings_provider.dart';
import '../../../core/navigation/route_names.dart';
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
  static const double _maxBudgetFilter = 50000.0;

  double _maxRentFilter = _maxBudgetFilter;
  PropertyType? _selectedPropertyTypeFilter;
  int _minCapacityFilter = 1;

  /// Passed cards are hidden by default but can be reviewed again.
  bool _showPassed = false;

  /// Cards liked or passed this session. The streams can take a beat to catch
  /// up, and the deck must advance immediately. They are tracked separately so
  /// "Show places I passed" can bring a pass back without resurrecting a card
  /// the renter already liked.
  final Set<String> _likedThisSession = {};
  final Set<String> _passedThisSession = {};

  /// Passes undone this session; overrides the persisted pass until the delete
  /// reaches the stream.
  final Set<String> _unpassedThisSession = {};

  @override
  void initState() {
    super.initState();
    final preferences = ref.read(authStateProvider).user?.preferences;
    if (preferences == null) return;

    // Seed the first deck with the onboarding budget, but never let it exceed
    // the filter's range. The banner below makes a hidden listing obvious.
    _maxRentFilter =
        preferences.budgetMax.toDouble().clamp(2000.0, _maxBudgetFilter);
  }

  bool _matchesFilters(ListingModel listing) {
    if (listing.monthlyRent > _maxRentFilter) return false;
    if (listing.capacity < _minCapacityFilter) return false;
    if (_selectedPropertyTypeFilter != null &&
        listing.propertyType != _selectedPropertyTypeFilter) {
      return false;
    }
    return true;
  }

  /// A card leaves the deck when it has already been liked or passed. Likes
  /// include a pending request, an approved match and a rejection, so the owner
  /// deciding never resurrects a card the renter already acted on.
  bool _isHidden(
    String listingId,
    Set<String> likedIds,
    Set<String> passedIds,
  ) {
    if (_likedThisSession.contains(listingId)) return true;
    if (likedIds.contains(listingId)) return true;
    if (_showPassed) return false;
    if (_unpassedThisSession.contains(listingId)) return false;
    if (_passedThisSession.contains(listingId)) return true;
    return passedIds.contains(listingId);
  }

  /// Forces a fresh cloud read. This is the escape hatch when a Realtime
  /// channel has gone stale after switching accounts.
  void _refresh() {
    setState(() {
      _likedThisSession.clear();
      _passedThisSession.clear();
      _unpassedThisSession.clear();
    });
    ref.invalidate(discoverListingsProvider);
    ref.invalidate(likedListingIdsProvider);
    ref.invalidate(passedListingIdsProvider);
  }

  /// Removes every Discover-only filter so listings that were hidden by the
  /// onboarding budget are visible.
  void _showAllListings() {
    setState(() {
      _maxRentFilter = _maxBudgetFilter;
      _selectedPropertyTypeFilter = null;
      _minCapacityFilter = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final listingsAsync = ref.watch(discoverListingsProvider);
    final likedIds =
        ref.watch(likedListingIdsProvider).valueOrNull ?? const <String>{};
    final passedIds =
        ref.watch(passedListingIdsProvider).valueOrNull ?? const <String>{};
    final currentUid = ref.watch(authStateProvider).user?.uid;
    final allListings = listingsAsync.valueOrNull ?? const <ListingModel>[];

    // Discover is a deck of other people's places. A listing you published
    // already has a home in My Listings with edit/delete/review actions.
    final otherListings =
        allListings.where((listing) => listing.ownerUid != currentUid).toList();
    final availableListings = otherListings
        .where((listing) =>
            listing.status == ListingStatus.available &&
            !_isHidden(listing.id, likedIds, passedIds))
        .toList();
    final listings = availableListings.where(_matchesFilters).toList();
    final hiddenCount = availableListings.length - listings.length;
    final canShowPassed = passedIds.isNotEmpty && !_showPassed;

    final Widget body;
    if (listingsAsync.isLoading && !listingsAsync.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (listingsAsync.hasError && !listingsAsync.hasValue) {
      body = _DiscoverErrorState(onRetry: _refresh);
    } else if (allListings.isEmpty) {
      body = const _DiscoverEmptyState();
    } else if (otherListings.isEmpty && currentUid != null) {
      body = const _OnlyMyListingsState();
    } else {
      body = Column(
        children: [
          if (hiddenCount > 0 && listings.isNotEmpty)
            _HiddenListingsBanner(
              count: hiddenCount,
              budget: _maxRentFilter,
              onShowAll: _showAllListings,
            ),
          Expanded(
            child: _buildDeck(
              listings: listings,
              availableListings: availableListings,
              hiddenCount: hiddenCount,
              canShowPassed: canShowPassed,
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover rentals'),
        actions: [
          IconButton(
            key: const Key('discover_refresh'),
            tooltip: 'Refresh listings',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildDeck({
    required List<ListingModel> listings,
    required List<ListingModel> availableListings,
    required int hiddenCount,
    required bool canShowPassed,
  }) {
    if (listings.isEmpty) {
      // Cards exist but the filters hide them; offer a way back.
      if (availableListings.isNotEmpty) {
        return _NoMatchingListingsState(
          hiddenCount: hiddenCount,
          onShowAll: _showAllListings,
        );
      }

      // Everything available was liked or passed.
      return _ReviewedEveryListingState(
        canShowPassed: canShowPassed,
        onShowPassed: () => setState(() => _showPassed = true),
        onRefresh: _refresh,
      );
    }

    final listing = listings.first;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _SwipeListingCard(
              listing: listing,
              onTap: () => _openListing(listing),
              onPass: () => _passListing(listing),
              onLike: () => _likeListing(listing),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Pass Button
              FloatingActionButton(
                key: const Key('discover_pass'),
                heroTag: 'pass_btn',
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.passRed,
                elevation: 4,
                tooltip: 'Not for me',
                onPressed: () => _passListing(listing),
                child: const Icon(Icons.close, size: 32),
              ),
              // Info Button
              FloatingActionButton.small(
                heroTag: 'info_btn',
                backgroundColor: Colors.grey.shade100,
                foregroundColor: AppTheme.navyDark,
                elevation: 2,
                onPressed: () => _openListing(listing),
                child: const Icon(Icons.info_outline),
              ),
              // Like Button
              FloatingActionButton(
                key: const Key('discover_like'),
                heroTag: 'like_btn',
                backgroundColor: AppTheme.primaryAmber,
                foregroundColor: AppTheme.navyDark,
                elevation: 4,
                tooltip: 'Interested',
                onPressed: () => _likeListing(listing),
                child: const Icon(Icons.favorite, size: 32),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openListing(ListingModel listing) async {
    final liked = await Navigator.of(context).pushNamed<bool>(
      AppRoutes.listingDetail,
      arguments: ListingDetailArgs(listingId: listing.id),
    );
    // The detail screen pops with `true` when the person expresses interest,
    // which is the same outcome as a right swipe.
    if (!mounted || liked != true) return;
    setState(() => _likedThisSession.add(listing.id));
  }

  Future<void> _likeListing(ListingModel listing) async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() => _likedThisSession.add(listing.id));

    try {
      final synced = await ref.read(listingsRepositoryProvider).like(
            listingId: listing.id,
            requesterUid: user.uid,
            requesterName: user.displayName,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Liked "${listing.title}"! Sent to the owner.'
                : 'Liked "${listing.title}" on this device. It will sync once '
                    'the connection is back.',
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: AppTheme.navyDark,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // The like never landed, so put the card back rather than losing it.
      setState(() => _likedThisSession.remove(listing.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send that like: $error')),
      );
    }
  }

  Future<void> _passListing(ListingModel listing) async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _passedThisSession.add(listing.id);
      _unpassedThisSession.remove(listing.id);
    });

    try {
      final synced = await ref.read(listingsRepositoryProvider).pass(
            listingId: listing.id,
            requesterUid: user.uid,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Passed on "${listing.title}".'
                : 'Passed on "${listing.title}" here. It will sync once the '
                    'connection is back.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoPass(listing),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _passedThisSession.remove(listing.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save that pass: $error')),
      );
    }
  }

  Future<void> _undoPass(ListingModel listing) async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    setState(() {
      _passedThisSession.remove(listing.id);
      _unpassedThisSession.add(listing.id);
    });

    try {
      final synced = await ref.read(listingsRepositoryProvider).undoPass(
            listingId: listing.id,
            requesterUid: user.uid,
          );
      if (!synced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The card is back here. The undo will sync once the connection '
              'is back.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _passedThisSession.add(listing.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not undo that pass: $error')),
      );
    }
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
            return SingleChildScrollView(
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
                    max: _maxBudgetFilter,
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
                            setState(() => _selectedPropertyTypeFilter =
                                selected ? type : null);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Fits at least:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [1, 2, 3, 4, 5].map((people) {
                      return ChoiceChip(
                        label: Text(people == 5 ? '5+' : '$people'),
                        selected: _minCapacityFilter == people,
                        onSelected: (_) {
                          setSheetState(() => _minCapacityFilter = people);
                          setState(() => _minCapacityFilter = people);
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show places I passed'),
                    subtitle: Text(
                      '${ref.read(passedListingIdsProvider).valueOrNull?.length ?? 0} '
                      'passed. Owners never see this.',
                    ),
                    value: _showPassed,
                    onChanged: (value) {
                      setSheetState(() => _showPassed = value);
                      setState(() => _showPassed = value);
                    },
                  ),
                  const SizedBox(height: 12),
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
}

class _DiscoverEmptyState extends StatelessWidget {
  const _DiscoverEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Places published here show up in Discover. Add your own from My Listings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlyMyListingsState extends StatelessWidget {
  const _OnlyMyListingsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.home_work_outlined,
                size: 64, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text(
              'No other places yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Your own listings live in My Listings. Discover shows places '
              'published by other accounts.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _DiscoverErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off,
                size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Could not load listings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('discover_retry'),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HiddenListingsBanner extends StatelessWidget {
  final int count;
  final double budget;
  final VoidCallback onShowAll;

  const _HiddenListingsBanner({
    required this.count,
    required this.budget,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('discover_hidden_banner'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryAmber.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryAmber.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined,
              size: 20, color: AppTheme.navyDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'listing is' : 'listings are'} hidden by '
              'your ₱${budget.round()} budget, property type or group size.',
              style: const TextStyle(fontSize: 12.5, height: 1.3),
            ),
          ),
          TextButton(
            key: const Key('discover_show_all'),
            onPressed: onShowAll,
            child: const Text('Show all'),
          ),
        ],
      ),
    );
  }
}

class _NoMatchingListingsState extends StatelessWidget {
  final int hiddenCount;
  final VoidCallback onShowAll;

  const _NoMatchingListingsState({
    required this.hiddenCount,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.tune, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'No listings match your filters',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              hiddenCount > 0
                  ? '$hiddenCount ${hiddenCount == 1 ? 'place is' : 'places are'} '
                      'available if you widen your budget, clear the property '
                      'type or lower the group size.'
                  : 'There are no available places right now. Check back later.',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
            if (hiddenCount > 0) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                key: const Key('discover_show_all_empty'),
                onPressed: onShowAll,
                child: const Text('Show all listings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewedEveryListingState extends StatelessWidget {
  final bool canShowPassed;
  final VoidCallback onShowPassed;
  final VoidCallback onRefresh;

  const _ReviewedEveryListingState({
    required this.canShowPassed,
    required this.onShowPassed,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.done_all, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            const Text(
              "You've reviewed every listing that matches your filters.",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              canShowPassed
                  ? 'You passed on some places. You can give them another look.'
                  : 'Check back later or widen your filters.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            if (canShowPassed)
              ElevatedButton(
                key: const Key('discover_show_passed'),
                onPressed: onShowPassed,
                child: const Text('Show places I passed'),
              )
            else
              ElevatedButton(
                key: const Key('discover_refresh_empty'),
                onPressed: onRefresh,
                child: const Text('Refresh'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SwipeListingCard extends StatelessWidget {
  final ListingModel listing;
  final VoidCallback onTap;
  final VoidCallback onPass;
  final VoidCallback onLike;

  const _SwipeListingCard({
    required this.listing,
    required this.onTap,
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
                  '₱${listing.monthlyRent.toStringAsFixed(0)} / mo • '
                  '${listing.propertyType.label.toUpperCase()} • '
                  'FITS ${listing.capacity}',
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

    // A tap opens the full listing. A horizontal swipe is the same pass/like
    // gesture as the buttons below the card.
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );

    return Dismissible(
      key: Key(listing.id),
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onPass();
        } else {
          onLike();
        }
      },
      child: tappable,
    );
  }
}
