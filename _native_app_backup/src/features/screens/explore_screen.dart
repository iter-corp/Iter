import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/post_providers.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../widgets/app_page_background.dart';
import '../widgets/post_card.dart';
import 'chat_screen.dart';
import 'home_screen.dart' show QaThreadCard;

const _kBrandPurple = Color(0xFFB05ECC);
const _kBrandDeep = Color(0xFF8A3FB8);

/// All users, live — filtered client-side by [ExploreBody]'s search query.
/// Mirrors the query the old Connect tab used.
final _explorePeopleStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .limit(300)
      .snapshots()
      .map((snap) => snap.docs.map((d) {
            final data = d.data();
            data['__id'] = d.id;
            return data;
          }).toList());
});

/// One row in Explore's merged search results — a matching person, post,
/// or Discuss question, tagged so the right card renders.
enum _ExploreHitKind { person, post, qa }

class _ExploreHit {
  final _ExploreHitKind kind;
  final Map<String, dynamic>? person;
  final Post? post;
  const _ExploreHit.person(Map<String, dynamic> this.person)
      : kind = _ExploreHitKind.person,
        post = null;
  const _ExploreHit.post(Post this.post)
      : kind = _ExploreHitKind.post,
        person = null;
  const _ExploreHit.qa(Post this.post)
      : kind = _ExploreHitKind.qa,
        person = null;
}

/// The Explore tab — replaces the old standalone Translate tab. Currently
/// just a combined search across people (formerly Connect) and posts /
/// Discuss questions (formerly Home's search); the rest of the screen is
/// intentionally blank for now.
class ExploreBody extends ConsumerStatefulWidget {
  const ExploreBody({super.key});

  @override
  ConsumerState<ExploreBody> createState() => _ExploreBodyState();
}

