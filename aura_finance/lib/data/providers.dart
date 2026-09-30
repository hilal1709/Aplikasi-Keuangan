import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/date_id.dart';
import 'local/database.dart';

final dbProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('override di main'));
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override di main'));

// -----------------------------------------------------------------------------
// Preferensi

class HideBalance extends Notifier<bool> {
  static const _key = 'hide_balance';
  @override
  bool build() => ref.read(prefsProvider).getBool(_key) ?? false;
  void toggle() {
    state = !state;
    ref.read(prefsProvider).setBool(_key, state);
  }
}

final hideBalanceProvider = NotifierProvider<HideBalance, bool>(HideBalance.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  @override
  ThemeMode build() => ThemeMode.values[ref.read(prefsProvider).getInt(_key) ?? ThemeMode.system.index];
  void set(ThemeMode mode) {
    state = mode;
    ref.read(prefsProvider).setInt(_key, mode.index);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class DisplayName extends Notifier<String> {
  static const _key = 'display_name';
  @override
  String build() => ref.read(prefsProvider).getString(_key) ?? '';
  void set(String name) {
    state = name.trim();
    ref.read(prefsProvider).setString(_key, state);
  }
}

final displayNameProvider = NotifierProvider<DisplayName, String>(DisplayName.new);

class AvatarKey extends Notifier<String?> {
  static const _key = 'avatar_key';
  @override
  String? build() => ref.read(prefsProvider).getString(_key);
  void set(String key) {
    state = key;
    ref.read(prefsProvider).setString(_key, key);
  }
}

final avatarKeyProvider = NotifierProvider<AvatarKey, String?>(AvatarKey.new);

// -----------------------------------------------------------------------------
// Data reaktif

final walletBalancesProvider = StreamProvider<List<WalletBalance>>((ref) => ref.watch(dbProvider).watchWalletBalances());

final walletMapProvider = Provider<Map<String, WalletBalance>>((ref) {
  final list = ref.watch(walletBalancesProvider).value ?? const [];
  return {for (final w in list) w.wallet.id: w};
});

final netWorthProvider = Provider<int>((ref) {
  final list = ref.watch(walletBalancesProvider).value ?? const [];
  return list.fold(0, (sum, w) => sum + w.balance);
});

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(dbProvider).watchCategories());

final categoryMapProvider = Provider<Map<String, Category>>((ref) {
  final list = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in list) c.id: c};
});

final recentTxProvider = StreamProvider<List<TxEntry>>((ref) => ref.watch(dbProvider).watchRecentTx(limit: 6));

final monthTotalsProvider = StreamProvider.family<PeriodTotals, DateTime>((ref, month) {
  return ref.watch(dbProvider).watchTotals(DateId.monthStart(month), DateId.nextMonthStart(month));
});

final membersProvider = StreamProvider<List<Member>>((ref) => ref.watch(dbProvider).watchMembers());

final goalsProvider = StreamProvider<List<(Goal, int)>>((ref) => ref.watch(dbProvider).watchGoalsWithSaved());

final billsProvider = StreamProvider<List<Bill>>((ref) => ref.watch(dbProvider).watchBills());

final recurringProvider = StreamProvider<List<RecurringRule>>((ref) => ref.watch(dbProvider).watchRecurring());

final budgetsProvider = StreamProvider.family<List<Budget>, DateTime>((ref, month) {
  return ref.watch(dbProvider).watchBudgets(DateId.monthStart(month));
});

final spendByCategoryProvider = StreamProvider.family<List<CategorySpend>, (DateTime, DateTime)>((ref, range) {
  return ref.watch(dbProvider).watchSpendByCategory(range.$1, range.$2);
});

final dailyFlowProvider = StreamProvider.family<List<DayFlow>, (DateTime, DateTime)>((ref, range) {
  return ref.watch(dbProvider).watchDailyFlow(range.$1, range.$2);
});

// -----------------------------------------------------------------------------
// Identitas & rumah tangga

class HouseholdId extends Notifier<String?> {
  static const _key = 'household_id';
  @override
  String? build() => ref.read(prefsProvider).getString(_key);
  Future<void> set(String? id) async {
    state = id;
    if (id == null) {
      await ref.read(prefsProvider).remove(_key);
    } else {
      await ref.read(prefsProvider).setString(_key, id);
    }
  }
}

final householdIdProvider = NotifierProvider<HouseholdId, String?>(HouseholdId.new);
