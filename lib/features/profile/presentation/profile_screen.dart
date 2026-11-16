import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/route_names.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/domain/user_model.dart';
import '../../auth/presentation/auth_provider.dart';

/// Account hub: identity, search preferences, and session actions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  static final NumberFormat _peso = NumberFormat.decimalPattern();

  String _budgetLabel(RenterPreferences preferences) {
    return '₱${_peso.format(preferences.budgetMin)} – '
        '₱${_peso.format(preferences.budgetMax)} / month';
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(initialName: currentName),
    );
    if (result == null) return;

    final name = result.trim();
    if (name.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A display name cannot be empty.')),
      );
      return;
    }

    final saved =
        await ref.read(authStateProvider.notifier).updateDisplayName(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Name updated.'
              : 'Could not update your name. Check your connection and try '
                  'again.',
        ),
      ),
    );
  }

  Future<void> _editPreferences(BuildContext context) async {
    final saved = await Navigator.of(context)
        .pushNamed<bool>(AppRoutes.preferencesEditor);
    if (!context.mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preferences updated.')),
    );
  }

  Future<void> _editPhoto(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('profile_photo_choose'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, 'choose'),
            ),
            if (user.photoUrl.isNotEmpty)
              ListTile(
                key: const Key('profile_photo_remove'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;

    final notifier = ref.read(authStateProvider.notifier);

    if (action == 'remove') {
      final error = await notifier.removeProfilePhoto();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Profile photo removed.')),
      );
      return;
    }

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 900,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the photo picker: $error')),
      );
      return;
    }
    if (picked == null || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    if (bytes.lengthInBytes > PhotoStorageService.maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That photo is larger than 5 MB.')),
      );
      return;
    }

    final error = await notifier.updateProfilePhoto(
      bytes: bytes,
      fileName: picked.name,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Profile photo updated.')),
    );
  }

  Future<void> _sendVerificationEmail(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    final notifier = ref.read(authStateProvider.notifier);
    final sent = await notifier.resendVerificationEmail();
    if (!context.mounted) return;

    final message = sent
        ? 'Verification link sent to $email. Open it, then tap Refresh.'
        : (ref.read(authStateProvider).errorMessage ??
            'Could not send the verification link.');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: sent
            ? SnackBarAction(
                label: 'Refresh',
                onPressed: notifier.refreshVerification,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final preferences = user?.preferences;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _ProfileAvatar(
                user: user,
                onTap: user == null ? null : () => _editPhoto(context, ref),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    user?.displayName ?? 'Swipeinn user',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('profile_edit_name'),
                  tooltip: 'Edit display name',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: user == null
                      ? null
                      : () => _editName(context, ref, user.displayName),
                ),
                if (user?.isOwnerVerified == true)
                  const Icon(Icons.verified,
                      color: AppTheme.verifiedBlue, size: 20),
              ],
            ),
            Text(
              user?.email ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            if (user?.isOwnerVerified == true) ...[
              const SizedBox(height: 8),
              const Center(
                child: Chip(
                  avatar: Icon(Icons.workspace_premium, size: 16),
                  label: Text('Verified owner'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Your preferences',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const Key('profile_edit_prefs'),
                          onPressed: user == null
                              ? null
                              : () => _editPreferences(context),
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                    if (preferences == null)
                      const Text(
                        'Not set yet.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      )
                    else ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.home_work_outlined,
                            color: AppTheme.navyDark),
                        title: const Text('Property types'),
                        subtitle: Text(
                          preferences.propertyTypes
                              .map((type) => type.label)
                              .join(', '),
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.payments_outlined,
                            color: AppTheme.navyDark),
                        title: const Text('Monthly budget'),
                        subtitle: Text(_budgetLabel(preferences)),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined,
                            color: AppTheme.navyDark),
                        title: const Text('Preferred areas'),
                        subtitle: Text(
                          preferences.areas.isEmpty
                              ? 'Anywhere'
                              : preferences.areas.join(', '),
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined,
                            color: AppTheme.navyDark),
                        title: const Text('Move-in window'),
                        subtitle: Text(preferences.moveInWindow.label),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.mail_outline,
                        color: AppTheme.navyDark),
                    title: const Text('Email'),
                    subtitle: Text(user?.email ?? ''),
                    trailing: _EmailVerificationStatus(
                      verified: ref.watch(authStateProvider).isEmailVerified,
                      onVerify: user == null
                          ? null
                          : () => _sendVerificationEmail(
                                context,
                                ref,
                                user.email,
                              ),
                    ),
                  ),
                  if ((user?.createdAt ?? 0) > 0)
                    ListTile(
                      leading: const Icon(Icons.calendar_today_outlined,
                          color: AppTheme.navyDark),
                      title: const Text('Member since'),
                      subtitle: Text(
                        DateFormat.yMMMMd().format(
                          DateTime.fromMillisecondsSinceEpoch(user!.createdAt),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => ref.read(authStateProvider.notifier).signOut(),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round avatar with the camera affordance that opens the photo sheet.
class _ProfileAvatar extends StatelessWidget {
  final UserModel? user;
  final VoidCallback? onTap;

  const _ProfileAvatar({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final photoUrl = user?.photoUrl ?? '';
    final initial = user?.displayName.isNotEmpty == true
        ? user!.displayName[0].toUpperCase()
        : 'S';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: AppTheme.primaryAmber,
          // foregroundImage draws over the initial once the bytes arrive and
          // silently falls back to it if the URL cannot be loaded.
          foregroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
          onForegroundImageError: photoUrl.isEmpty ? null : (_, __) {},
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppTheme.navyDark,
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Material(
            color: AppTheme.navyDark,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              key: const Key('profile_photo_button'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Verified" badge, or the button that sends the confirmation link.
class _EmailVerificationStatus extends StatelessWidget {
  final bool verified;
  final VoidCallback? onVerify;

  const _EmailVerificationStatus({
    required this.verified,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    if (verified) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 18, color: AppTheme.likeGreen),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.likeGreen,
            ),
          ),
        ],
      );
    }

    return TextButton(
      key: const Key('profile_verify_email'),
      onPressed: onVerify,
      child: const Text('Verify'),
    );
  }
}

/// Owns the name field's controller so it outlives the dialog's exit
/// animation. Disposing it as soon as `showDialog` returns throws while the
/// route is still fading out.
class _RenameDialog extends StatefulWidget {
  final String initialName;

  const _RenameDialog({required this.initialName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Display name'),
      content: TextField(
        key: const Key('profile_name_field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('profile_name_save'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
