import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/date_id.dart';
import 'local/database.dart';
import 'remote/neon.dart';

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

// -----------------------------------------------------------------------------
// Cakupan tampilan: Semua / Bersama / Pribadiku (hanya berarti saat punya rumah tangga)

enum ViewScope { all, shared, mine }

class ViewScopeNotifier extends Notifier<ViewScope> {
  static const _key = 'view_scope';
  @override
  ViewScope build() {
    if (ref.watch(householdIdProvider) == null) return ViewScope.all;
    return ViewScope.values.elementAtOrNull(ref.read(prefsProvider).getInt(_key) ?? 0) ?? ViewScope.all;
  }

  void set(ViewScope v) {
    state = v;
    ref.read(prefsProvider).setInt(_key, v.index);
  }
}

final viewScopeProvider = NotifierProvider<ViewScopeNotifier, ViewScope>(ViewScopeNotifier.new);

final allWalletsProvider = StreamProvider<List<Wallet>>((ref) => ref.watch(dbProvider).watchAllWallets());

/// Dompet pribadi milikku (dompet pribadi pasangan memang tidak pernah sampai ke HP ini).
bool isMyPrivateWallet(Wallet w) => !w.isShared && (w.createdBy == null || w.createdBy == Neon.auth.currentUser?.id);

/// Himpunan dompet untuk suatu cakupan. `all` tetap dibatasi ke dompet yang ada,
/// supaya transaksi yang dompetnya tidak terlihat tidak ikut terhitung.
final walletIdsForScopeProvider = Provider.family<Set<String>, ViewScope>((ref, scope) {
  final list = ref.watch(allWalletsProvider).value ?? const <Wallet>[];
  return {
    for (final w in list)
      if (switch (scope) { ViewScope.all => true, ViewScope.shared => w.isShared, ViewScope.mine => isMyPrivateWallet(w) }) w.id,
  };
});

final scopedWalletIdsProvider = Provider<Set<String>>((ref) => ref.watch(walletIdsForScopeProvider(ref.watch(viewScopeProvider))));

/// Semua dompet aktif beserta saldo (untuk formulir & halaman Dompet; tidak terpengaruh cakupan).
final walletBalancesProvider = StreamProvider<List<WalletBalance>>((ref) => ref.watch(dbProvider).watchWalletBalances());

final walletMapProvider = Provider<Map<String, WalletBalance>>((ref) {
  final list = ref.watch(walletBalancesProvider).value ?? const [];
  return {for (final w in list) w.wallet.id: w};
});

/// Total saldo seluruh dompet yang terlihat.
final totalBalanceProvider = Provider<int>((ref) {
  final list = ref.watch(walletBalancesProvider).value ?? const [];
  return list.fold(0, (sum, w) => sum + w.balance);
});

/// Dompet & total saldo sesuai cakupan tampilan (Beranda, Insight).
final scopedWalletBalancesProvider = Provider<List<WalletBalance>>((ref) {
  final ids = ref.watch(scopedWalletIdsProvider);
  return (ref.watch(walletBalancesProvider).value ?? const <WalletBalance>[]).where((w) => ids.contains(w.wallet.id)).toList();
});

final netWorthProvider = Provider<int>((ref) => ref.watch(scopedWalletBalancesProvider).fold(0, (sum, w) => sum + w.balance));

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(dbProvider).watchCategories());

final categoryMapProvider = Provider<Map<String, Category>>((ref) {
  final list = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in list) c.id: c};
});

final recentTxProvider = StreamProvider<List<TxEntry>>(
  (ref) => ref.watch(dbProvider).watchRecentTx(limit: 6, walletIds: ref.watch(scopedWalletIdsProvider)),
);

final monthTotalsProvider = StreamProvider.family<PeriodTotals, DateTime>((ref, month) {
  return ref
      .watch(dbProvider)
      .watchTotals(DateId.monthStart(month), DateId.nextMonthStart(month), walletIds: ref.watch(scopedWalletIdsProvider));
});

final membersProvider = StreamProvider<List<Member>>((ref) => ref.watch(dbProvider).watchMembers());

final goalsProvider = StreamProvider<List<(Goal, int)>>((ref) => ref.watch(dbProvider).watchGoalsWithSaved());

final billsProvider = StreamProvider<List<Bill>>((ref) => ref.watch(dbProvider).watchBills());

final recurringProvider = StreamProvider<List<RecurringRule>>((ref) => ref.watch(dbProvider).watchRecurring());

final budgetsProvider = StreamProvider.family<List<Budget>, DateTime>((ref, month) {
  return ref.watch(dbProvider).watchBudgets(DateId.monthStart(month));
});

/// Pengeluaran per kategori untuk cakupan tertentu (dipakai budget bersama/pribadi).
final spendForScopeProvider = StreamProvider.family<List<CategorySpend>, (DateTime, DateTime, ViewScope)>((ref, k) {
  return ref.watch(dbProvider).watchSpendByCategory(k.$1, k.$2, walletIds: ref.watch(walletIdsForScopeProvider(k.$3)));
});

final spendByCategoryProvider = StreamProvider.family<List<CategorySpend>, (DateTime, DateTime)>((ref, range) {
  return ref.watch(dbProvider).watchSpendByCategory(range.$1, range.$2, walletIds: ref.watch(scopedWalletIdsProvider));
});

final dailyFlowProvider = StreamProvider.family<List<DayFlow>, (DateTime, DateTime)>((ref, range) {
  return ref.watch(dbProvider).watchDailyFlow(range.$1, range.$2, walletIds: ref.watch(scopedWalletIdsProvider));
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
