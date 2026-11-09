import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/user_model.dart';
import '../auth_provider.dart';
import 'demographic_components.dart';

class StudentDemographicsScreen extends ConsumerStatefulWidget {
  const StudentDemographicsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<StudentDemographicsScreen> createState() => _StudentDemographicsScreenState();
}

class _StudentDemographicsScreenState extends ConsumerState<StudentDemographicsScreen> {
  int _currentStep = 0;

  // Step 1: Pax State
  int _selectedPax = 1;
  bool _isGroupSearch = false;

  // Step 2: Gender Policy State
  String _selectedGenderPolicy = 'any';

  // Step 3: House Rules State
  final Set<String> _selectedHouseRules = {};

  // Step 4: Nearby Essentials State
  final Set<String> _selectedEssentials = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<Map<String, String>> _allEssentials = const [
    {'label': '24/7 Convenience Store', 'emoji': '🏪'},
    {'label': 'Sari-Sari Store', 'emoji': '🛒'},
    {'label': 'Fast Food & Carinderia', 'emoji': '🍔'},
    {'label': 'Printing & School Supplies', 'emoji': '🖨️'},
    {'label': 'Laundromat & Laundry', 'emoji': '🧺'},
    {'label': 'Pharmacy & Drugstore', 'emoji': '💊'},
    {'label': 'Study Cafe & Coffee', 'emoji': '☕'},
    {'label': 'Bank & ATM', 'emoji': '🏧'},
    {'label': 'Public Market & Groceries', 'emoji': '🥦'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _skip() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      ref.read(authStateProvider.notifier).skipStudentDemographics();
    }
  }

  void _submit() {
    final demographics = StudentDemographics(
      paxCount: _selectedPax,
      isGroupSearch: _isGroupSearch,
      genderPolicy: _selectedGenderPolicy,
      houseRules: _selectedHouseRules.toList(),
      nearbyEssentials: _selectedEssentials.toList(),
    );
    ref.read(authStateProvider.notifier).completeStudentDemographics(demographics);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_currentStep + 1) / 4.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppTheme.navyDark),
                onPressed: () => setState(() => _currentStep--),
              )
            : null,
        title: DemographicProgressBar(progress: progress),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: _buildCurrentStepView(),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Pax();
      case 1:
        return _buildStep2Gender();
      case 2:
        return _buildStep3HouseRules();
      case 3:
      default:
        return _buildStep4NearbyEssentials();
    }
  }

  // --- Step 1: Pax ---
  Widget _buildStep1Pax() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How many are looking for a place?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.navyDark,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Choose whether you are moving solo or pooling a dorm with your college friends.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        PaxOptionCard(
          title: 'Solo (1 Pax)',
          subtitle: 'Just me, looking for a room or open bedspace slot.',
          icon: Icons.person_outline,
          isSelected: _selectedPax == 1 && !_isGroupSearch,
          onTap: () {
            setState(() {
              _selectedPax = 1;
              _isGroupSearch = false;
            });
          },
        ),
        const SizedBox(height: 14),
        PaxOptionCard(
          title: 'Pair (2 Pax)',
          subtitle: 'Moving in with 1 roommate / friend.',
          icon: Icons.people_outline,
          isSelected: _selectedPax == 2 && _isGroupSearch,
          onTap: () {
            setState(() {
              _selectedPax = 2;
              _isGroupSearch = true;
            });
          },
        ),
        const SizedBox(height: 14),
        PaxOptionCard(
          title: 'Trio (3 Pax)',
          subtitle: 'Finding a 3-person room, condo, or unit together.',
          icon: Icons.groups_outlined,
          isSelected: _selectedPax == 3 && _isGroupSearch,
          onTap: () {
            setState(() {
              _selectedPax = 3;
              _isGroupSearch = true;
            });
          },
        ),
        const SizedBox(height: 14),
        PaxOptionCard(
          title: 'Squad (4+ Pax)',
          subtitle: 'Large student group seeking an entire floor or unit.',
          icon: Icons.diversity_3_outlined,
          isSelected: _selectedPax >= 4 && _isGroupSearch,
          onTap: () {
            setState(() {
              _selectedPax = 4;
              _isGroupSearch = true;
            });
          },
        ),
      ],
    );
  }

  // --- Step 2: Dorm Gender Policy ---
  Widget _buildStep2Gender() {
    final genderOptions = [
      {'label': 'All-Female', 'value': 'female_only', 'desc': 'Only female residents in unit/floor'},
      {'label': 'All-Male', 'value': 'male_only', 'desc': 'Only male residents in unit/floor'},
      {'label': 'Co-ed / Mixed', 'value': 'mixed', 'desc': 'Open to both male and female residents'},
      {'label': 'Any / No Preference', 'value': 'any', 'desc': 'Flexible on dorm gender arrangement'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dorm gender preference',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.navyDark,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Choose what gender environment you prefer for your dorm or open slot.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 14,
          children: genderOptions.map((opt) {
            final isSelected = _selectedGenderPolicy == opt['value'];
            return PillSelectableChip(
              label: opt['label']!,
              isSelected: isSelected,
              onTap: () {
                setState(() => _selectedGenderPolicy = opt['value']!);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- Step 3: House Rules ---
  Widget _buildStep3HouseRules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Living conditions & rules',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.navyDark,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Select the house rules and living conditions that fit your college lifestyle.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        _buildRuleCategory('Curfew Policy', [
          'No Curfew',
          'Curfew Okay',
        ]),
        const SizedBox(height: 20),
        _buildRuleCategory('Visitors Policy', [
          'Visitors Allowed',
          'Daytime Only',
          'No Visitors',
        ]),
        const SizedBox(height: 20),
        _buildRuleCategory('Pet Policy', [
          'Pets Allowed',
          'No Pets',
        ]),
        const SizedBox(height: 20),
        _buildRuleCategory('Cleanliness & Substances', [
          'Smoke-Free',
          'Alcohol-Free',
          'Strict Cleanliness',
        ]),
      ],
    );
  }

  Widget _buildRuleCategory(String title, List<String> rules) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.navyDark,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: rules.map((rule) {
            final isSelected = _selectedHouseRules.contains(rule);
            return PillSelectableChip(
              label: rule,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedHouseRules.remove(rule);
                  } else {
                    _selectedHouseRules.add(rule);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- Step 4: Nearby Essentials ---
  Widget _buildStep4NearbyEssentials() {
    final filtered = _allEssentials.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item['label']!.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What do you need nearby?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppTheme.navyDark,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Pick up to 5 campus essentials you want within easy reach of your dorm.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('nearby_search_field'),
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search nearby essentials (e.g. store, laundry)...',
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            filled: true,
            fillColor: Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val.trim());
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Campus Essentials',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.navyDark,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: filtered.map((item) {
            final label = item['label']!;
            final emoji = item['emoji']!;
            final isSelected = _selectedEssentials.contains(label);

            return PillSelectableChip(
              label: label,
              emoji: emoji,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedEssentials.remove(label);
                  } else {
                    if (_selectedEssentials.length < 5) {
                      _selectedEssentials.add(label);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You can select up to 5 essentials.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- Bottom Action Bar ---
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _skip,
            child: Text(
              'Skip',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          if (_currentStep == 3)
            Text(
              '${_selectedEssentials.length}/5 selected',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          GestureDetector(
            key: const Key('demographics_next_button'),
            onTap: _nextStep,
            child: Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: AppTheme.navyDark,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