class _ExploreBodyState extends ConsumerState<ExploreBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final next = _searchCtrl.text.trim();
      if (next != _query) setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_ExploreHit> _buildHits({
    required List<Map<String, dynamic>> people,
    required List<Post> posts,
    required List<Post> qaPosts,
    required String currentUid,
    required Map<String, dynamic>? currentUser,
  }) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];

    final myBlocked = List<String>.from(currentUser?['blockedUsers'] ?? []);
    final peopleHits = people.where((u) {
      if (u['__id'] == currentUid) return false;
      if (myBlocked.contains(u['__id'])) return false;
      final theirBlocked = List<String>.from(u['blockedUsers'] ?? []);
      if (theirBlocked.contains(currentUid)) return false;
      final name = (u['username'] as String? ?? '').toLowerCase();
      final handle = (u['handle'] as String? ?? '').toLowerCase();
      final bio = (u['bio'] as String? ?? '').toLowerCase();
      final city = (u['city'] as String? ?? '').toLowerCase();
      return name.contains(q) ||
          handle.contains(q) ||
          bio.contains(q) ||
          city.contains(q);
    });

    bool matchesPost(Post post) {
      if (post.caption.toLowerCase().contains(q)) return true;
      final place = post.postPlaceName?.toLowerCase();
      if (place != null && place.contains(q)) return true;
      final city = post.postPlaceCity?.toLowerCase();
      if (city != null && city.contains(q)) return true;
      return false;
    }

    return [
      for (final u in peopleHits) _ExploreHit.person(u),
      for (final p in posts.where(matchesPost)) _ExploreHit.post(p),
      for (final p in qaPosts.where(matchesPost)) _ExploreHit.qa(p),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final peopleAsync = ref.watch(_explorePeopleStreamProvider);
    final feedAsync = ref.watch(feedProvider);
    final qaAsync = ref.watch(qaFeedProvider);
    final currentUid = ref.watch(authStateProvider).value?.uid ?? '';
    final currentUser = ref.watch(currentUserDocProvider).valueOrNull;

    final loading = peopleAsync.isLoading && !peopleAsync.hasValue ||
        feedAsync.isLoading && !feedAsync.hasValue ||
        qaAsync.isLoading && !qaAsync.hasValue;

    final hits = _query.isEmpty
        ? const <_ExploreHit>[]
        : _buildHits(
            people: peopleAsync.valueOrNull ?? const [],
            posts: feedAsync.valueOrNull ?? const [],
            qaPosts: qaAsync.valueOrNull ?? const [],
            currentUid: currentUid,
            currentUser: currentUser,
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: AppPageBackground(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.exploreTitle,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t.exploreSubtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppGlassCard(
                      radius: 999,
                      emphasize: _query.isNotEmpty,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: TextField(
                        controller: _searchCtrl,
                        style:
                            TextStyle(color: context.textPrimary, fontSize: 15),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: context.t.exploreSearchHint,
                          hintStyle: TextStyle(color: context.textSecondary),
                          prefixIcon: Icon(Icons.search_rounded,
                              color: _query.isEmpty
                                  ? context.textSecondary
                                  : _kBrandPurple),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(Icons.close_rounded,
                                      color: context.textSecondary),
                                  onPressed: () => _searchCtrl.clear(),
                                ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _query.isEmpty
                    ? _ExploreMessage(
                        icon: Icons.travel_explore_rounded,
                        title: context.t.exploreBlankHint,
                        subtitle: context.t.exploreBlankSubtitle,
                      )
                    : loading
                        ? const Center(child: CircularProgressIndicator())
                        : hits.isEmpty
                            ? _ExploreMessage(
                                icon: Icons.search_off_rounded,
                                title: context.t.eventsNoResultsFor(_query),
                                subtitle: context.t.eventsTryDifferentKeyword,
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 100),
                                itemCount: hits.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final hit = hits[i];
                                  switch (hit.kind) {
                                    case _ExploreHitKind.person:
                                      final u = hit.person!;
                                      return _PersonCard(
                                        uid: u['__id'] as String,
                                        username: (u['username'] as String?) ??
                                            'User',
                                        avatarUrl: u['avatarUrl'] as String?,
                                        bio: (u['bio'] as String?) ?? '',
                                        city: (u['city'] as String?) ?? '',
                                      );
                                    case _ExploreHitKind.qa:
                                      return QaThreadCard(
                                        key: ValueKey('qa_${hit.post!.id}'),
                                        post: hit.post!,
                                      );
                                    case _ExploreHitKind.post:
                                      return PostCard(
                                        key: ValueKey('post_${hit.post!.id}'),
                                        post: hit.post!,
                                      );
                                  }
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered icon + title + subtitle used for Explore's blank and
/// no-results states — matches the app's other empty-state treatments.
class _ExploreMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ExploreMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _kBrandPurple.withValues(alpha: 0.18),
                    _kBrandDeep.withValues(alpha: 0.08),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: _kBrandPurple),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact person result row — the search half of the old Connect tab.
/// Avatar, username, bio, city, and a "wave" button that opens a chat.
class _PersonCard extends ConsumerStatefulWidget {
  final String uid;
  final String username;
  final String? avatarUrl;
  final String bio;
  final String city;

  const _PersonCard({
    required this.uid,
    required this.username,
    required this.avatarUrl,
    required this.bio,
    required this.city,
  });

  @override
  ConsumerState<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends ConsumerState<_PersonCard> {
  bool _sending = false;

  Future<void> _wave() async {
    if (_sending) return;
    final currentUid = ref.read(authStateProvider).value?.uid;
    if (currentUid == null) return;
    setState(() => _sending = true);
    try {
      final chatId = await ref.read(chatServiceProvider).openChat(
            currentUid: currentUid,
            otherUid: widget.uid,
          );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            otherUid: widget.uid,
            otherName: widget.username,
            otherAvatar: widget.avatarUrl ?? '',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.eventsFailedToOpenChat(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presenceAsync = ref.watch(presenceWatchProvider(widget.uid));
    final isOnline = presenceAsync.whenOrNull(data: (p) => p.online) ?? false;

    return GestureDetector(
      onTap: () => openUserProfile(context, uid: widget.uid),
      child: AppGlassCard(
        padding: const EdgeInsets.all(14),
        radius: 22,
        emphasize: isOnline,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFF0F0F5),
                  backgroundImage: widget.avatarUrl != null
                      ? CachedNetworkImageProvider(widget.avatarUrl!)
                      : null,
                  child: widget.avatarUrl == null
                      ? Icon(Icons.person, color: context.textMuted)
                      : null,
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3BD671),
                        shape: BoxShape.circle,
                        border: Border.all(color: context.cardBg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  if (widget.bio.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (widget.city.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.city,
                      style:
                          TextStyle(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _wave,
              child: Container(
                width: 44,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kBrandPurple, _kBrandDeep],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.waving_hand_rounded,
                        color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
