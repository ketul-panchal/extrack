import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:spent/core/database/database.dart';
import 'package:spent/core/money/money_format.dart';

/// What a backup file contains, shown before restoring it.
class BackupSummary {
  const BackupSummary({
    required this.exportedAt,
    required this.transactions,
    required this.accounts,
    required this.categories,
    required this.goals,
    required this.rules,
  });

  final DateTime? exportedAt;
  final int transactions;
  final int accounts;
  final int categories;
  final int goals;
  final int rules;
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Plain JSON backups and CSV exports. Nothing is uploaded anywhere; the
/// user decides where the file goes.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const format = 'spent-backup';
  static const version = 1;

  Future<Map<String, Object?>> export({required Map<String, Object?> settings}) async => {
    'format': format,
    'version': version,
    'exportedAt': clock.now().toUtc().toIso8601String(),
    'settings': settings,
    'accounts': [for (final r in await _db.select(_db.accounts).get()) r.toJson()],
    'categories': [for (final r in await _db.select(_db.categories).get()) r.toJson()],
    'recurring': [for (final r in await _db.select(_db.recurringRules).get()) r.toJson()],
    'txns': [for (final r in await _db.select(_db.txns).get()) r.toJson()],
    'budgets': [for (final r in await _db.select(_db.budgets).get()) r.toJson()],
    'goals': [for (final r in await _db.select(_db.goals).get()) r.toJson()],
    'goalEntries': [for (final r in await _db.select(_db.goalEntries).get()) r.toJson()],
  };

  Future<Uint8List> exportBytes({required Map<String, Object?> settings}) async =>
      Uint8List.fromList(utf8.encode(jsonEncode(await export(settings: settings))));

  /// Decodes and checks a backup file without touching the database.
  Map<String, Object?> decode(Uint8List bytes) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const BackupException('This file isn\'t a Spent backup (it isn\'t valid JSON).');
    }
    if (json is! Map<String, Object?> || json['format'] != format) {
      throw const BackupException('This file isn\'t a Spent backup.');
    }
    final v = json['version'];
    if (v is! int || v > version) {
      throw const BackupException('This backup was made by a newer version of Spent.');
    }
    return json;
  }

  BackupSummary summarize(Map<String, Object?> json) {
    int count(String key) => (json[key] as List?)?.length ?? 0;
    return BackupSummary(
      exportedAt: DateTime.tryParse(json['exportedAt'] as String? ?? '')?.toLocal(),
      transactions: count('txns'),
      accounts: count('accounts'),
      categories: count('categories'),
      goals: count('goals'),
      rules: count('recurring'),
    );
  }

  /// Replaces everything in the database with the backup, atomically.
  Future<void> restore(Map<String, Object?> json) async {
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) fromJson) {
      final list = json[key];
      if (list == null) return <T>[];
      if (list is! List) throw BackupException('The "$key" section is damaged.');
      try {
        return [for (final m in list) fromJson((m as Map).cast<String, dynamic>())];
      } on Object {
        throw BackupException('The "$key" section is damaged.');
      }
    }

    final accounts = rows('accounts', Account.fromJson);
    final categories = rows('categories', Category.fromJson);
    final recurring = rows('recurring', RecurringRule.fromJson);
    final txns = rows('txns', Txn.fromJson);
    final budgets = rows('budgets', Budget.fromJson);
    final goals = rows('goals', Goal.fromJson);
    final entries = rows('goalEntries', GoalEntry.fromJson);

    await _db.transaction(() async {
      await _db.wipe();
      await _db.batch((b) {
        b.insertAll(_db.accounts, accounts);
        b.insertAll(_db.categories, categories);
        b.insertAll(_db.recurringRules, recurring);
        b.insertAll(_db.txns, txns);
        b.insertAll(_db.budgets, budgets);
        b.insertAll(_db.goals, goals);
        b.insertAll(_db.goalEntries, entries);
      });
    });
  }

  /// All transactions as CSV (oldest first), easy to open in a spreadsheet.
  Future<Uint8List> csv(MoneyFormat money, {DateTime? from, DateTime? to}) async {
    final categories = {for (final c in await _db.select(_db.categories).get()) c.id: c};
    final accounts = {for (final a in await _db.select(_db.accounts).get()) a.id: a};
    final q = _db.select(_db.txns)
      ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]);
    if (from != null) q.where((t) => t.date.isBiggerOrEqualValue(from));
    if (to != null) q.where((t) => t.date.isSmallerThanValue(to));
    final txns = await q.get();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    String cell(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    String amount(int minor) {
      final unit = money.unit;
      final whole = minor.abs() ~/ unit;
      final frac = minor.abs() % unit;
      final text = money.decimals == 0
          ? '$whole'
          : '$whole.${frac.toString().padLeft(money.decimals, '0')}';
      return minor < 0 ? '-$text' : text;
    }

    final buffer = StringBuffer('﻿')
      ..writeln(
        [
          'Date',
          'Type',
          'Amount',
          'Currency',
          'Category',
          'Account',
          'To account',
          'Note',
        ].join(','),
      );
    for (final t in txns) {
      final signed = t.kind == TxnKind.expense ? -t.amount : t.amount;
      buffer.writeln(
        [
          dateFormat.format(t.date),
          t.kind.label,
          amount(signed),
          money.currency.code,
          categories[t.categoryId]?.name ?? '',
          accounts[t.accountId]?.name ?? '',
          accounts[t.toAccountId]?.name ?? '',
          t.note,
        ].map(cell).join(','),
      );
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  static String fileStamp(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
}
