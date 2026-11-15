import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../matches/data/matches_repository.dart';
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
      // The match is created first so the pending like still exists while the
      // RLS insert policy verifies it; the queue entry is closed afterwards.
      await ref.read(matchesRepositoryProvider).createMatch(match);
      await ref.read(listingsRepositoryProvider).markLikeApproved(
            listingId: listing.id,
            requesterUid: like.requesterUid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Approved. The chat is now in Matches.'),
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
                      trailing: FilledButton(
                        onPressed: () => _approve(context, ref, like),
                        child: const Text('Approve'),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
