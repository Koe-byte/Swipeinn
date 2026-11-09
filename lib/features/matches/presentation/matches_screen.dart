import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/match_model.dart';
import 'matches_provider.dart';
import '../../listings/presentation/landlord_studio_screen.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../auth/domain/user_model.dart';
import '../../../core/theme/app_theme.dart';
import 'chat_screen.dart';

class MatchesScreen extends ConsumerWidget {
  const MatchesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchesProvider);
    final user = ref.watch(authStateProvider).value;
    final listings = ref.watch(listingsProvider);

    final activeMatches = matches.where((m) => m.status == MatchStatus.active && !m.isExpired).toList();
    final expiredMatches = matches.where((m) => m.isExpired || m.status == MatchStatus.expired).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matched Connections'),
      ),
      body: matches.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.favorite_border, size: 64, color: AppTheme.textSecondary),
                    SizedBox(height: 16),
                    Text(
                      'No matches yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'When mutual interest occurs, your 24h direct chat unlocks here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (activeMatches.isNotEmpty) ...[
                  const Text(
                    'Active Chats (24h Window)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.navyDark),
                  ),
                  const SizedBox(height: 8),
                  ...activeMatches.map((m) {
                    final listing = listings.firstWhere(
                      (l) => l.id == m.listingId,
                      orElse: () => listings.first,
                    );
                    return _MatchCard(
                      match: m,
                      listingTitle: listing.title,
                      isStudent: user?.role == UserRole.student,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(match: m, listingTitle: listing.title),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ],
                if (expiredMatches.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Expired Matches',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  ...expiredMatches.map((m) {
                    final listing = listings.firstWhere(
                      (l) => l.id == m.listingId,
                      orElse: () => listings.first,
                    );
                    return ListTile(
                      tileColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: const Icon(Icons.timer_off_outlined, color: Colors.grey),
                      title: Text(listing.title, style: const TextStyle(color: Colors.grey)),
                      subtitle: const Text('24h First Move elapsed without message'),
                    );
                  }).toList(),
                ],
              ],
            ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final MatchModel match;
  final String listingTitle;
  final bool isStudent;
  final VoidCallback onTap;

  const _MatchCard({
    required this.match,
    required this.listingTitle,
    required this.isStudent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final remainingHours = match.remainingTime.inHours;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppTheme.primaryAmber,
              child: const Icon(Icons.home, color: AppTheme.navyDark),
            ),
            if (match.messagesCount == 0)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        title: Text(listingTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timer, size: 14, color: AppTheme.primaryDarkAmber),
                const SizedBox(width: 4),
                Text(
                  match.messagesCount == 0
                      ? '$remainingHours hrs left for First Move'
                      : 'Chat Unlocked',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: match.messagesCount == 0 ? AppTheme.primaryDarkAmber : AppTheme.likeGreen,
                  ),
                ),
              ],
            ),
            if (match.viewingStatus == ViewingStatus.proposed)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text(
                  '📅 In-Person Inspection Requested',
                  style: TextStyle(fontSize: 12, color: AppTheme.navyDark, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
