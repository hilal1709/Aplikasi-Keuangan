import 'package:home_widget/home_widget.dart';

import '../core/utils/date_id.dart';
import '../core/utils/rupiah.dart';
import '../data/local/database.dart';

/// Mengirim ringkasan ke widget layar utama Android (AuraWidgetProvider).
abstract final class HomeWidgetSync {
  static Future<void> push(AppDatabase db) async {
    final now = DateTime.now();
    final today = DateId.dateOnly(now);
    final t = await db.watchTotals(today, today.add(const Duration(days: 1))).first;
    final m = await db.watchTotals(DateId.monthStart(now), DateId.nextMonthStart(now)).first;
    await HomeWidget.saveWidgetData<String>('today_expense', Rupiah.format(t.expense));
    await HomeWidget.saveWidgetData<String>('month_expense', 'Bulan ini ${Rupiah.compact(m.expense)}');
    await HomeWidget.updateWidget(androidName: 'AuraWidgetProvider');
  }
}
