import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_provider.dart';
import '../domain/listing_model.dart';
import 'listings_provider.dart';

/// One form for publishing a new place and for editing an existing one.
/// Photos are intentionally untouched here; upload is a separate feature.
class ListingEditorScreen extends ConsumerStatefulWidget {
  /// Null creates a new listing.
  final ListingModel? listing;

  const ListingEditorScreen({Key? key, this.listing}) : super(key: key);

  bool get isEditing => listing != null;

  @override
  ConsumerState<ListingEditorScreen> createState() =>
      _ListingEditorScreenState();
}

class _ListingEditorScreenState extends ConsumerState<ListingEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _rentController;

  late PropertyType _propertyType;
  late ListingStatus _status;
  late Set<String> _amenities;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final listing = widget.listing;
    _titleController = TextEditingController(text: listing?.title ?? '');
    _descriptionController =
        TextEditingController(text: listing?.description ?? '');
    _rentController = TextEditingController(
      text: listing == null ? '' : listing.monthlyRent.toStringAsFixed(0),
    );
    _propertyType = listing?.propertyType ?? PropertyType.room;
    _status = listing?.status ?? ListingStatus.available;
    _amenities = {...?listing?.amenities};
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _rentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final rent = double.parse(_rentController.text.trim());

    final listing = widget.listing;
    final saved = listing == null
        ? ListingModel(
            id: 'listing_${DateTime.now().microsecondsSinceEpoch}',
            ownerUid: user.uid,
            title: title,
            description:
                description.isEmpty ? 'Newly posted listing.' : description,
            monthlyRent: rent,
            propertyType: _propertyType,
            photos: const [],
            amenities: _amenities.toList()..sort(),
            latitude: 14.6090,
            longitude: 120.9890,
            status: _status,
            createdAt: DateTime.now(),
          )
        : listing.copyWith(
            title: title,
            description:
                description.isEmpty ? 'Newly posted listing.' : description,
            monthlyRent: rent,
            propertyType: _propertyType,
            amenities: _amenities.toList()..sort(),
            status: _status,
          );

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final repository = ref.read(listingsRepositoryProvider);
      if (listing == null) {
        await repository.publish(saved);
      } else {
        await repository.updateListing(saved);
      }
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            listing == null
                ? '"${saved.title}" is now in Discover.'
                : '"${saved.title}" was updated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save this listing: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Edit listing' : 'Publish New Listing Card',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              key: const Key('listing_title'),
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Listing Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Give the listing a title.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('listing_description'),
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'What makes this place worth a look?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('listing_rent'),
              controller: _rentController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monthly Rent (₱)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              validator: (value) {
                final rent = double.tryParse(value?.trim() ?? '');
                if (rent == null || rent <= 0) {
                  return 'Enter a monthly rent above zero.';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            const _FieldLabel('Property type'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PropertyType.values.map((type) {
                return ChoiceChip(
                  label: Text(type.label),
                  selected: _propertyType == type,
                  onSelected: (_) => setState(() => _propertyType = type),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const _FieldLabel('Amenities'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: listingAmenityOptions.map((amenity) {
                final selected = _amenities.contains(amenity);
                return FilterChip(
                  label: Text(amenity),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _amenities.add(amenity);
                      } else {
                        _amenities.remove(amenity);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const _FieldLabel('Availability'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ListingStatus.values.map((status) {
                return ChoiceChip(
                  label: Text(
                    status == ListingStatus.full
                        ? 'Full / hidden'
                        : status.name,
                  ),
                  selected: _status == status,
                  onSelected: (_) => setState(() => _status = status),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            const Text(
              'Photos can be added in a later update. A listing without a '
              'photo still shows up in Discover.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ElevatedButton(
          key: const Key('listing_save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.navyDark,
                  ),
                )
              : Text(
                  widget.isEditing ? 'Save changes' : 'Publish Listing Card',
                ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: AppTheme.navyDark,
      ),
    );
  }
}
