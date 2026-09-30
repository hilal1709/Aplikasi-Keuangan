import 'package:drift/drift.dart';

/// Kolom yang dimiliki setiap entitas yang disinkronkan ke Neon (Postgres).
/// `id` dibuat di perangkat (UUID) supaya bisa mencatat saat offline.
/// `dirty` = baris berubah secara lokal dan belum terkirim (outbox).
mixin Syncable on Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

enum WalletKind { cash, bank, ewallet, other }

enum TxKind { income, expense, transfer }

enum CategoryKind { income, expense }

enum Frequency { daily, weekly, monthly, yearly }

class Wallets extends Table with Syncable {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<WalletKind>()();
  IntColumn get initialBalance => integer().withDefault(const Constant(0))();
  IntColumn get color => integer()();
  BoolColumn get isShared => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Categories extends Table with Syncable {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<CategoryKind>()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// Penanda kategori bawaan, dipakai untuk menggabungkan duplikat saat
  /// bergabung ke rumah tangga yang sudah punya kategori sama.
  TextColumn get seedKey => text().nullable()();
}

@DataClassName('TxEntry')
class TxEntries extends Table with Syncable {
  TextColumn get kind => textEnum<TxKind>()();
  IntColumn get amount => integer()();
  TextColumn get walletId => text()();
  TextColumn get toWalletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get recurringRuleId => text().nullable()();
  TextColumn get billId => text().nullable()();
}

class Budgets extends Table with Syncable {
  TextColumn get categoryId => text()();

  /// Awal bulan (tanggal 1, 00:00).
  DateTimeColumn get month => dateTime()();
  IntColumn get limitAmount => integer()();
}

class Goals extends Table with Syncable {
  TextColumn get name => text()();
  IntColumn get target => integer()();
  DateTimeColumn get deadline => dateTime().nullable()();

  /// Kunci ilustrasi clay (travel, shield, home, gadget, study, gift).
  TextColumn get illustration => text()();
  IntColumn get color => integer()();
  DateTimeColumn get achievedAt => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class GoalContributions extends Table with Syncable {
  TextColumn get goalId => text()();

  /// Positif = setor, negatif = tarik.
  IntColumn get amount => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get occurredAt => dateTime()();
}

class RecurringRules extends Table with Syncable {
  TextColumn get kind => textEnum<TxKind>()();
  IntColumn get amount => integer()();
  TextColumn get walletId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get frequency => textEnum<Frequency>()();
  DateTimeColumn get nextRun => dateTime()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class Bills extends Table with Syncable {
  TextColumn get name => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get dueDate => dateTime()();
  IntColumn get remindDaysBefore => integer().withDefault(const Constant(3))();
  BoolColumn get repeatMonthly => boolean().withDefault(const Constant(true))();
  TextColumn get walletId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  DateTimeColumn get paidAt => dateTime().nullable()();
}

/// Cache lokal anggota rumah tangga (dikelola server, hanya ditarik).
class Members extends Table {
  TextColumn get userId => text()();
  TextColumn get householdId => text()();
  TextColumn get displayName => text()();
  TextColumn get role => text()();
  IntColumn get color => integer().withDefault(const Constant(0xFFFE64A3))();
  TextColumn get avatar => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, householdId};
}
