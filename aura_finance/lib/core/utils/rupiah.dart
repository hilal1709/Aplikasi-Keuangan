import 'package:intl/intl.dart';

/// Semua nominal disimpan sebagai `int` rupiah — tidak pernah `double`.
abstract final class Rupiah {
  static final _full = NumberFormat.decimalPattern('id_ID');

  /// `84520000` -> `Rp 84.520.000`
  static String format(int value, {bool signed = false}) {
    final sign = value < 0 ? '-' : (signed && value > 0 ? '+' : '');
    return '${sign}Rp ${_full.format(value.abs())}';
  }

  /// `1200000` -> `Rp 1,2 jt`, `450000` -> `Rp 450 rb`
  static String compact(int value, {bool signed = false}) {
    final sign = value < 0 ? '-' : (signed && value > 0 ? '+' : '');
    final v = value.abs();
    String body;
    if (v >= 1000000000) {
      body = '${_trim(v / 1000000000)} M';
    } else if (v >= 1000000) {
      body = '${_trim(v / 1000000)} jt';
    } else if (v >= 1000) {
      body = '${_trim(v / 1000)} rb';
    } else {
      body = '$v';
    }
    return '${sign}Rp $body';
  }

  /// Hanya angka dengan pemisah ribuan, untuk keypad: `125000` -> `125.000`
  static String digits(int value) => _full.format(value);

  static String _trim(double v) {
    final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s.replaceAll('.', ',');
  }
}
