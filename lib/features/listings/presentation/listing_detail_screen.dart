import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/route_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../auth/presentation/auth_provider.dart';
import '../domain/listing_model.dart';
import 'listings_provider.dart';

/// Full listing view. Owners get edit/delete/review actions; everyone else can
/// express interest, which is the same pending like the swipe deck creates.
class ListingDetailScreen extends ConsumerStatefulWidget {
  final String listingId;

  const ListingDetailScreen({Key? key, required this.listingId})
      : super(key: key);

  @override
  ConsumerState<ListingDetailScreen> createState() =>
      _ListingDetailScreenState();
}

class _ListingDetailScreenState extends ConsumerState<ListingDetailScreen> {
  bool _sendingInterest = false;

  Future<void> _sendInterest(ListingModel listing) async {
    final user = ref.read(authStateProvider).user;
    if (user == null || _sendingInterest) return;

    setState(() => _sendingInterest = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await ref.read(listingsRepositoryProvider).like(
            listingId: listing.id,
            requesterUid: user.uid,
            requesterName: user.displayName,
          );
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Liked "${listing.title}"! Sent to the owner.'),
          duration: const Duration(seconds: 1),
          backgroundColor: AppTheme.navyDark,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sendingInterest = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send that like: $error')),
      );
    }
  }

  Future<void> _deleteListing(ListingModel listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete listing?'),
        content: Text(
          '"${listing.title}" will be removed from Discover. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const Key('listing_delete_confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.passRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final deleted =
        await ref.read(listingsRepositoryProvider).deleteListing(listing.id);
    if (!mounted) return;

    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? '"${listing.title}" was deleted.'
              : '"${listing.title}" was removed here. Other devices may still '
                  'show it until they reconnect.',
        ),
      ),
    );
  }

  void _openEditor(ListingModel listing) {
    Navigator.of(context).pushNamed(
      AppRoutes.listingEditor,
      arguments: ListingEditorArgs(listing: listing),
    );
  }

  void _openReviewQueue(ListingModel listing) {
    Navigator.of(context).pushNamed(
      AppRoutes.listingReviewQueue,
      arguments: ListingReviewQueueArgs(listing: listing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listingAsync = ref.watch(listingProvider(widget.listingId));
    final currentUid = ref.watch(authStateProvider).user?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Listing details')),
      body: listingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyStateView(
          icon: Icons.cloud_off,
          title: 'Could not load this listing',
          message: '$error',
          action: FilledButton(
            onPressed: () => ref.invalidate(listingProvider(widget.listingId)),
            child: const Text('Try again'),
          ),
        ),
        data: (listing) {
          if (listing == null) {
            return EmptyStateView(
              icon: Icons.home_work_outlined,
              title: 'Listing unavailable',
              message: 'It may have been removed by its owner or is no longer '
                  'shared.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            );
          }

          final isOwner = listing.isOwnedBy(currentUid);
          return _ListingBody(
            listing: listing,
            isOwner: isOwner,
            isSendingInterest: _sendingInterest,
            onSendInterest: () => _sendInterest(listing),
            onEdit: () => _openEditor(listing),
            onReviewQueue: () => _openReviewQueue(listing),
            onDelete: () => _deleteListing(listing),
          );
        },
      ),
    );
  }
}

class _ListingBody extends StatelessWidget {
  final ListingModel listing;
  final bool isOwner;
  final bool isSendingInterest;
  final VoidCallback onSendInterest;
  final VoidCallback onEdit;
  final VoidCallback onReviewQueue;
  final VoidCallback onDelete;

  const _ListingBody({
    required this.listing,
    required this.isOwner,
    required this.isSendingInterest,
    required this.onSendInterest,
    required this.onEdit,
    required this.onReviewQueue,
    required this.onDelete,
  });

  Color get _statusColor {
    switch (listing.status) {
      case ListingStatus.available:
        return AppTheme.likeGreen;
      case ListingStatus.reserved:
        return Colors.orange;
      case ListingStatus.full:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: 220,
                width: double.infinity,
                child: listing.photos.isNotEmpty
                    ? Image.network(
                        listing.photos.first,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const _PhotoPlaceholder(),
                      )
                    : const _PhotoPlaceholder(),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.navyDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            listing.status.name.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₱${listing.monthlyRent.toStringAsFixed(0)} / month • '
                      '${listing.propertyType.label}',
                      style: const TextStyle(
                        color: AppTheme.primaryDarkAmber,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Divider(height: 32),
                    const _SectionTitle('About this place'),
                    const SizedBox(height: 8),
                    Text(
                      listing.description.trim().isEmpty
                          ? 'No description provided.'
                          : listing.description,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle('Amenities'),
                    const SizedBox(height: 8),
                    if (listing.amenities.isEmpty)
                      const Text(
                        'No amenities listed.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: listing.amenities
                            .map(
                              (amenity) => Chip(
                                label: Text(amenity),
                                backgroundColor: Colors.amber.shade50,
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 24),
                    const _SectionTitle('Location'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            color: AppTheme.navyDark, size: 20),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Pinned near '
                            '${listing.latitude.toStringAsFixed(4)}, '
                            '${listing.longitude.toStringAsFixed(4)}',
                            style:
                                const TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    if (isOwner) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAmber.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'This is your listing. Interest from other accounts '
                          'shows up in the Review Queue.',
                          style: TextStyle(
                            color: AppTheme.navyDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        _ActionBar(
          isOwner: isOwner,
          isSendingInterest: isSendingInterest,
          onSendInterest: onSendInterest,
          onEdit: onEdit,
          onReviewQueue: onReviewQueue,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

/// Pinned primary actions. Keeping them out of the scrolling list means the
/// owner's edit/delete and the visitor's interest button are always reachable.
class _ActionBar extends StatelessWidget {
  final bool isOwner;
  final bool isSendingInterest;
  final VoidCallback onSendInterest;
  final VoidCallback onEdit;
  final VoidCallback onReviewQueue;
  final VoidCallback onDelete;

  const _ActionBar({
    required this.isOwner,
    required this.isSendingInterest,
    required this.onSendInterest,
    required this.onEdit,
    required this.onReviewQueue,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: isOwner
            ? Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onReviewQueue,
                      icon: const Icon(Icons.people_alt, size: 18),
                      label: const Text('Review Queue'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('listing_edit'),
                    tooltip: 'Edit listing',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    key: const Key('listing_delete'),
                    tooltip: 'Delete listing',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.passRed),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('listing_interest'),
                      onPressed: isSendingInterest ? null : onSendInterest,
                      icon: isSendingInterest
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.navyDark,
                              ),
                            )
                          : const Icon(Icons.favorite, size: 20),
                      label: Text(
                        isSendingInterest
                            ? 'Sending interest...'
                            : "I'm interested",
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Interest is private. A chat opens only if the owner '
                    'approves.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: AppTheme.navyDark,
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_work_outlined,
                size: 48, color: Colors.grey.shade500),
            const SizedBox(height: 8),
            const Text(
              'No photo added',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
