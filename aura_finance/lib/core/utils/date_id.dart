import 'package:intl/intl.dart';

abstract final class DateId {
  static final _day = DateFormat('EEEE, d MMM', 'id_ID');
  static final _short = DateFormat('d MMM yyyy', 'id_ID');
  static final _time = DateFormat('HH:mm', 'id_ID');
  static final _month = DateFormat('MMMM yyyy', 'id_ID');
  static final _weekday = DateFormat('E', 'id_ID');

  static String dayLong(DateTime d) => _day.format(d);
  static String short(DateTime d) => _short.format(d);
  static String time(DateTime d) => _time.format(d);
  static String month(DateTime d) => _month.format(d);
  static String weekdayShort(DateTime d) => _weekday.format(d).substring(0, 3);

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
  static DateTime nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1);

  /// "Hari ini", "Kemarin", atau tanggal.
  static String relativeDay(DateTime d, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final diff = today.difference(dateOnly(d)).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    if (diff < 7 && diff > 0) return DateFormat('EEEE', 'id_ID').format(d);
    return short(d);
  }

  static String greeting({DateTime? now}) {
    final h = (now ?? DateTime.now()).hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 18) return 'Selamat sore';
    return 'Selamat malam';
  }
}
