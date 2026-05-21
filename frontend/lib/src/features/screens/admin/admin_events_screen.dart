import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_strings.dart';
import '../../../providers/admin_providers.dart';
import '../../../services/admin_service.dart';
import '../../../services/storage_service.dart';
import '../../../theme/app_theme.dart';

class AdminEventsScreen extends ConsumerWidget {
  const AdminEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the role-scoped provider so an org_admin sees only their
    // own events here. Full admins see everything (same result as
    // adminEventsProvider). The public events page keeps using the
    // unfiltered adminEventsProvider so users see everyone's events.
    final eventsAsync = ref.watch(manageableEventsProvider);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: Text(context.t.events),
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
        label: Text(context.t.adminNewEvent,
            style: const TextStyle(color: Colors.white)),
      ),
      body: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Text(context.t.adminNoEventsYet,
                  style: TextStyle(color: context.textSecondary)),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.only(bottom: bottomInset + 12),
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
                            child:
                                Icon(Icons.event, color: context.textSecondary),
                          ),
                  ),
                ),
                title:
                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteEventDialog(),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminServiceProvider).deleteEvent(id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.t.failedWithError(e))));
      }
    }
  }
}

class _DeleteEventDialog extends StatefulWidget {
  const _DeleteEventDialog();

  @override
  State<_DeleteEventDialog> createState() => _DeleteEventDialogState();
}

class _DeleteEventDialogState extends State<_DeleteEventDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t.adminDeleteEventTitle),
      content: Text(context.t.adminDeleteEventBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            false,
          ),
          child: Text(context.t.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            true,
          ),
          child: Text(
            context.t.delete,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}

class _EventEditorScreen extends ConsumerStatefulWidget {
  final AdminEvent? existing;
  const _EventEditorScreen({this.existing});

  @override
  ConsumerState<_EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<_EventEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  // Inline validation errors. Cleared on each save attempt, populated
  // for whichever required fields are empty so the user can see every
  // problem at once instead of fixing one snackbar at a time.
  String? _titleError;
  String? _eventTypeError;
  String? _countryError;
  String? _descError;
  String? _imagesError;

