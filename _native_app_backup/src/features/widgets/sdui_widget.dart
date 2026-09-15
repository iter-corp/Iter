import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_client.dart';

class SduiWidget extends StatefulWidget {
  final String screenId;
  final Widget? fallback;

  const SduiWidget({
    super.key,
    required this.screenId,
    this.fallback,
  });

  @override
  State<SduiWidget> createState() => _SduiWidgetState();
}

class _SduiWidgetState extends State<SduiWidget> {
  Map<String, dynamic>? _screenData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchLayout();
  }

  Future<void> _fetchLayout() async {
    try {
      final res = await ApiClient.instance.get('/dynamic/screens/${widget.screenId}');
      if (mounted) {
        setState(() {
          _screenData = res is Map<String, dynamic> ? res : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _screenData == null || _screenData!['active'] != true) {
      return widget.fallback ?? const SizedBox.shrink();
    }

    final layout = _screenData!['layout'] as Map<String, dynamic>?;
    final blocks = (layout?['blocks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (blocks.isEmpty) return widget.fallback ?? const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: blocks.map((b) => _buildBlock(context, b)).toList(),
    );
  }

  Widget _buildBlock(BuildContext context, Map<String, dynamic> block) {
    final type = block['type'] as String? ?? 'card';
    final title = block['title'] as String? ?? '';
    final subtitle = block['subtitle'] as String? ?? '';
    final bgHex = block['backgroundColor'] as String?;
    final textHex = block['textColor'] as String?;
    final action = block['action'] as Map<String, dynamic>?;

    final bgColor = bgHex != null ? _parseColor(bgHex) : Theme.of(context).cardColor;
    final textColor = textHex != null ? _parseColor(textHex) : null;

    final isBanner = type == 'banner';
    final radius = BorderRadius.circular(isBanner ? 8 : 16);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isBanner ? 12 : 16, vertical: isBanner ? 4 : 8),
      child: Material(
        color: bgColor,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => _handleAction(context, action),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: textColor?.withOpacity(0.8) ?? Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null)
                  Icon(Icons.arrow_forward_ios, size: 14, color: textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, Map<String, dynamic>? action) {
    if (action == null) return;
    final actionType = action['type'] as String?;
    final target = action['target'] as String?;

    if (actionType == 'open_url' && target != null) {
      final uri = Uri.tryParse(target);
      if (uri != null) launchUrl(uri);
    }
  }

  Color _parseColor(String hex) {
    var clean = hex.replaceAll('#', '');
    if (clean.length == 6) clean = 'FF$clean';
    return Color(int.parse(clean, radix: 16));
  }
}
