import 'package:drift/drift.dart';

import '../../core/icons/category_icons.dart';
import 'database.dart';

List<CategoriesCompanion> defaultCategories() {
  const expense = [
    ('food', 'Makan & Minum', 'food'),
    ('coffee', 'Kopi & Jajan', 'coffee'),
    ('groceries', 'Belanja Dapur', 'groceries'),
    ('transport', 'Transportasi', 'transport'),
    ('home', 'Rumah', 'home'),
    ('bills', 'Tagihan', 'bills'),
    ('internet', 'Internet & Pulsa', 'internet'),
    ('health', 'Kesehatan', 'health'),
    ('shopping', 'Belanja', 'shopping'),
    ('entertainment', 'Hiburan', 'entertainment'),
    ('subscription', 'Langganan', 'subscription'),
    ('education', 'Pendidikan', 'education'),
    ('gift', 'Hadiah & Sosial', 'gift'),
    ('other_expense', 'Lainnya', 'other'),
  ];
  const income = [
    ('salary', 'Gaji', 'salary'),
    ('freelance', 'Freelance', 'freelance'),
    ('bonus', 'Bonus', 'bonus'),
    ('investment', 'Hasil Investasi', 'investment'),
    ('receive', 'Pemberian', 'receive'),
    ('other_income', 'Lainnya', 'other'),
  ];

  var i = 0;
  CategoriesCompanion make((String, String, String) e, CategoryKind kind) {
    final order = i++;
    return CategoriesCompanion.insert(
      id: newId(),
      name: e.$2,
      kind: kind,
      icon: e.$3,
      color: categoryTones[order % categoryTones.length],
      sortOrder: Value(order),
      seedKey: Value(e.$1),
    );
  }

  return [
    for (final e in expense) make(e, CategoryKind.expense),
    for (final e in income) make(e, CategoryKind.income),
  ];
}
