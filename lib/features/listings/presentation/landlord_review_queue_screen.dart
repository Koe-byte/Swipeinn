import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/listing_model.dart';
import '../../auth/domain/user_model.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'student_discovery_screen.dart';
import '../../matches/presentation/matches_provider.dart';

class LandlordReviewQueueScreen extends ConsumerStatefulWidget {
  final ListingModel listing;

  const LandlordReviewQueueScreen({Key? key, required this.listing}) : super(key: key);

  @override
  ConsumerState<LandlordReviewQueueScreen> createState() => _LandlordReviewQueueScreenState();
}

class _LandlordReviewQueueScreenState extends ConsumerState<LandlordReviewQueueScreen> {
  int _currentIndex = 0;

  // Mock list of prospective students who liked this listing
  final List<UserModel> _interestedStudents = [
    const UserModel(
      uid: 'student_sample_1',
      email: 'maria.santos@ust.edu.ph',
      displayName: 'Maria Santos',
      photoUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=400&q=80',
      role: UserRole.student,
      isVerified: true,
      school: 'UST Faculty of Pharmacy',
      budgetMax: 5000.0,
      lifestyleTags: ['Non-Smoker', 'Quiet Study', 'Organized'],
      bio: '2nd Year Pharmacy student. Looking for a quiet place close to campus to study for board exams.',
    ),
    const UserModel(
      uid: 'student_sample_2',
      email: 'christian.reyes@dlsu.edu.ph',
      displayName: 'Christian Reyes',
      photoUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=400&q=80',
      role: UserRole.student,
      isVerified: true,
      school: 'DLSU College of Engineering',
      budgetMax: 6000.0,
      lifestyleTags: ['Early Bird', 'Clean', 'No Parties'],
      bio: 'Engineering junior. Respectful of quiet hours and looking for move-in starting next semester.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final likesMap = ref.watch(studentLikesProvider);
    final likedStudentUids = likesMap[widget.listing.id] ?? {};

    // Filter students who actually liked this listing
    final user = ref.watch(authStateProvider).valueOrNull;
    final allStudents = [
      if (user != null && user.role == UserRole.student && !_interestedStudents.any((s) => s.uid == user.uid))
        user,
      ..._interestedStudents,
    ];

    final studentsInQueue = allStudents
        .where((s) => likedStudentUids.contains(s.uid) || s.uid.startsWith('student_sample'))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Review: ${widget.listing.title}'),
      ),
      body: studentsInQueue.isEmpty || _currentIndex >= studentsInQueue.length
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mark_email_read_outlined, size: 64, color: AppTheme.textSecondary),
                    const SizedBox(height: 16),
                    const Text(
                      'All student inquiries reviewed!',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'When new students like this listing, they will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _StudentCard(student: studentsInQueue[_currentIndex]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Pass Button
                      FloatingActionButton(
                        heroTag: 'pass_student',
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.passRed,
                        elevation: 4,
                        onPressed: () {
                          setState(() => _currentIndex++);
                        },
                        child: const Icon(Icons.close, size: 32),
                      ),
                      // Approve / Match Button
                      FloatingActionButton(
                        heroTag: 'approve_student',
                        backgroundColor: AppTheme.likeGreen,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        onPressed: () {
                          final student = studentsInQueue[_currentIndex];
                          // Create deterministic match: ${listingId}_${studentUid}
                          ref.read(matchesProvider.notifier).createBilateralMatch(
                                listingId: widget.listing.id,
                                landlordUid: widget.listing.landlordUid,
                                studentUid: student.uid,
                              );

                          _showMatchCelebration(context, student);
                          setState(() => _currentIndex++);
                        },
                        child: const Icon(Icons.check, size: 36),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  void _showMatchCelebration(BuildContext context, UserModel student) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: const [
            Icon(Icons.celebration, color: AppTheme.primaryAmber, size: 28),
            SizedBox(width: 8),
            Text('Mutual Match!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You and ${student.displayName} have approved each other for "${widget.listing.title}".',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryAmber),
              ),
              child: Text(
                '24h First Move: ${student.displayName} will initiate the chat within 24 hours to schedule a viewing.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue Reviewing'),
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final UserModel student;

  const _StudentCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage: student.photoUrl.isNotEmpty
                      ? NetworkImage(student.photoUrl)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              student.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                            ),
                          ),
                          if (student.isVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified, color: AppTheme.verifiedBlue, size: 20),
                          ]
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        student.school,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAmber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          student.demographics != null
                              ? (student.demographics!.paxCount == 1
                                  ? 'Solo (1 Pax)'
                                  : student.demographics!.paxCount == 2
                                      ? 'Pair (2 Pax)'
                                      : 'Squad (${student.demographics!.paxCount}+ Pax)')
                              : 'Solo (1 Pax)',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.navyDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            const Text(
              'Tenant Bio & Study Habits',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(student.bio),
            const SizedBox(height: 16),
            const Text(
              'Lifestyle Tags',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: student.lifestyleTags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                      backgroundColor: Colors.blue.shade50,
                      labelStyle: const TextStyle(color: AppTheme.navyDark, fontSize: 12),
                    ),
                  )
                  .toList(),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Budget Ceiling:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '₱${student.budgetMax.toStringAsFixed(0)} / mo',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navyDark),
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
