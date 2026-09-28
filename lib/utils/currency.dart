import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Philippine Peso formatting helpers shared by the billing screens.
class Currency {
  Currency._();

  /// Bundled [NotoSans] includes Unicode ₱ (U+20B1) on all devices.
  static const String symbol = '\u20B1';
  static const String fontFamily = 'NotoSans';

  static final NumberFormat _peso = NumberFormat.currency(
    locale: 'en_PH',
    symbol: symbol,
    decimalDigits: 2,
  );

  /// Example: `₱1,250.00`
  static String peso(num amount) => _peso.format(amount);

  /// For input labels, e.g. `Amount Received (₱)`.
  static String label(String text) => '$text ($symbol)';

  /// Ensures the bundled font is used so ₱ renders on all Android devices.
  static TextStyle style(TextStyle base) => base.copyWith(
        fontFamily: fontFamily,
        fontFamilyFallback: const ['sans-serif'],
      );
}

/// Text widget that always renders amounts with the bundled ₱ glyph.
class CurrencyText extends StatelessWidget {
  final num amount;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const CurrencyText({
    super.key,
    required this.amount,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      Currency.peso(amount),
      style: Currency.style(style ?? const TextStyle()),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
