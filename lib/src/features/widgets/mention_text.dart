import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../navigation/user_profile_nav.dart';
import '../../services/user_service.dart';
import '../../utils/mention_utils.dart';

class MentionText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? mentionStyle;
  final InlineSpan? prefixSpan;
  final TextDirection? textDirection;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final StrutStyle? strutStyle;

  const MentionText({
    Key? key,
    required this.text,
    this.style,
    this.mentionStyle,
    this.prefixSpan,
    this.textDirection,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.strutStyle,
  }) : super(key: key);

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  List<InlineSpan> _spans = [];
  final List<TapGestureRecognizer> _recognizers = [];
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    _buildSpans();
  }

  @override
  void didUpdateWidget(MentionText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.mentionStyle != widget.mentionStyle) {
      _buildSpans();
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _buildSpans() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    _spans = [];
    if (widget.prefixSpan != null) {
      _spans.add(widget.prefixSpan!);
    }
    final text = widget.text;
    if (text.isEmpty) return;

    // Use default text style from theme if not provided
    final baseStyle = widget.style;
    final mentionStyle = widget.mentionStyle ??
        (baseStyle != null
            ? baseStyle.copyWith(color: Colors.blue, fontWeight: FontWeight.bold)
            : const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold));

    final matches = MentionUtils.mentionRegex.allMatches(text);
    int lastMatchEnd = 0;

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        _spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      final mentionText = match.group(0)!;
      final username = match.group(1)!;

      final recognizer = TapGestureRecognizer()
        ..onTap = () => _handleMentionTap(username);
      _recognizers.add(recognizer);

      _spans.add(TextSpan(
        text: mentionText,
        style: mentionStyle,
        recognizer: recognizer,
      ));

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      _spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }
  }

  Future<void> _handleMentionTap(String username) async {
    try {
      final uids = await _userService.getUidsByUsernames([username]);
      final uid = uids[username.toLowerCase()];
      if (uid != null && mounted) {
        openUserProfile(context, uid: uid);
      } else {
        debugPrint('[MentionText] User $username not found');
      }
    } catch (e) {
      debugPrint('[MentionText] Error resolving username $username: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _spans, style: widget.style),
      textDirection: widget.textDirection,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      strutStyle: widget.strutStyle,
    );
  }
}
