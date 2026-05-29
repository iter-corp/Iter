import 'package:flutter/widgets.dart';

// Picks a paragraph direction from the first strong-directional codepoint.
// Neutral-only text falls back to LTR so trailing emoji remain after Latin text.
TextDirection detectTextDirection(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x05FF) || // Hebrew
        (r >= 0x0600 && r <= 0x06FF) || // Arabic
        (r >= 0x0700 && r <= 0x074F) || // Syriac
        (r >= 0x0750 && r <= 0x077F) || // Arabic Supplement
        (r >= 0x0780 && r <= 0x07BF) || // Thaana
        (r >= 0x07C0 && r <= 0x07FF) || // NKo
        (r >= 0x08A0 && r <= 0x08FF) || // Arabic Extended-A
        (r >= 0xFB1D && r <= 0xFDFF) || // Hebrew + Arabic Presentation Forms-A
        (r >= 0xFE70 && r <= 0xFEFF)) {
      // Arabic Presentation Forms-B
      return TextDirection.rtl;
    }
  }
  return TextDirection.ltr;
}
