import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/photo_storage_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_provider.dart';
import '../domain/listing_model.dart';
import 'listings_provider.dart';

/// One form for publishing a new place and for editing an existing one.
/// Photos upload to the listing-photos bucket only when the form is saved, so
/// cancelling an edit never leaves an orphaned object behind.
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
  static const int _maxPhotos = 5;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _rentController;

  late PropertyType _propertyType;
  late ListingStatus _status;
  late Set<String> _amenities;

  /// Public URLs already saved on the listing.
  late List<String> _photos;

  /// Picked but not uploaded yet; bytes stay in memory until save.
  final List<_PickedPhoto> _pickedPhotos = [];

  /// Existing photos the person removed, deleted only after a successful save.
  final List<String> _removedPhotoUrls = [];

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
    _photos = [...?listing?.photos];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _rentController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final slots = _maxPhotos - _photos.length - _pickedPhotos.length;
    if (slots <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add at most $_maxPhotos photos.')),
      );
      return;
    }

    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked.isEmpty || !mounted) return;

      var index = 0;
      for (final file in picked.take(slots)) {
        final bytes = await file.readAsBytes();
        if (bytes.lengthInBytes > PhotoStorageService.maxBytes) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${file.name} is larger than 5 MB and was skipped.'),
            ),
          );
          continue;
        }
        final photo = _PickedPhoto(
          bytes: bytes,
          fileName: _fileNameFor(file.name, index),
        );
        index++;
        if (!mounted) return;
        setState(() => _pickedPhotos.add(photo));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the photo picker: $error')),
      );
    }
  }

  static String _fileNameFor(String original, int index) {
    final dot = original.lastIndexOf('.');
    final extension = dot >= 0 ? original.substring(dot).toLowerCase() : '.jpg';
    return 'photo_${DateTime.now().microsecondsSinceEpoch}_$index$extension';
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final rent = double.parse(_rentController.text.trim());

    final listing = widget.listing;
    // The id has to exist before upload: it is part of the object path.
    final listingId =
        listing?.id ?? 'listing_${DateTime.now().microsecondsSinceEpoch}';

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final uploadedUrls = <String>[];

    try {
      for (final photo in _pickedPhotos) {
        uploadedUrls.add(
          await PhotoStorageService.instance.uploadListingPhoto(
            ownerUid: user.uid,
            listingId: listingId,
            bytes: photo.bytes,
            fileName: photo.fileName,
          ),
        );
      }

      final photos = [..._photos, ...uploadedUrls];

      final saved = listing == null
          ? ListingModel(
              id: listingId,
              ownerUid: user.uid,
              title: title,
              description:
                  description.isEmpty ? 'Newly posted listing.' : description,
              monthlyRent: rent,
              propertyType: _propertyType,
              photos: photos,
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
              photos: photos,
              amenities: _amenities.toList()..sort(),
              status: _status,
            );

      final repository = ref.read(listingsRepositoryProvider);
      if (listing == null) {
        await repository.publish(saved);
      } else {
        await repository.updateListing(saved);
      }

      for (final url in _removedPhotoUrls) {
        unawaited(PhotoStorageService.instance.deletePhotoByUrl(url));
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
      // Keep anything already uploaded so a retry does not store it twice.
      setState(() {
        _photos = [..._photos, ...uploadedUrls];
        _pickedPhotos.clear();
        _saving = false;
      });
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
            const SizedBox(height: 24),
            const _FieldLabel('Photos'),
            const SizedBox(height: 4),
            Text(
              'Up to $_maxPhotos photos, 5 MB each. The first one becomes the '
              'card image.',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var index = 0; index < _photos.length; index++)
                    _PhotoTile(
                      key: ValueKey('photo_existing_$index'),
                      image: NetworkImage(_photos[index]),
                      onRemove: () => setState(() {
                        _removedPhotoUrls.add(_photos.removeAt(index));
                      }),
                    ),
                  for (var index = 0; index < _pickedPhotos.length; index++)
                    _PhotoTile(
                      key: ValueKey('photo_picked_$index'),
                      image: MemoryImage(_pickedPhotos[index].bytes),
                      onRemove: () => setState(
                        () => _pickedPhotos.removeAt(index),
                      ),
                    ),
                  if (_photos.length + _pickedPhotos.length < _maxPhotos)
                    _AddPhotoTile(onTap: _saving ? null : _pickPhotos),
                ],
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

/// Bytes held in memory between picking and saving.
class _PickedPhoto {
  final Uint8List bytes;
  final String fileName;

  const _PickedPhoto({required this.bytes, required this.fileName});
}

class _PhotoTile extends StatelessWidget {
  final ImageProvider image;
  final VoidCallback onRemove;

  const _PhotoTile({
    Key? key,
    required this.image,
    required this.onRemove,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 96,
              height: 96,
              child: Image(image: image, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddPhotoTile({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade400),
          color: Colors.grey.shade100,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.add_a_photo_outlined,
                size: 22, color: AppTheme.textSecondary),
            SizedBox(height: 4),
            Text(
              'Add photo',
              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
