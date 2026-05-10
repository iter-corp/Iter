import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../services/sticker_data.dart';
import '../../services/sticker_service.dart';

/// Telegram-style sticker picker sheet.
///
/// Layout (top → bottom):
///   ┌──────────────────────────────────┐
///   │  Search bar                      │
///   ├──────────────────────────────────┤
///   │  Sticker grid (scrollable)       │
///   ├──────────────────────────────────┤
///   │  Tab bar (Recent│Fav│Pack1│Pack2…│+)│
///   └──────────────────────────────────┘
///
/// Like Telegram, tabs are at the bottom for thumb-reach on mobile.
class StickerPickerSheet extends ConsumerStatefulWidget {
  final String currentUid;
  final void Function(String stickerUrl, String? packId) onStickerSelected;

  const StickerPickerSheet({
    super.key,
    required this.currentUid,
    required this.onStickerSelected,
  });

  @override
  ConsumerState<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends ConsumerState<StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<String> _recentStickers = [];
  List<String> _favoriteStickers = [];
  bool _loaded = false;

  // Total tabs: Recent + Favorites + built-in packs + custom packs + add(+)
  // We don't include the (+) in the TabController — it's a separate button.

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2 + kBuiltInStickerPacks.length,
      vsync: this,
    );
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    final svc = ref.read(stickerServiceProvider);
    final recent = await svc.getRecentStickers();
    final favs = await svc.getFavoriteStickers();
    if (!mounted) return;
    setState(() {
      _recentStickers = recent;
      _favoriteStickers = favs;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onStickerTap(String stickerUrl, String? packId) {
    // Track in recent
    ref.read(stickerServiceProvider).addRecentSticker(stickerUrl);
    widget.onStickerSelected(stickerUrl, packId);
  }

  Future<void> _onStickerLongPress(String stickerUrl) async {
    final svc = ref.read(stickerServiceProvider);
    final isFav = _favoriteStickers.contains(stickerUrl);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Preview
            Container(
              padding: const EdgeInsets.all(20),
              child: _buildStickerWidget(stickerUrl, size: 120),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isFav ? Icons.star : Icons.star_outline,
                color: const Color(0xFFB05ECC),
              ),
              title: Text(isFav ? 'Remove from favorites' : 'Add to favorites'),
              onTap: () async {
                await svc.toggleFavorite(stickerUrl);
                await _loadLocalData();
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerWidget(String url, {double size = 56}) {
    // Check if it's an emoji (built-in sticker) or an image URL
    if (!url.startsWith('http') && !url.startsWith('asset:')) {
      // It's an emoji string
      return Text(
        url,
        style: TextStyle(fontSize: size * 0.7),
        textAlign: TextAlign.center,
      );
    }
    // Network image (custom sticker)
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholder: (_, __) => SizedBox(
        width: size,
        height: size,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      ),
      errorWidget: (_, __, ___) => Icon(
        Icons.broken_image_outlined,
        size: size * 0.5,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildStickerGrid(List<_StickerItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_emotions_outlined,
                  size: 48, color: context.textMuted),
              const SizedBox(height: 12),
              Text(
                'No stickers here yet',
                style: TextStyle(color: context.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return GestureDetector(
          onTap: () => _onStickerTap(item.url, item.packId),
          onLongPress: () => _onStickerLongPress(item.url),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.transparent,
            ),
            child: Center(
              child: _buildStickerWidget(item.url, size: 52),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customPacksAsync =
        ref.watch(customStickerPacksProvider(widget.currentUid));
    final customPacks = customPacksAsync.valueOrNull ?? [];

    // Search results
    if (_searchQuery.isNotEmpty) {
      final results = searchStickers(_searchQuery);
      final items =
          results.map((s) => _StickerItem(url: s.url, packId: s.packId)).toList();
      return _buildPickerShell(
        child: _buildStickerGrid(items),
        customPacks: customPacks,
        showSearch: true,
      );
    }

    return _buildPickerShell(
      customPacks: customPacks,
      showSearch: true,
      child: _loaded
          ? TabBarView(
              controller: _tabController,
              children: [
                // Recent tab
                _buildStickerGrid(
                  _recentStickers
                      .map((url) => _StickerItem(url: url, packId: null))
                      .toList(),
                ),
                // Favorites tab
                _buildStickerGrid(
                  _favoriteStickers
                      .map((url) => _StickerItem(url: url, packId: null))
                      .toList(),
                ),
                // Built-in pack tabs
                ...kBuiltInStickerPacks.map(
                  (pack) => _buildStickerGrid(
                    pack.stickers
                        .map((s) =>
                            _StickerItem(url: s.url, packId: s.packId))
                        .toList(),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildPickerShell({
    required Widget child,
    required List<CustomStickerPack> customPacks,
    bool showSearch = false,
  }) {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Search bar
          if (showSearch)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search stickers...',
                    hintStyle:
                        TextStyle(color: context.textMuted, fontSize: 13),
                    prefixIcon: Icon(Icons.search,
                        size: 18, color: context.textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Icon(Icons.close,
                                size: 16, color: context.textSecondary),
                          )
                        : null,
                    filled: true,
                    fillColor: context.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    isDense: true,
                  ),
                ),
              ),
            ),

          // Sticker content area
          Expanded(child: child),

          // Tab bar (bottom, like Telegram)
          if (_searchQuery.isEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.borderColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // Tab icons (scrollable)
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorColor: const Color(0xFFB05ECC),
                        indicatorSize: TabBarIndicatorSize.label,
                        indicatorWeight: 2.5,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        dividerColor: Colors.transparent,
                        tabs: [
                          // Recent
                          Tab(
                            child: Icon(Icons.access_time,
                                size: 22, color: context.textSecondary),
                          ),
                          // Favorites
                          Tab(
                            child: Icon(Icons.star_outline,
                                size: 22, color: context.textSecondary),
                          ),
                          // Built-in packs
                          ...kBuiltInStickerPacks.map(
                            (pack) => Tab(
                              child: Text(pack.icon,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),


                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Internal model for flattened sticker items in grids.
class _StickerItem {
  final String url;
  final String? packId;
  const _StickerItem({required this.url, this.packId});
}
