import 'package:intl/intl.dart';

/// Philippine Peso formatting helpers shared by the billing screens.
class Currency {
  Currency._();

  static final NumberFormat _peso = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '\u20B1', // ₱
    decimalDigits: 2,
  );

  /// `₱1,250.00`
  static String peso(num amount) => _peso.format(amount);
}
