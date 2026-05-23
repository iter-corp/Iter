import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme/app_theme.dart';

/// Shared toolbar for the admin reports screens (post / discuss / profile /
/// error). Owns the search field state, the select-mode toggle, and the
/// bulk-delete UI. Each report screen wires three callbacks:
///
/// * `onQueryChanged` — fired on every keystroke so the screen can filter
///   its own list (we don't impose a uniform model here because each
///   report type has a different shape).
/// * `onDeleteSelected` — fired when the admin confirms deleting the
///   currently-checked rows. The screen owns the selection set.
/// * `onDeleteAll` — fired when the admin confirms a "delete all visible"
///   action. The toolbar shows the confirmation dialog; the screen does
///   the actual deletion.
///
/// The widget exposes a [ReportsToolbarController] (created via
/// [ReportsToolbarController.create]) so its parent can drive selection
/// mode (e.g. to exit selection mode after a successful bulk delete).
class ReportsToolbar extends StatefulWidget {
  final ReportsToolbarController controller;
  // Number of rows currently selected — drives the "N selected" text and
  // the enable state of the delete-selected button.
  final int selectedCount;
  // Number of rows currently visible (i.e. after the search filter has
  // been applied). Used by the "delete all" confirmation and to show
  // "select all" only when there is something to select.
  final int visibleCount;

  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final Future<void> Function() onDeleteSelected;
  final Future<void> Function() onDeleteAll;

  const ReportsToolbar({
    super.key,
    required this.controller,
    required this.selectedCount,
    required this.visibleCount,
    required this.onQueryChanged,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onDeleteSelected,
    required this.onDeleteAll,
  });

  @override
  State<ReportsToolbar> createState() => _ReportsToolbarState();
}

/// Controller used by the parent screen to drive the toolbar's selection
/// mode. The parent calls `enterSelectionMode()` to turn on per-row
/// checkboxes (e.g. from a row long-press) and `exitSelectionMode()`
/// after a successful bulk action.
class ReportsToolbarController extends ChangeNotifier {
  bool _selecting = false;
  bool get isSelecting => _selecting;

  void enterSelectionMode() {
    if (_selecting) return;
    _selecting = true;
    notifyListeners();
  }

  void exitSelectionMode() {
    if (!_selecting) return;
    _selecting = false;
    notifyListeners();
  }

  static ReportsToolbarController create() => ReportsToolbarController();
}

class _ReportsToolbarState extends State<ReportsToolbar> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _searchCtrl.addListener(() => widget.onQueryChanged(_searchCtrl.text));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteSelected() async {
    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.adminReportsDeleteSelectedTitle(widget.selectedCount)),
        content: Text(t.adminReportsDeleteSelectedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onDeleteSelected();
  }

  Future<void> _confirmDeleteAll() async {
    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.adminReportsDeleteAllTitle),
        content: Text(t.adminReportsDeleteAllBody(widget.visibleCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onDeleteAll();
  }

  @override
  Widget build(BuildContext context) {
    final selecting = widget.controller.isSelecting;
    final t = context.t;
    return Material(
      color: context.surfaceSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Column(
          children: [
            // Search field — always visible. Disabling it during selection
            // mode would be confusing; admins might want to search within
            // their selection.
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.adminReportsSearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: t.clear,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      ),
                filled: true,
                fillColor: context.cardBg,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Action row — Select / Delete-all when idle, selection
            // controls when in selection mode.
            if (!selecting)
              Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.visibleCount == 0
                        ? null
                        : widget.controller.enterSelectionMode,
                    icon: const Icon(Icons.check_box_outlined, size: 18),
                    label: Text(t.adminReportsSelect),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed:
                        widget.visibleCount == 0 ? null : _confirmDeleteAll,
                    icon: const Icon(Icons.delete_sweep_outlined,
                        size: 18, color: Colors.red),
                    label: Text(
                      t.adminReportsDeleteAll,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  IconButton(
                    tooltip: t.adminReportsCancelSelection,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      widget.onClearSelection();
                      widget.controller.exitSelectionMode();
                    },
                  ),
                  Text(
                    t.adminReportsSelectedCount(widget.selectedCount),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.selectedCount == widget.visibleCount
                        ? widget.onClearSelection
                        : widget.onSelectAll,
                    child: Text(
                      widget.selectedCount == widget.visibleCount
                          ? t.adminReportsSelectNone
                          : t.adminReportsSelectAll,
                    ),
                  ),
                  IconButton(
                    tooltip: t.delete,
                    onPressed: widget.selectedCount == 0
                        ? null
                        : _confirmDeleteSelected,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
