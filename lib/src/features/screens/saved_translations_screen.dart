import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_page_background.dart';

/// Data returned when the user taps a saved entry — used to restore it into
/// the Translate screen's inputs.
class SavedTranslation {
  final String id;
  final String sourceText;
  final String translatedText;
  final String sourceLangLabel;
  final String targetLangLabel;

  const SavedTranslation({
    required this.id,
    required this.sourceText,
    required this.translatedText,
    required this.sourceLangLabel,
    required this.targetLangLabel,
  });

  factory SavedTranslation.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return SavedTranslation(
      id: doc.id,
      sourceText: (d['sourceText'] as String?) ?? '',
      translatedText: (d['translatedText'] as String?) ?? '',
      sourceLangLabel: (d['sourceLangLabel'] as String?) ?? '',
      targetLangLabel: (d['targetLangLabel'] as String?) ?? '',
    );
  }
}

class SavedTranslationsScreen extends StatelessWidget {
  const SavedTranslationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final query = uid == null
        ? null
        : FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('savedTranslations')
            .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: Text(context.t.savedTranslations),
              backgroundColor: Colors.transparent,
              foregroundColor: context.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              floating: true,
              snap: true,
            ),
            if (uid == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(context.t.savedTranslationsSignInPrompt),
                ),
              )
            else
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: query!.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(context.t.errorWithMessage(snap.error!)),
                      ),
                    );
                  }
                  final items =
                      snap.data?.docs.map(SavedTranslation.fromDoc).toList() ??
                          [];
                  if (items.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(),
                    );
                  }
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      24 + MediaQuery.of(context).padding.bottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _SavedTile(item: items[i]),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedTile extends StatelessWidget {
  final SavedTranslation item;
  const _SavedTile({required this.item});

  Future<void> _delete(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedTranslations')
        .doc(item.id)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(context),
      child: AppGlassCard(
        radius: 16,
        surfaceAlpha: context.isDark ? 0.42 : 0.36,
        borderAlpha: context.isDark ? 0.14 : 0.50,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(context, item),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.sourceLangLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: context.textMuted,
                        ),
                      ),
                      Text(
                        item.targetLangLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFCE5DE5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.sourceText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.translatedText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border, size: 48, color: context.textMuted),
            const SizedBox(height: 12),
            Text(
              context.t.savedTranslationsEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
