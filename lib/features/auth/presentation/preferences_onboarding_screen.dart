import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/user_model.dart';
import 'auth_provider.dart';
import 'auth_ui.dart';

/// Required two-step onboarding shown once, after the email is verified.
/// Step 1 tunes the feed by property type and budget; step 2 by area and
/// move-in timing.
class PreferencesOnboardingScreen extends ConsumerStatefulWidget {
  /// When true the same two-step form edits existing answers from the profile
  /// screen instead of gating a first-time account.
  final bool editing;

  const PreferencesOnboardingScreen({Key? key, this.editing = false})
      : super(key: key);

  @override
  ConsumerState<PreferencesOnboardingScreen> createState() =>
      _PreferencesOnboardingScreenState();
}

class _PreferencesOnboardingScreenState
    extends ConsumerState<PreferencesOnboardingScreen> {
  static const int _maxBudget = 50000;
  static final NumberFormat _peso = NumberFormat.decimalPattern();

  int _step = 0;
  final Set<PropertyType> _propertyTypes = {};
  RangeValues _budget = const RangeValues(3000, 15000);
  MoveInWindow _moveInWindow = MoveInWindow.flexible;
  final _areasController = TextEditingController();

  String _budgetLabel() {
    return '₱${_peso.format(_budget.start.round())} – '
        '₱${_peso.format(_budget.end.round())} / month';
  }

  @override
  void initState() {
    super.initState();
    final existing = ref.read(authStateProvider).user?.preferences;
    if (existing != null) {
      _propertyTypes.addAll(existing.propertyTypes);
      _budget = RangeValues(
        existing.budgetMin.toDouble(),
        existing.budgetMax.toDouble(),
      );
      _moveInWindow = existing.moveInWindow;
      _areasController.text = existing.areas.join(', ');
    }
  }

  @override
  void dispose() {
    _areasController.dispose();
    super.dispose();
  }

  void _next() {
    if (_propertyTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one property type.')),
      );
      return;
    }
    setState(() => _step = 1);
  }

  Future<void> _finish() async {
    final areas = _areasController.text
        .split(',')
        .map((area) => area.trim())
        .where((area) => area.isNotEmpty)
        .toList();

    final preferences = RenterPreferences(
      propertyTypes: _propertyTypes.toList(),
      budgetMin: _budget.start.round(),
      budgetMax: _budget.end.round(),
      areas: areas,
      moveInWindow: _moveInWindow,
    );

    FocusScope.of(context).unfocus();
    final notifier = ref.read(authStateProvider.notifier);

    if (!widget.editing) {
      await notifier.completeOnboarding(preferences);
      return;
    }

    final saved = await notifier.updatePreferences(preferences);
    if (!mounted || !saved) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authStateProvider);
    final name = state.user?.displayName ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: widget.editing,
        title: Text(widget.editing ? 'Edit preferences' : 'Your preferences'),
        actions: [
          if (!widget.editing)
            TextButton(
              onPressed: state.isSubmitting
                  ? null
                  : ref.read(authStateProvider.notifier).signOut,
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: (_step + 1) / 2,
                    backgroundColor: Colors.grey.shade200,
                    color: AppTheme.primaryAmber,
                    minHeight: 6,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step ${_step + 1} of 2',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (state.errorMessage != null)
                    AuthErrorBanner(message: state.errorMessage!),
                  if (_step == 0)
                    ..._buildStepOne(name)
                  else
                    ..._buildStepTwo(state.isSubmitting),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStepOne(String name) {
    return [
      Text(
        name.isEmpty
            ? 'What are you looking for?'
            : 'What are you looking for, $name?',
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppTheme.navyDark,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Pick every type you would consider, and a monthly budget. Your budget sets the first rent filter.',
        style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: PropertyType.values.map((type) {
          final selected = _propertyTypes.contains(type);
          return FilterChip(
            label: Text(type.label),
            selected: selected,
            onSelected: (value) {
              setState(() {
                if (value) {
                  _propertyTypes.add(type);
                } else {
                  _propertyTypes.remove(type);
                }
              });
            },
            selectedColor: AppTheme.primaryAmber.withOpacity(0.35),
            checkmarkColor: AppTheme.navyDark,
          );
        }).toList(),
      ),
      const SizedBox(height: 28),
      const Text(
        'Monthly budget (PHP)',
        style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.navyDark),
      ),
      const SizedBox(height: 4),
      Text(
        _budgetLabel(),
        style: const TextStyle(color: AppTheme.textSecondary),
      ),
      RangeSlider(
        values: _budget,
        min: 1000,
        max: _maxBudget.toDouble(),
        divisions: 49,
        activeColor: AppTheme.primaryAmber,
        labels: RangeLabels(
          _peso.format(_budget.start.round()),
          _peso.format(_budget.end.round()),
        ),
        onChanged: (values) => setState(() => _budget = values),
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        key: const Key('prefs_next'),
        onPressed: _next,
        child: const Text('Continue'),
      ),
    ];
  }

  List<Widget> _buildStepTwo(bool isSubmitting) {
    return [
      const Text(
        'Where and when?',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppTheme.navyDark,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Optional, but it helps us rank listings you can actually visit.',
        style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _areasController,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: 'Preferred areas',
          hintText: 'e.g. Lahug, Cebu City',
          helperText: 'Separate multiple areas with commas.',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'When do you want to move in?',
        style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.navyDark),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: MoveInWindow.values.map((window) {
          return ChoiceChip(
            label: Text(window.label),
            selected: _moveInWindow == window,
            onSelected: (_) => setState(() => _moveInWindow = window),
            selectedColor: AppTheme.primaryAmber.withOpacity(0.35),
          );
        }).toList(),
      ),
      const SizedBox(height: 28),
      ElevatedButton(
        key: const Key('prefs_finish'),
        onPressed: isSubmitting ? null : _finish,
        child: isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.navyDark,
                ),
              )
            : Text(widget.editing ? 'Save preferences' : 'Start browsing'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: isSubmitting ? null : () => setState(() => _step = 0),
        child: const Text('Back'),
      ),
    ];
  }
}
