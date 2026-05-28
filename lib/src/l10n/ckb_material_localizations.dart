import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Localization delegates for Kurdish Sorani (`ckb`).
///
/// Flutter's `flutter_localizations` package ships built-in Material,
/// Cupertino and Widgets localizations for ~80 locales, but Kurdish
/// Sorani is not among them. Without a delegate that *claims* `ckb`,
/// framework widgets (date pickers, dialogs, the `Directionality`
/// that `WidgetsLocalizations` provides, tooltip semantics, etc.)
/// would throw "No <Foo>Localizations found".
///
/// Kurdish Sorani is written in Arabic script and is right-to-left,
/// so the safest, zero-maintenance approach is to reuse Flutter's
/// Arabic (`ar`) localizations for every `ckb` request. The user-
/// facing app text still comes from our own `strings_ckb.dart`; only
/// the framework-level chrome (e.g. the word "Cancel" inside a stock
/// date picker) falls back to Arabic — acceptable and rarely seen.

const Locale _kArabic = Locale('ar');

/// Material-widget localizations for `ckb`, backed by Arabic.
class CkbMaterialLocalizations {
  const CkbMaterialLocalizations._();

  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _CkbMaterialLocalizationsDelegate();
}

class _CkbMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _CkbMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ckb';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    return GlobalMaterialLocalizations.delegate.load(_kArabic);
  }

  @override
  bool shouldReload(_CkbMaterialLocalizationsDelegate old) => false;
}

/// Cupertino-widget localizations for `ckb`, backed by Arabic.
class CkbCupertinoLocalizations {
  const CkbCupertinoLocalizations._();

  static const LocalizationsDelegate<CupertinoLocalizations> delegate =
      _CkbCupertinoLocalizationsDelegate();
}

class _CkbCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CkbCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ckb';

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    return GlobalCupertinoLocalizations.delegate.load(_kArabic);
  }

  @override
  bool shouldReload(_CkbCupertinoLocalizationsDelegate old) => false;
}

/// Widgets-layer localizations for `ckb`. This is what supplies the
/// ambient [TextDirection] (RTL) to the whole subtree.
class CkbWidgetsLocalizations {
  const CkbWidgetsLocalizations._();

  static const LocalizationsDelegate<WidgetsLocalizations> delegate =
      _CkbWidgetsLocalizationsDelegate();
}

class _CkbWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _CkbWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ckb';

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    return GlobalWidgetsLocalizations.delegate.load(_kArabic);
  }

  @override
  bool shouldReload(_CkbWidgetsLocalizationsDelegate old) => false;
}
