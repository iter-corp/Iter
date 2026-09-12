import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Standard screen size categories across the entire application.
enum AppScreenSize {
  /// Mobile phones (portrait or narrow landscape) with width < 600dp.
  compact,

  /// Tablets, foldable displays, and medium viewports with 600dp <= width < 1024dp.
  medium,

  /// Desktop monitors, large tablets (landscape), and wide web displays with width >= 1024dp.
  expanded;

  bool get isCompact => this == AppScreenSize.compact;
  bool get isMedium => this == AppScreenSize.medium;
  bool get isExpanded => this == AppScreenSize.expanded;

  /// Semantic aliases for standard device terminology:
  bool get isMobile => isCompact;
  bool get isTablet => isMedium;
  bool get isDesktop => isExpanded;
}

/// Canonical responsive breakpoints across the app.
class Breakpoints {
  // Primary size boundaries:
  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  // Granular breakpoints for fine-tuned scaling:
  static const double xs = 320; // Small phones (e.g. iPhone SE 1st gen)
  static const double sm = 360; // Standard Android compact
  static const double md = 414; // Large modern phones (Pro Max / Plus / Ultra)
  static const double lg = 600; // Foldables / tablets (iPad Mini portrait)
  static const double xl = 1024; // Standard desktop / large tablets
  static const double xxl = 1440; // Wide screens / large desktop

  /// Maps a viewport width directly to an [AppScreenSize].
  static AppScreenSize fromWidth(double width) {
    if (width < mobileMax) return AppScreenSize.compact;
    if (width < tabletMax) return AppScreenSize.medium;
    return AppScreenSize.expanded;
  }
}

/// Holds responsive context data passed down through the widget tree.
class ResponsiveData {
  final AppScreenSize screenSize;
  final Size windowSize;
  final Size contentSize;
  final bool isFramed;

  const ResponsiveData({
    required this.screenSize,
    required this.windowSize,
    required this.contentSize,
    required this.isFramed,
  });

  bool get isMobile => screenSize.isMobile;
  bool get isTablet => screenSize.isTablet;
  bool get isDesktop => screenSize.isDesktop;
}

/// InheritedWidget providing [ResponsiveData] to the entire subtree.
class ResponsiveScope extends InheritedWidget {
  final ResponsiveData data;

  const ResponsiveScope({
    super.key,
    required this.data,
    required super.child,
  });

  static ResponsiveData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ResponsiveScope>()?.data;
  }

  static ResponsiveData of(BuildContext context) {
    final result = maybeOf(context);
    assert(result != null, 'No ResponsiveScope found in context. Wrap the app with ResponsiveBootstrap.');
    return result!;
  }

  @override
  bool updateShouldNotify(ResponsiveScope oldWidget) {
    return data.screenSize != oldWidget.data.screenSize ||
        data.windowSize != oldWidget.data.windowSize ||
        data.contentSize != oldWidget.data.contentSize ||
        data.isFramed != oldWidget.data.isFramed;
  }
}

/// App-wide responsive helpers on [BuildContext].
///
/// All widgets can size against [BuildContext] extensions defined here
/// rather than hard-coding pixel values.
extension ResponsiveContext on BuildContext {
  /// The current screen size class (compact / medium / expanded).
  AppScreenSize get screenSize {
    final scoped = ResponsiveScope.maybeOf(this);
    if (scoped != null) return scoped.screenSize;
    return Breakpoints.fromWidth(MediaQuery.sizeOf(this).width);
  }

  /// True for mobile phones (< 600dp).
  bool get isMobile => screenSize.isMobile;

  /// True for tablets (600dp - 1024dp).
  bool get isTablet => screenSize.isTablet;

  /// True for desktop and wide web screens (>= 1024dp).
  bool get isDesktop => screenSize.isDesktop;

  /// Semantic size class aliases:
  bool get isCompact => screenSize.isCompact;
  bool get isMedium => screenSize.isMedium;
  bool get isExpanded => screenSize.isExpanded;

  /// Effective content dimensions inside the active responsive viewport.
  Size get _size => MediaQuery.sizeOf(this);
  double get screenWidth => _size.width;
  double get screenHeight => _size.height;

  /// Physical device window dimensions (from ResponsiveScope).
  Size get deviceSize {
    final scoped = ResponsiveScope.maybeOf(this);
    return scoped?.windowSize ?? _size;
  }

  double get deviceWidth => deviceSize.width;
  double get deviceHeight => deviceSize.height;

  /// True for phones below ~360dp (iPhone SE, small Android).
  bool get isXSmall => screenWidth < Breakpoints.sm;

  /// Resolve a value based on the current screen size.
  ///
  /// Priority:
  /// - On [AppScreenSize.expanded]: `desktop` ?? `tablet` ?? `mobile`
  /// - On [AppScreenSize.medium]: `tablet` ?? `mobile`
  /// - On [AppScreenSize.compact]: `mobile`
  T responsive<T>({
    required T mobile,
    T? tablet,
    T? desktop,
    // Backwards compatibility for existing code using compact/medium/expanded:
    T? compact,
    T? medium,
    T? expanded,
  }) {
    final effectiveMobile = compact ?? mobile;
    final effectiveTablet = tablet ?? medium;
    final effectiveDesktop = desktop ?? expanded;

    switch (screenSize) {
      case AppScreenSize.expanded:
        return effectiveDesktop ?? effectiveTablet ?? effectiveMobile;
      case AppScreenSize.medium:
        return effectiveTablet ?? effectiveMobile;
      case AppScreenSize.compact:
        return effectiveMobile;
    }
  }

