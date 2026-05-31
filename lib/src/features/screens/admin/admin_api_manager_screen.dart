import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_page_background.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class ApiKeyEntry {
  final String id;
  final String provider;
  final String maskedKey;
  final bool active;
  final String? statusMessage;
  final DateTime? lastChecked;
  // Lower number = tried first. Default 999 = unset (added last).
  final int priority;

  const ApiKeyEntry({
    required this.id,
    required this.provider,
    required this.maskedKey,
    required this.active,
    this.statusMessage,
    this.lastChecked,
    this.priority = 999,
  });

  factory ApiKeyEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final raw = (d['key'] as String?) ?? '';
    final masked = raw.length > 8
        ? '${raw.substring(0, 4)}${'•' * (raw.length - 8)}${raw.substring(raw.length - 4)}'
        : '•' * raw.length;
    return ApiKeyEntry(
      id: doc.id,
      provider: (d['provider'] as String?) ?? '',
      maskedKey: masked,
      active: (d['active'] as bool?) ?? true,
      statusMessage: d['statusMessage'] as String?,
      lastChecked: (d['lastChecked'] as Timestamp?)?.toDate(),
      priority: (d['priority'] as num?)?.toInt() ?? 999,
    );
  }
}

class ApiLogEntry {
  final String id;
  final String provider;
  final String keyId;
  final bool success;
  final bool wasFallback;    // true = another provider was tried first
  final String? error;       // set when success==false
  final String? nextProvider; // which provider it fell back TO (if any)
  final DateTime? createdAt;

  const ApiLogEntry({
    required this.id,
    required this.provider,
    required this.keyId,
    required this.success,
    required this.wasFallback,
    this.error,
    this.nextProvider,
    this.createdAt,
  });

