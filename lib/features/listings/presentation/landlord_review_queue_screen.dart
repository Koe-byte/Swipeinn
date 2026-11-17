import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../matches/domain/match_model.dart';
import '../domain/listing_model.dart';
import 'listings_provider.dart';

/// Who expressed interest in one of your listings. Approving a renter opens a
/// chat, which is the only way a conversation can start.
class LandlordReviewQueueScreen extends ConsumerWidget {
  final ListingModel listing;

  const LandlordReviewQueueScreen({Key? key, required this.listing})
      : super(key: key);

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    ListingLike like,
  ) async {
    final now = DateTime.now();
    final match = MatchModel(
      id: '${listing.id}_${like.requesterUid}',
      listingId: listing.id,
      listingTitle: listing.title,
      ownerUid: listing.ownerUid,
      requesterUid: like.requesterUid,
      participantUids: [listing.ownerUid, like.requesterUid],
      status: MatchStatus.active,
      matchedAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );

    try {
      // One database function creates the match and closes the like in the
      // same transaction. Without it a failure between the two writes could
      // leave an approved renter with no chat, or a chat still in the queue.
      final approved = await ref
          .read(listingsRepositoryProvider)
          .approveInterest(match: match);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'Approved. The chat is now in Matches.'
                : 'Approval saved on this device. It will sync once the '
                    'connection is back.',
          ),
          backgroundColor: AppTheme.navyDark,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not approve this request: $error')),
      );
    }
  }

  Future<void> _reject(
    BuildContext context,
    WidgetRef ref,
    ListingLike like,
  ) async {
    try {
      final rejected = await ref.read(listingsRepositoryProvider).rejectInterest(
            listingId: listing.id,
            requesterUid: like.requesterUid,
          );
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            rejected
                ? 'Passed on ${like.displayName}. They will not be notified.'
                : 'Rejection saved on this device. It will sync once the '
                    'connection is back.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                final reopened = await ref
                    .read(listingsRepositoryProvider)
                    .reopenInterest(
                      listingId: listing.id,
                      requesterUid: like.requesterUid,
                    );
                if (!reopened) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'The request is back here. The undo will sync once the '
                        'connection is back.',
                      ),
                    ),
                  );
                }
              } catch (error) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Could not undo that: $error')),
                );
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pass on this request: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likesAsync = ref.watch(pendingLikesProvider(listing.id));

    return Scaffold(
      appBar: AppBar(title: Text('Interest: ${listing.title}')),
      body: likesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Could not load interest: $error'),
        ),
        data: (likes) => likes.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hourglass_empty,
                          size: 56, color: AppTheme.textSecondary),
                      const SizedBox(height: 16),
                      const Text(
                        'No interest yet',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'When someone likes "${listing.title}", they appear here for you to approve.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: likes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final like = likes[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryAmber,
                        child:
                            const Icon(Icons.person, color: AppTheme.navyDark),
                      ),
                      title: Text(
                        like.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text('Wants to view this place'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('reject_interest_${like.requesterUid}'),
                            tooltip: 'Not a fit',
                            onPressed: () => _reject(context, ref, like),
                            icon: const Icon(Icons.close,
                                color: AppTheme.passRed),
                          ),
                          const SizedBox(width: 4),
                          FilledButton(
                            onPressed: () => _approve(context, ref, like),
                            child: const Text('Approve'),
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