  /// Linear interpolation between two values based on screen width, clamped
  /// to the [Breakpoints.xs] → [Breakpoints.lg] range.
  ///
  /// `compact` is the value at 320dp, `expanded` is the value at 600dp.
  double scaleW(double compact, double expanded, {double minW = Breakpoints.xs, double maxW = Breakpoints.lg}) {
    final w = screenWidth.clamp(minW, maxW);
    final t = (w - minW) / (maxW - minW);
    return compact + (expanded - compact) * t;
  }

  /// Clamped text scaler: respects user accessibility prefs but caps the
  /// upper bound so layouts don't break at 1.5x+ font scale.
  TextScaler get safeTextScaler {
    final raw = MediaQuery.textScalerOf(this);
    return raw.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25);
  }

  /// Standard horizontal screen padding — adapts based on screen size.
  EdgeInsets get screenPadding => EdgeInsets.symmetric(
        horizontal: responsive<double>(
          mobile: scaleW(12, 20),
          tablet: 24,
          desktop: 32,
        ),
      );

  /// Standard max content width for centering readable layouts:
  /// - Mobile: unbounded (double.infinity)
  /// - Tablet: 720dp
  /// - Desktop: 680dp (feed column)
  double get maxContentWidth => responsive<double>(
        mobile: double.infinity,
        tablet: 720.0,
        desktop: 680.0,
      );

  /// Bottom padding accounting for the iOS home indicator / Android nav bar.
  double get bottomSafeInset => MediaQuery.viewPaddingOf(this).bottom;

  /// Top padding accounting for status bar / iOS notch / Dynamic Island.
  double get topSafeInset => MediaQuery.viewPaddingOf(this).top;
}

/// The Universal Responsive Bootstrap.
///
/// Wraps the entire application in `MaterialApp.builder`.
/// Guarantees that EVERY screen, dialog, sheet, and overlay automatically:
/// 1. Runs with safe text scaling limits.
/// 2. Scales smoothly on mobile (100% full width).
/// 3. Expands to a multi-column social web layout on desktop up to 1440dp.
/// 4. Injects [ResponsiveScope] for unified screen size detection across all pages.
class ResponsiveBootstrap extends StatelessWidget {
  final Widget child;

  /// Custom max content width for tablets. Defaults to 900dp.
  final double tabletMaxWidth;

  /// Custom max content width for desktop. Defaults to 1440dp.
  final double desktopMaxWidth;

  const ResponsiveBootstrap({
    super.key,
    required this.child,
    this.tabletMaxWidth = 900.0,
    this.desktopMaxWidth = 1440.0,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final windowSize = mq.size;
    final screenSize = Breakpoints.fromWidth(windowSize.width);

    // Calculate effective width per screen size
    final double effectiveWidth;
    final bool isFramed;

    switch (screenSize) {
      case AppScreenSize.compact:
        effectiveWidth = windowSize.width;
        isFramed = false;
        break;
      case AppScreenSize.medium:
        effectiveWidth = windowSize.width;
        isFramed = false;
        break;
      case AppScreenSize.expanded:
        effectiveWidth = math.min(windowSize.width, desktopMaxWidth);
        isFramed = windowSize.width > desktopMaxWidth;
        break;
    }

    final effectiveContentSize = Size(effectiveWidth, windowSize.height);

    final effectiveMq = mq.copyWith(
      size: effectiveContentSize,
      textScaler: mq.textScaler.clamp(
        minScaleFactor: 0.85,
        maxScaleFactor: 1.25,
      ),
    );

    final responsiveData = ResponsiveData(
      screenSize: screenSize,
      windowSize: windowSize,
      contentSize: effectiveContentSize,
      isFramed: isFramed,
    );

    final innerChild = ResponsiveScope(
      data: responsiveData,
      child: MediaQuery(
        data: effectiveMq,
        child: child,
      ),
    );

    // Mobile / Unframed: render full-width edge-to-edge
    if (!isFramed) {
      return innerChild;
    }

    // Tablet & Desktop framed container: centered responsive frame with ambient background
    return Material(
      color: isDark ? const Color(0xFF07090E) : const Color(0xFFE9ECF2),
      child: Center(
        child: Container(
          width: effectiveWidth,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 0),
              ),
            ],
            border: Border.symmetric(
              vertical: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
            ),
          ),
          child: ClipRect(
            child: innerChild,
          ),
        ),
      ),
    );
  }
}

/// A responsive widget switcher that renders different widgets
/// according to screen size: [mobile], [tablet], [desktop].
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return context.responsive<Widget>(
      mobile: mobile,
      tablet: tablet ?? mobile,
      desktop: desktop ?? tablet ?? mobile,
    );
  }
}

/// A builder that provides [AppScreenSize] directly to child builder.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, AppScreenSize size) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return builder(context, context.screenSize);
  }
}

/// Centered container that respects [maxContentWidth] and [screenPadding].
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMax = maxWidth ?? context.maxContentWidth;
    final effectivePadding = padding ?? context.screenPadding;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: effectiveMax,
        ),
        child: Padding(
          padding: effectivePadding,
          child: child,
        ),
      ),
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