  factory ApiLogEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return ApiLogEntry(
      id: doc.id,
      provider: (d['provider'] as String?) ?? '',
      keyId: (d['keyId'] as String?) ?? '',
      success: (d['success'] as bool?) ?? false,
      wasFallback: (d['wasFallback'] as bool?) ?? false,
      error: d['error'] as String?,
      nextProvider: d['nextProvider'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─── Supported providers ────────────────────────────────────────────────────

class _ApiProvider {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  const _ApiProvider({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const _kProviders = [
  _ApiProvider(
    id: 'claude',
    name: 'Anthropic Claude',
    description: 'Claude 3.5 / Claude 3 Haiku / Opus',
    icon: Icons.psychology_outlined,
    color: Color(0xFF7E3BE8),
  ),
  _ApiProvider(
    id: 'openai',
    name: 'OpenAI',
    description: 'GPT-4o / GPT-4 Turbo / GPT-3.5',
    icon: Icons.auto_awesome_outlined,
    color: Color(0xFF10A37F),
  ),
  _ApiProvider(
    id: 'azure',
    name: 'Microsoft Azure AI',
    description: 'Azure Translator (Kurdish-primary)',
    icon: Icons.cloud_outlined,
    color: Color(0xFF0078D4),
  ),
  _ApiProvider(
    id: 'gemini',
    name: 'Google Gemini',
    description: 'Gemini 2.0 Flash / 1.5 Pro',
    icon: Icons.stars_outlined,
    color: Color(0xFF4285F4),
  ),
];

_ApiProvider? _providerMeta(String id) {
  try {
    return _kProviders.firstWhere((p) => p.id == id.toLowerCase());
  } catch (_) {
    return null;
  }
}

// ─── Firestore service ───────────────────────────────────────────────────────

class _ApiKeyService {
  final _col = FirebaseFirestore.instance.collection('apiKeys');
  final _logCol = FirebaseFirestore.instance.collection('apiLogs');

  // Keys stream — sorted client-side by priority then createdAt to avoid
  // needing a Firestore composite index.
  Stream<List<ApiKeyEntry>> streamKeys() {
    return _col
        .snapshots()
        .map((s) {
          final list = s.docs.map(ApiKeyEntry.fromDoc).toList();
          list.sort((a, b) => a.priority.compareTo(b.priority));
          return list;
        });
  }

  // Error log stream — newest first, last 200.
  Stream<List<ApiLogEntry>> streamLogs() {
    return _logCol
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map(ApiLogEntry.fromDoc).toList());
  }

  Future<void> add({required String provider, required String key, required int priority}) {
    return _col.add({
      'provider': provider,
      'key': key,
      'active': true,
      'statusMessage': null,
      'lastChecked': null,
      'priority': priority,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();

  Future<void> setActive(String id, bool active) =>
      _col.doc(id).update({'active': active});

  Future<void> setPriority(String id, int priority) =>
      _col.doc(id).update({'priority': priority});

  Future<void> clearLogs() =>
      _logCol.limit(500).get().then((s) async {
        for (final d in s.docs) {
          await d.reference.delete();
        }
      });
}

// ─── Providers ───────────────────────────────────────────────────────────────

final _apiKeyServiceProvider = Provider((_) => _ApiKeyService());

final _apiKeysProvider = StreamProvider<List<ApiKeyEntry>>((ref) {
  return ref.watch(_apiKeyServiceProvider).streamKeys();
});

final _apiLogsProvider = StreamProvider<List<ApiLogEntry>>((ref) {
  return ref.watch(_apiKeyServiceProvider).streamLogs();
});

// ─── Screen ─────────────────────────────────────────────────────────────────

class AdminApiManagerScreen extends ConsumerWidget {
  const AdminApiManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(context.t.adminApiManager),
          backgroundColor: Colors.transparent,
          foregroundColor: context.textPrimary,
          elevation: 0,
          flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
          bottom: TabBar(
            labelColor: AppColors.purple,
            unselectedLabelColor: context.textSecondary,
            indicatorColor: AppColors.purple,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(icon: Icon(Icons.vpn_key_outlined), text: 'Keys'),
              Tab(icon: Icon(Icons.history_outlined), text: 'API Log'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: context.t.add,
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _showAddSheet(context, ref),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: AppPageBackground(
          child: TabBarView(
            children: [
              _KeysTab(onAddTap: () => _showAddSheet(context, ref)),
              _LogTab(ref: ref),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    final keys = ref.read(_apiKeysProvider).valueOrNull ?? [];
    // Default priority = next after existing keys for this provider.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddKeySheet(
        service: ref.read(_apiKeyServiceProvider),
        existingKeys: keys,
      ),
    );
  }
}

// ─── Keys tab ────────────────────────────────────────────────────────────────

class _KeysTab extends ConsumerWidget {
  final VoidCallback onAddTap;
  const _KeysTab({required this.onAddTap});

  @override
  Widget build(BuildContext context, WidgetRef r) {
    final keysAsync = r.watch(_apiKeysProvider);
    return keysAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
      data: (keys) {
        if (keys.isEmpty) {
          return _emptyState(context, r);
        }

        // Group by provider for display.
        final byProvider = <String, List<ApiKeyEntry>>{};
        for (final k in keys) {
          byProvider.putIfAbsent(k.provider, () => []).add(k);
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16, 16, 16, 28 + MediaQuery.paddingOf(context).bottom),
          children: [
            // Fallback order explanation banner.
            _FallbackOrderBanner(keys: keys),
            const SizedBox(height: 16),
            _SectionHeader('API KEYS  ·  drag to reorder priority'),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: keys.length,
              onReorder: (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex--;
                final reordered = List<ApiKeyEntry>.from(keys);
                final moved = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, moved);
                // Write new priority values (0, 1, 2, …).
                final svc = r.read(_apiKeyServiceProvider);
                for (var i = 0; i < reordered.length; i++) {
                  if (reordered[i].priority != i) {
                    await svc.setPriority(reordered[i].id, i);
                  }
                }
              },
              itemBuilder: (ctx, i) => _ApiKeyTile(
                key: ValueKey(keys[i].id),
                entry: keys[i],
                rank: i + 1,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef r) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key_outlined, size: 56, color: context.textMuted),
            const SizedBox(height: 16),
            Text(
              context.t.adminApiManagerEmpty,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                  color: context.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(context.t.adminApiManagerEmptySubtitle,
                style: TextStyle(color: context.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAddTap,
              icon: const Icon(Icons.add),
              label: Text(context.t.adminApiManagerAddKey),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.purple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Fallback order banner ───────────────────────────────────────────────────

class _FallbackOrderBanner extends StatelessWidget {
  final List<ApiKeyEntry> keys;
  const _FallbackOrderBanner({required this.keys});

  @override
  Widget build(BuildContext context) {
    final active = keys.where((k) => k.active).toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return AppGlassCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      surfaceAlpha: context.isDark ? 0.20 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route_outlined, size: 16,
                  color: AppColors.purple),
              const SizedBox(width: 6),
              Text(
                'Fallback order',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < active.length; i++) ...[
                if (i > 0)
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 10, color: context.textMuted),
                _ProviderBadge(entry: active[i], rank: i + 1),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  final ApiKeyEntry entry;
  final int rank;
  const _ProviderBadge({required this.entry, required this.rank});

  @override
  Widget build(BuildContext context) {
    final meta = _providerMeta(entry.provider);
    final color = meta?.color ?? AppColors.purple;
    final name = meta?.name ?? entry.provider;
    final hasError = entry.statusMessage != null &&
        entry.statusMessage!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasError
              ? Colors.orange.withValues(alpha: 0.6)
              : color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$rank.',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          if (hasError) ...[
            const SizedBox(width: 4),
            const Icon(Icons.warning_amber_rounded, size: 11,
                color: Colors.orange),
          ],
        ],
      ),
    );
  }
}

// ─── API Key tile ────────────────────────────────────────────────────────────

class _ApiKeyTile extends ConsumerWidget {
  final ApiKeyEntry entry;
  final int rank;

  const _ApiKeyTile({super.key, required this.entry, required this.rank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = _providerMeta(entry.provider);
    final color = meta?.color ?? AppColors.purple;
    final name = meta?.name ?? entry.provider;
    final description = meta?.description ?? '';
    final icon = meta?.icon ?? Icons.key_outlined;
    final service = ref.read(_apiKeyServiceProvider);

    final hasError = entry.active &&
        entry.statusMessage != null &&
        entry.statusMessage!.isNotEmpty;
    final statusColor = !entry.active
        ? Colors.grey
        : hasError
            ? Colors.orange
            : Colors.green;
    final statusLabel = !entry.active
        ? context.t.adminApiManagerDisabled
        : hasError
            ? entry.statusMessage!
            : context.t.adminApiManagerActive;

    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      borderAlpha: entry.active ? 0.55 : 0.20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
        child: Row(
          children: [
            // Drag handle + rank number.
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ReorderableDragStartListener(
                  index: rank - 1,
                  child: Icon(Icons.drag_handle_rounded,
                      color: context.textMuted, size: 20),
                ),
                Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            // Provider icon.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: entry.active
                                ? context.textPrimary
                                : context.textSecondary,
                          ),
                        ),
                      ),
                      // Status dot.
                      Container(
                        width: 8, height: 8,
                        margin: const EdgeInsetsDirectional.only(start: 4),
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty)
                    Text(description,
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(
                    entry.maskedKey,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: context.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        hasError
                            ? Icons.warning_amber_rounded
                            : !entry.active
                                ? Icons.pause_circle_outline
                                : Icons.check_circle_outline,
                        size: 11,
                        color: statusColor,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: context.textSecondary,
                  size: 20),
              onSelected: (action) async {
                if (action == 'toggle') {
                  await service.setActive(entry.id, !entry.active);
                } else if (action == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.t.adminApiManagerDeleteTitle),
                      content: Text(ctx.t.adminApiManagerDeleteBody),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(ctx.t.cancel),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(ctx.t.delete),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await service.delete(entry.id);
                } else if (action == 'copy') {
                  await Clipboard.setData(
                      ClipboardData(text: entry.maskedKey));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t.copied)),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(entry.active
                      ? context.t.adminApiManagerDisableKey
                      : context.t.adminApiManagerEnableKey),
                ),
                PopupMenuItem(
                  value: 'copy',
                  child: Text(context.t.copy),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.t.delete,
                      style: const TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── API Log tab ─────────────────────────────────────────────────────────────

class _LogTab extends ConsumerWidget {
  final WidgetRef ref;
  const _LogTab({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef r) {
    final logsAsync = r.watch(_apiLogsProvider);
    return logsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
      data: (logs) {
        return Column(
          children: [
            // Header row with clear button.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${logs.length} entries',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (logs.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear API log?'),
                            content: const Text(
                                'All log entries will be permanently removed.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(ctx.t.cancel),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Clear'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await r.read(_apiKeyServiceProvider).clearLogs();
                        }
                      },
                      icon: const Icon(Icons.cleaning_services_outlined,
                          size: 16),
                      label: const Text('Clear'),
                    ),
                ],
              ),
            ),
            if (logs.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_outlined,
                          size: 48, color: context.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'No API activity yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Translation requests will appear here.',
                        style:
                            TextStyle(color: context.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      12, 4, 12, 24 + MediaQuery.paddingOf(context).bottom),
                  itemCount: logs.length,
                  itemBuilder: (_, i) => _LogTile(entry: logs[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Log tile ────────────────────────────────────────────────────────────────

class _LogTile extends StatelessWidget {
  final ApiLogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final meta = _providerMeta(entry.provider);
    final color = meta?.color ?? AppColors.purple;
    final name = meta?.name ?? entry.provider;
    final icon = meta?.icon ?? Icons.key_outlined;
    final ts = entry.createdAt;
    final timeStr = ts == null
        ? '—'
        : DateFormat('MMM d, HH:mm:ss').format(ts.toLocal());

    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      radius: 14,
      borderAlpha: entry.success ? 0.30 : 0.65,
      surfaceAlpha: entry.success
          ? (context.isDark ? 0.18 : 0.40)
          : (context.isDark ? 0.28 : 0.52),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status icon.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                entry.success
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color: entry.success ? Colors.green : Colors.red,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: context.textPrimary,
                        ),
                      ),
                      if (entry.wasFallback) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'FALLBACK',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.orange,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (!entry.success && entry.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.error!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.red,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (!entry.success && entry.nextProvider != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.alt_route_outlined,
                            size: 12, color: context.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Fell back to: ${_providerMeta(entry.nextProvider!)?.name ?? entry.nextProvider!}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add key sheet ───────────────────────────────────────────────────────────

class _AddKeySheet extends StatefulWidget {
  final _ApiKeyService service;
  final List<ApiKeyEntry> existingKeys;

  const _AddKeySheet({
    required this.service,
    required this.existingKeys,
  });

  @override
  State<_AddKeySheet> createState() => _AddKeySheetState();
}

class _AddKeySheetState extends State<_AddKeySheet> {
  String _selectedProvider = _kProviders.first.id;
  final _keyCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  int get _nextPriority {
    if (widget.existingKeys.isEmpty) return 0;
    return widget.existingKeys
            .map((k) => k.priority)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  Future<void> _save() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = context.t.adminApiManagerKeyRequired);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.service.add(
        provider: _selectedProvider,
        key: key,
        priority: _nextPriority,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t.adminApiManagerAddKey,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.t.adminApiManagerSelectProvider,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary),
              ),
              const SizedBox(height: 12),
              ..._kProviders.map((p) {
                final selected = _selectedProvider == p.id;
                return GestureDetector(
                  onTap: () => setState(() => _selectedProvider = p.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? p.color.withValues(alpha: 0.10)
                          : context.inputFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? p.color.withValues(alpha: 0.60)
                            : context.borderColor,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(p.icon, color: p.color, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary)),
                              Text(p.description,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.textSecondary)),
                            ],
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle_rounded, color: p.color),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Text(
                context.t.adminApiManagerApiKey,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyCtrl,
                obscureText: _obscure,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: context.t.adminApiManagerKeyHint,
                  filled: true,
                  fillColor: context.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.borderColor),
                  ),
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.t.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Text(context.t.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