  final List<String> _imageUrls = [];
  bool _saving = false;
  bool _uploadingImage = false;
  String _eventType = '';
  String _country = '';
  DateTime? _deadlineAt;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _subtitleCtrl.text = e.subtitle;
      _descCtrl.text = e.description;
      _linkCtrl.text = e.link;
      _phoneCtrl.text = e.phone;
      _emailCtrl.text = e.email;
      _imageUrls.addAll(e.imageUrls);
      _eventType = e.eventType;
      _country = e.country.isNotEmpty ? e.country : e.location;
      _deadlineAt = e.deadlineAt;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _descCtrl.dispose();
    _linkCtrl.dispose();
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
      setState(() {
        _imageUrls.add(url);
        _imagesError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.t.adminUploadFailed(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (_deadlineAt != null && _deadlineAt!.isAfter(today))
        ? _deadlineAt!
        : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 20),
      helpText: context.t.adminSelectDeadline,
    );
    if (picked == null) return;
    setState(() => _deadlineAt = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    // Validate every required field in one pass so the user sees all
    // problems at once instead of being snackbar-pinged one at a time.
    final titleError =
        _titleCtrl.text.trim().isEmpty ? context.t.adminTitleRequired : null;
    final eventTypeError =
        _eventType.trim().isEmpty ? context.t.adminPickEventType : null;
    final countryError =
        _country.trim().isEmpty ? context.t.adminCountryRequired : null;
    final descError = _descCtrl.text.trim().isEmpty
        ? context.t.adminDescriptionRequired
        : null;
    final imagesError =
        _imageUrls.isEmpty ? context.t.adminAddAtLeastOneImage : null;
    setState(() {
      _titleError = titleError;
      _eventTypeError = eventTypeError;
      _countryError = countryError;
      _descError = descError;
      _imagesError = imagesError;
    });
    if (titleError != null ||
        eventTypeError != null ||
        countryError != null ||
        descError != null ||
        imagesError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.t.adminFixHighlightedFields),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final admin = ref.read(adminServiceProvider);
      final data = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'subtitle': _subtitleCtrl.text.trim(),
        // Location now mirrors country so event cards/details keep one source.
        'location': _country.trim(),
        'description': _descCtrl.text.trim(),
        'link': _linkCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'imageUrls': _imageUrls,
        'deadline': _deadlineAt,
        'eventType': _eventType,
        'country': _country,
      };
      if (widget.existing == null) {
        await admin.createEvent(
          title: data['title']! as String,
          subtitle: data['subtitle']! as String,
          location: data['location']! as String,
          description: data['description']! as String,
          link: data['link']! as String,
          phone: data['phone']! as String,
          email: data['email']! as String,
          imageUrls: _imageUrls,
          deadlineAt: _deadlineAt,
          eventType: _eventType,
          country: _country,
        );
      } else {
        await admin.updateEvent(widget.existing!.id, data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.t.adminSaveFailed(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final cfg = ref.watch(adminConfigProvider).value ?? const AdminConfig();
    // Keep event types aligned with the canonical list requested by product.
    final typeOptions = <String>{
      ...kEventTypes,
      if (_eventType.isNotEmpty) _eventType,
    }.toList();
    final countryOptions = <String>{
      ...cfg.eventCountries,
      if (_country.isNotEmpty) _country,
    }.toList();
    return Scaffold(
      backgroundColor: context.surfaceSoft,
      appBar: AppBar(
        title: Text(isNew ? context.t.adminNewEvent : context.t.adminEditEvent),
        backgroundColor: context.cardBg,
        foregroundColor: context.textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    if (_formKey.currentState?.validate() ?? false) {
                      _save();
                    }
                  },
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.t.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset + 12),
          children: [
            _refinedField(
              label: context.t.adminFieldTitle,
              controller: _titleCtrl,
              hint: context.t.adminEnterEventTitle,
              required: true,
              errorText: _titleError,
              textInputAction: TextInputAction.next,
              onChanged: (v) {
                if (_titleError != null && v.trim().isNotEmpty) {
                  setState(() => _titleError = null);
                }
              },
            ),
            _refinedField(
              label: context.t.adminFieldSubtitle,
              controller: _subtitleCtrl,
              hint: context.t.adminShortSubtitleOptional,
              textInputAction: TextInputAction.next,
            ),
            _SearchablePickerField(
              placeholder: context.t.adminFieldEventType,
              sheetTitle: context.t.adminChooseEventType,
              searchHint: context.t.adminSearchEventType,
              options: typeOptions,
              selected: _eventType.isEmpty ? null : _eventType,
              onChanged: (v) {
                setState(() {
                  _eventType = v;
                  _eventTypeError = null;
                });
              },
            ),
            if (_eventTypeError != null)
              _FieldError(text: _eventTypeError!),
            _SearchablePickerField(
              placeholder: context.t.adminFieldCountry,
              sheetTitle: context.t.adminChooseCountry,
              searchHint: context.t.adminSearchCountry,
              options: countryOptions,
              selected: _country.isEmpty ? null : _country,
              onChanged: (v) {
                setState(() {
                  _country = v;
                  _countryError = null;
                });
              },
            ),
            if (_countryError != null) _FieldError(text: _countryError!),
            _DeadlineField(
              deadlineAt: _deadlineAt,
              onPick: _pickDeadline,
              onClear: _deadlineAt == null
                  ? null
                  : () => setState(() => _deadlineAt = null),
            ),
            _refinedField(
              label: context.t.adminFieldDescription,
              controller: _descCtrl,
              hint: context.t.adminDescribeTheEvent,
              maxLines: 4,
              required: true,
              errorText: _descError,
              textInputAction: TextInputAction.newline,
              onChanged: (v) {
                if (_descError != null && v.trim().isNotEmpty) {
                  setState(() => _descError = null);
                }
              },
            ),
            _refinedField(
              label: context.t.adminFieldLink,
              controller: _linkCtrl,
              hint: context.t.adminRegistrationOrInfoLink,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            _refinedField(
              label: context.t.adminFieldPhone,
              controller: _phoneCtrl,
              hint: context.t.adminContactPhoneOptional,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            _refinedField(
              label: context.t.adminFieldEmail,
              controller: _emailCtrl,
              hint: context.t.adminContactEmailOptional,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(context.t.adminFieldImages,
                    style: TextStyle(
                        color: context.textSecondary,
                        fontWeight: FontWeight.w600)),
                const Text(' *',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            if (_imagesError != null) _FieldError(text: _imagesError!),
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
      ),
    );
  }

  Widget _refinedField({
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    bool required = false,
    String? errorText,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(12),
        color: context.cardBg,
        child: TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          style: TextStyle(fontSize: 15, color: context.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint ?? label,
            filled: true,
            fillColor: context.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            errorText: errorText,
          ),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty)
                  ? context.t.adminFieldIsRequired(label)
                  : null
              : null,
        ),
      ),
    );
  }
}

/// Small inline validation message shown directly under a picker /
/// image section that cannot host its own `errorText`. Matches the
/// look of Flutter's default `TextField` error: 12px red caption,
/// 6px left padding to align with field content.
class _FieldError extends StatelessWidget {
  final String text;
  const _FieldError({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, top: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _DeadlineField extends StatelessWidget {
  final DateTime? deadlineAt;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _DeadlineField({
    required this.deadlineAt,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final label = deadlineAt == null
        ? context.t.adminFieldDeadline
        : MaterialLocalizations.of(context).formatMediumDate(deadlineAt!);
    return GestureDetector(
      onTap: onPick,
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: deadlineAt != null
                      ? context.textPrimary
                      : context.textSecondary,
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
                tooltip: context.t.adminClearDeadline,
              ),
            Icon(Icons.calendar_month, color: context.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─── Searchable picker field/sheet (5 visible rows + scroll) ───────────────

class _SearchablePickerField extends StatelessWidget {
  final String placeholder;
  final String sheetTitle;
  final String searchHint;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onChanged;

  const _SearchablePickerField({
    required this.placeholder,
    required this.sheetTitle,
    required this.searchHint,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        title: sheetTitle,
        searchHint: searchHint,
        options: options,
        selected: selected,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected ?? placeholder,
                style: TextStyle(
                  fontSize: 14,
                  color: selected != null
                      ? context.textPrimary
                      : context.textSecondary,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: context.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  final String title;
  final String searchHint;
  final List<String> options;
  final String? selected;

  const _PickerSheet({
    required this.title,
    required this.searchHint,
    required this.options,
    required this.selected,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _searchCtrl = TextEditingController();
  List<String> _filtered = [];

  // Height for exactly 5 rows + search bar + handle
  static const double _itemH = 52.0;
  static const int _visibleRows = 5;

  @override
  void initState() {
    super.initState();
    _filtered = List.of(widget.options);
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.of(widget.options)
          : widget.options.where((c) => c.toLowerCase().contains(q)).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cap visible height to _visibleRows items; shrink if fewer results.
    final listH = (_filtered.length.clamp(1, _visibleRows)) * _itemH;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: context.surfaceSoft,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // scrollable list — fixed height = 5 items
            SizedBox(
              height: listH,
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        context.t.adminNoResults,
                        style: TextStyle(color: context.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemExtent: _itemH,
                      itemBuilder: (_, i) {
                        final c = _filtered[i];
                        final isSelected = c == widget.selected;
                        return ListTile(
                          dense: true,
                          title: Text(c),
                          trailing: isSelected
                              ? const Icon(Icons.check,
                                  size: 18, color: Color(0xFF7E3BE8))
                              : null,
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
