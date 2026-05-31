import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_page_background.dart';

// ─── Model ──────────────────────────────────────────────────────────────────

class ApiKeyEntry {
  final String id;
  final String provider;
  final String maskedKey;
  final bool active;
  final String? statusMessage;
  final DateTime? lastChecked;

  const ApiKeyEntry({
    required this.id,
    required this.provider,
    required this.maskedKey,
    required this.active,
    this.statusMessage,
    this.lastChecked,
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
    description: 'Azure OpenAI Service deployments',
    icon: Icons.cloud_outlined,
    color: Color(0xFF0078D4),
  ),
  _ApiProvider(
    id: 'gemini',
    name: 'Google Gemini',
    description: 'Gemini 1.5 Pro / Flash / Nano',
    icon: Icons.stars_outlined,
    color: Color(0xFF4285F4),
  ),
];

// ─── Firestore service ───────────────────────────────────────────────────────

class _ApiKeyService {
  final _col = FirebaseFirestore.instance.collection('apiKeys');

  Stream<List<ApiKeyEntry>> stream() {
    return _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ApiKeyEntry.fromDoc).toList());
  }

  Future<void> add({required String provider, required String key}) {
    return _col.add({
      'provider': provider,
      'key': key,
      'active': true,
      'statusMessage': null,
      'lastChecked': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();

  Future<void> setActive(String id, bool active) =>
      _col.doc(id).update({'active': active});
}

// ─── Provider ────────────────────────────────────────────────────────────────

final _apiKeyServiceProvider = Provider((_) => _ApiKeyService());

final _apiKeysProvider = StreamProvider<List<ApiKeyEntry>>((ref) {
  return ref.watch(_apiKeyServiceProvider).stream();
});

// ─── Screen ─────────────────────────────────────────────────────────────────

class AdminApiManagerScreen extends ConsumerWidget {
  const AdminApiManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keysAsync = ref.watch(_apiKeysProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.t.adminApiManager),
        backgroundColor: Colors.transparent,
        foregroundColor: context.textPrimary,
        elevation: 0,
        flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
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
        child: keysAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(context.t.errorWithMessage(e))),
          data: (keys) {
            if (keys.isEmpty) {
              return _emptyState(context, ref);
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _SectionHeader(context.t.adminApiManagerProviders),
                const SizedBox(height: 8),
                ...keys.map((k) => _ApiKeyTile(entry: k)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: keysAsync.valueOrNull?.isNotEmpty == true
          ? FloatingActionButton.extended(
              onPressed: () => _showAddSheet(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.t.adminApiManagerAddKey),
              backgroundColor: AppColors.purple,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _emptyState(BuildContext context, WidgetRef ref) {
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
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.t.adminApiManagerEmptySubtitle,
              style: TextStyle(color: context.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showAddSheet(context, ref),
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

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddKeySheet(service: ref.read(_apiKeyServiceProvider)),
    );
  }
}

// ─── API Key tile ────────────────────────────────────────────────────────────

class _ApiKeyTile extends ConsumerWidget {
  final ApiKeyEntry entry;

  const _ApiKeyTile({required this.entry});

  _ApiProvider? get _meta {
    try {
      return _kProviders.firstWhere((p) => p.id == entry.provider);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = _meta;
    final color = meta?.color ?? AppColors.purple;
    final name = meta?.name ?? entry.provider;
    final description = meta?.description ?? '';
    final icon = meta?.icon ?? Icons.key_outlined;
    final service = ref.read(_apiKeyServiceProvider);

    final statusColor = entry.active
        ? (entry.statusMessage != null && entry.statusMessage!.isNotEmpty)
            ? Colors.orange
            : Colors.green
        : Colors.grey;
    final statusLabel = !entry.active
        ? context.t.adminApiManagerDisabled
        : (entry.statusMessage != null && entry.statusMessage!.isNotEmpty)
            ? entry.statusMessage!
            : context.t.adminApiManagerActive;

    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      radius: 16,
      borderAlpha: entry.active ? 0.55 : 0.20,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
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
                            fontSize: 14,
                            color: entry.active
                                ? context.textPrimary
                                : context.textSecondary,
                          ),
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsetsDirectional.only(start: 6),
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 11.5),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    entry.maskedKey,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: context.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: context.textSecondary),
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
                            backgroundColor: Colors.red,
                          ),
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
                  child: Text(
                    context.t.delete,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
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

  const _AddKeySheet({required this.service});

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

  Future<void> _save() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = context.t.adminApiManagerKeyRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.add(provider: _selectedProvider, key: key);
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
          20,
          16,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
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
                    fontWeight: FontWeight.w600, color: context.textSecondary),
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
                              Text(
                                p.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                p.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                              ),
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
                    fontWeight: FontWeight.w600, color: context.textSecondary),
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
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
