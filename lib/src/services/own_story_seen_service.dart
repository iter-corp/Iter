import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which of the *current device user's own* stories the user has
/// already viewed. Stored locally on the device — own-story views are
/// intentionally NOT written to Firestore (the viewers list would
/// include the author, which Instagram-style social UX hides), so we
/// need a side channel to dim the ring on the home rail once the
/// author has flipped through their own stories.
///
/// Keyed by story id. Values are kept until the story expires (24h)
/// and clean themselves up when the story doc disappears from
/// `activeStoriesProvider`; we don't need a sweeper.
class OwnStorySeenService {
  static const _prefix = 'own_story_seen_';
  // Stores the viewers count on a story at the last moment the author
  // opened it themselves. When the live count exceeds this number,
  // there are new viewers and the home ring should re-highlight.
  static const _viewerCountPrefix = 'own_story_seen_viewers_';

  Future<bool> isSeen(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$storyId') ?? false;
  }

  Future<void> markSeen(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$storyId', true);
  }

  Future<int> lastSeenViewerCount(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_viewerCountPrefix$storyId') ?? 0;
  }

  Future<void> setLastSeenViewerCount(String storyId, int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_viewerCountPrefix$storyId', count);
  }
}

final ownStorySeenServiceProvider =
    Provider<OwnStorySeenService>((_) => OwnStorySeenService());

/// Snapshot the author keeps locally for each of their own stories:
/// whether they've opened it once + the viewers count at that moment.
/// Used to decide if the home ring should re-highlight when a new
/// viewer arrives after the author's last visit.
class OwnStorySeenState {
  final Set<String> seen;
  final Map<String, int> lastSeenViewers;
  const OwnStorySeenState({
    this.seen = const <String>{},
    this.lastSeenViewers = const <String, int>{},
  });

  OwnStorySeenState copyWith({
    Set<String>? seen,
    Map<String, int>? lastSeenViewers,
  }) =>
      OwnStorySeenState(
        seen: seen ?? this.seen,
        lastSeenViewers: lastSeenViewers ?? this.lastSeenViewers,
      );
}

/// In-memory mirror of `OwnStorySeenService`. Holds both the "did the
/// author open this story?" flag and the viewers count at the moment
/// they opened it, so the home rail can re-highlight a story the
/// moment a new viewer arrives.
class OwnStorySeenNotifier extends StateNotifier<OwnStorySeenState> {
  OwnStorySeenNotifier(this._service) : super(const OwnStorySeenState()) {
    _hydrate();
  }

  final OwnStorySeenService _service;

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = <String>{};
    final counts = <String, int>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith(OwnStorySeenService._viewerCountPrefix)) {
        final id =
            k.substring(OwnStorySeenService._viewerCountPrefix.length);
        counts[id] = prefs.getInt(k) ?? 0;
      } else if (k.startsWith(OwnStorySeenService._prefix) &&
          !k.startsWith(OwnStorySeenService._viewerCountPrefix) &&
          prefs.getBool(k) == true) {
        seen.add(k.substring(OwnStorySeenService._prefix.length));
      }
    }
    if (mounted) {
      state = OwnStorySeenState(seen: seen, lastSeenViewers: counts);
    }
  }

  Future<void> markSeen(String storyId, {int? currentViewerCount}) async {
    await _service.markSeen(storyId);
    if (currentViewerCount != null) {
      await _service.setLastSeenViewerCount(storyId, currentViewerCount);
    }
    if (!mounted) return;
    state = state.copyWith(
      seen: {...state.seen, storyId},
      lastSeenViewers: currentViewerCount == null
          ? null
          : {...state.lastSeenViewers, storyId: currentViewerCount},
    );
  }

  bool isSeen(String storyId) => state.seen.contains(storyId);
  int lastSeenViewerCount(String storyId) =>
      state.lastSeenViewers[storyId] ?? 0;
}

final ownStorySeenProvider =
    StateNotifierProvider<OwnStorySeenNotifier, OwnStorySeenState>(
  (ref) => OwnStorySeenNotifier(ref.watch(ownStorySeenServiceProvider)),
);

/// Pair: story id + current live viewers count from Firestore. The
/// home bubble passes one of these per own-story so the derived
/// provider can decide whether to re-highlight.
class OwnStoryViewerSnapshot {
  final String id;
  final int viewerCount;
  const OwnStoryViewerSnapshot(this.id, this.viewerCount);

  @override
  bool operator ==(Object other) =>
      other is OwnStoryViewerSnapshot &&
      other.id == id &&
      other.viewerCount == viewerCount;
  @override
  int get hashCode => Object.hash(id, viewerCount);
}

/// Reactive "have I seen all of these?" — false if any own-story
/// either hasn't been opened yet OR has gained new viewers since the
/// last time the author opened it. The home story bubble watches this
/// and the ring updates the moment a friend hits the author's story.
final ownStoriesAllSeenProvider =
    Provider.family<bool, List<OwnStoryViewerSnapshot>>((ref, snapshots) {
  if (snapshots.isEmpty) return true;
  final state = ref.watch(ownStorySeenProvider);
  for (final s in snapshots) {
    if (!state.seen.contains(s.id)) return false;
    final last = state.lastSeenViewers[s.id] ?? 0;
    if (s.viewerCount > last) return false;
  }
  return true;
});
