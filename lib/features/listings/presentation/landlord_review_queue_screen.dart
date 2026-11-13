import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../matches/presentation/matches_provider.dart';
import '../domain/listing_model.dart';
import 'student_discovery_screen.dart';

/// Who expressed interest in one of your listings. Approving a renter opens a
/// chat, which is the only way a conversation can start.
class LandlordReviewQueueScreen extends ConsumerWidget {
  final ListingModel listing;

  const LandlordReviewQueueScreen({Key? key, required this.listing})
      : super(key: key);

  void _approve(BuildContext context, WidgetRef ref, String renterUid) {
    ref.read(matchesProvider.notifier).createBilateralMatch(
          listingId: listing.id,
          landlordUid: listing.landlordUid,
          studentUid: renterUid,
        );

    // The request is settled once approved, so drop it from the pending list.
    final likesMap = ref.read(studentLikesProvider);
    final remaining = (likesMap[listing.id] ?? <String>{})
      ..removeWhere((uid) => uid == renterUid);
    ref.read(studentLikesProvider.notifier).state = {
      ...likesMap,
      listing.id: remaining,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Approved. The chat is now in Matches.'),
        backgroundColor: AppTheme.navyDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final likesMap = ref.watch(studentLikesProvider);
    final interestedUids = likesMap[listing.id] ?? const <String>{};

    return Scaffold(
      appBar: AppBar(title: Text('Interest: ${listing.title}')),
      body: interestedUids.isEmpty
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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              itemCount: interestedUids.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final uid = interestedUids.elementAt(index);
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryAmber,
                      child: const Icon(Icons.person, color: AppTheme.navyDark),
                    ),
                    title: Text(
                      uid.length > 12
                          ? 'Renter ${uid.substring(uid.length - 6)}'
                          : uid,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Wants to view this place'),
                    trailing: FilledButton(
                      onPressed: () => _approve(context, ref, uid),
                      child: const Text('Approve'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
