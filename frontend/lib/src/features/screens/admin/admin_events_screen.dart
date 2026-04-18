import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../providers/admin_providers.dart';
import '../../../services/admin_service.dart';
import '../../../services/storage_service.dart';
import '../../../theme/app_theme.dart';

class AdminEventsScreen extends ConsumerWidget {
  const AdminEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(adminEventsProvider);

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: const Text('Events'),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const _EventEditorScreen()),
        ),
        backgroundColor: const Color(0xFF7E3BE8),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New event', style: TextStyle(color: Colors.white)),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Text('No events yet. Tap "New event" to add one.',
                  style: TextStyle(color: context.textSecondary)),
            );
          }
          return ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = events[i];
              final url = e.imageUrls.isNotEmpty ? e.imageUrls.first : null;
              return ListTile(
                leading: SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: url != null
                        ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                        : Container(
                            color: context.inputFill,
                            child: Icon(Icons.event,
                                color: context.textSecondary),
                          ),
                  ),
                ),
                title: Text(e.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  e.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _EventEditorScreen(existing: e),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(context, ref, e.id),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete event?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(adminServiceProvider).deleteEvent(id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    }
  }
}

class _EventEditorScreen extends ConsumerStatefulWidget {
  final AdminEvent? existing;
  const _EventEditorScreen({this.existing});

  @override
  ConsumerState<_EventEditorScreen> createState() =>
      _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<_EventEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final List<String> _imageUrls = [];
  bool _saving = false;
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _subtitleCtrl.text = e.subtitle;
      _locationCtrl.text = e.location;
      _descCtrl.text = e.description;
      _phoneCtrl.text = e.phone;
      _emailCtrl.text = e.email;
      _imageUrls.addAll(e.imageUrls);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_uploadingImage) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (picked == null) return;
    setState(() => _uploadingImage = true);
    try {
      // Re-use the post bucket / kind for now — event images go to the same
      // bucket under the admin's uid/posts folder.
      final url = await StorageService().uploadPostImage(File(picked.path));
      setState(() => _imageUrls.add(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Title is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final admin = ref.read(adminServiceProvider);
      final data = {
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'imageUrls': _imageUrls,
      };
      if (widget.existing == null) {
        await admin.createEvent(
          title: data['title']! as String,
          subtitle: data['subtitle']! as String,
          location: data['location']! as String,
          description: data['description']! as String,
          phone: data['phone']! as String,
          email: data['email']! as String,
          imageUrls: _imageUrls,
        );
      } else {
        await admin.updateEvent(widget.existing!.id, data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: Text(isNew ? 'New event' : 'Edit event'),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Title', _titleCtrl),
          _field('Subtitle', _subtitleCtrl),
          _field('Location', _locationCtrl),
          _field('Description', _descCtrl, maxLines: 4),
          _field('Phone', _phoneCtrl),
          _field('Email', _emailCtrl),
          const SizedBox(height: 8),
          Text('Images',
              style: TextStyle(
                  color: context.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._imageUrls.map((u) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: u,
                          width: 86,
                          height: 86,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _imageUrls.remove(u)),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  )),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: context.cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: _uploadingImage
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.add_a_photo_outlined,
                          color: context.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: label,
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
