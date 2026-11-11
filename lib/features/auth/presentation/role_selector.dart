import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_model.dart';

class RoleSelector extends StatelessWidget {
  final UserRole selected;
  final ValueChanged<UserRole> onChanged;

  const RoleSelector({
    Key? key,
    required this.selected,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            title: 'Student',
            subtitle: 'Find dorms & bedspaces',
            icon: Icons.school_rounded,
            isSelected: selected == UserRole.student,
            onTap: () => onChanged(UserRole.student),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            title: 'Landlord',
            subtitle: 'List rooms & review matches',
            icon: Icons.real_estate_agent_rounded,
            isSelected: selected == UserRole.landlord,
            onTap: () => onChanged(UserRole.landlord),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryAmber.withOpacity(0.15) : Colors.white,
          border: Border.all(
            color: isSelected ? AppTheme.primaryAmber : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 34, color: isSelected ? AppTheme.navyDark : AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
