import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// App-wide responsive helpers.
///
/// All widgets should size against [BuildContext] extensions defined here
/// rather than hard-coding pixel values. Targets ≥360dp width on Android and
/// ≥320pt width on iOS (iPhone SE 1st gen) without overflow.
class Breakpoints {
  static const double xs = 320; // iPhone SE 1st gen
  static const double sm = 360; // typical Android
  static const double md = 411; // Pixel-class
  static const double lg = 600; // small tablet / foldable inner
  static const double xl = 840; // tablet landscape
}

extension ResponsiveContext on BuildContext {
  Size get _size => MediaQuery.sizeOf(this);
  double get screenWidth => _size.width;
  double get screenHeight => _size.height;

  /// True for phones below ~360dp (iPhone SE, small Android).
  bool get isXSmall => screenWidth < Breakpoints.sm;

  /// True for compact phones (≤411dp) — most Android phones in portrait.
  bool get isCompact => screenWidth < Breakpoints.md;

  /// True for tablet-class widths (≥600dp).
  bool get isTablet => screenWidth >= Breakpoints.lg;

  /// Linear interpolation between two values based on screen width, clamped
  /// to the [Breakpoints.xs] → [Breakpoints.lg] range.
  ///
  /// `compact` is the value at 320dp, `expanded` is the value at 600dp.
  double scaleW(double compact, double expanded) {
    final w = screenWidth.clamp(Breakpoints.xs, Breakpoints.lg);
    final t = (w - Breakpoints.xs) / (Breakpoints.lg - Breakpoints.xs);
    return compact + (expanded - compact) * t;
  }

  /// Pick a value based on width buckets.
  T responsive<T>({required T compact, T? medium, required T expanded}) {
    if (screenWidth >= Breakpoints.lg) return expanded;
    if (screenWidth >= Breakpoints.md) return medium ?? expanded;
    return compact;
  }

  /// Clamped text scaler: respects user accessibility prefs but caps the
  /// upper bound so layouts don't break at 1.5x+ font scale.
  TextScaler get safeTextScaler {
    final raw = MediaQuery.textScalerOf(this);
    return raw.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25);
  }

  /// Standard horizontal screen padding — shrinks on narrow phones.
  EdgeInsets get screenPadding => EdgeInsets.symmetric(
        horizontal: scaleW(12, 20),
      );

  /// Bottom padding accounting for the iOS home indicator / Android nav bar.
  double get bottomSafeInset => MediaQuery.viewPaddingOf(this).bottom;

  /// Top padding accounting for status bar / iOS notch / Dynamic Island.
  double get topSafeInset => MediaQuery.viewPaddingOf(this).top;
}

/// Wraps [child] with a [MediaQuery] that clamps text scaling and applies
/// safe defaults. Use as the `MaterialApp.builder` to make every screen
/// inherit consistent sizing on both Android and iOS.
class ResponsiveBootstrap extends StatelessWidget {
  final Widget child;
  const ResponsiveBootstrap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: mq.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.25,
        ),
      ),
      child: child,
    );
  }
}

/// A drop-in replacement for [Text] that fades on overflow, hard-clamps font
/// scale, and shrinks slightly on narrow screens.
///
/// Use for chip / tab / button / card-header labels where wrapping is not
/// acceptable but accessibility scaling must still be respected.
class FitText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int maxLines;
  final double minFontSize;

  const FitText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines = 1,
    this.minFontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return Text(
            data,
            style: base,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            softWrap: maxLines > 1,
          );
        }
        final scaler = MediaQuery.textScalerOf(context);
        final fitted = _fit(
          data,
          base,
          constraints.maxWidth,
          scaler,
          maxLines,
          minFontSize,
        );
        return Text(
          data,
          style: base.copyWith(fontSize: fitted),
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          softWrap: maxLines > 1,
        );
      },
    );
  }

  static double _fit(
    String text,
    TextStyle style,
    double maxWidth,
    TextScaler scaler,
    int maxLines,
    double minFontSize,
  ) {
    final start = style.fontSize ?? 14.0;
    var size = start;
    while (size > minFontSize) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
        textDirection: ui.TextDirection.ltr,
        textScaler: scaler,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      final fits = !tp.didExceedMaxLines && tp.width <= maxWidth + 0.5;
      tp.dispose();
      if (fits) return size;
      size = math.max(minFontSize, size - 0.5);
    }
    return minFontSize;
  }
}
