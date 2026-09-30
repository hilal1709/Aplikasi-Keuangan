import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../data/local/database.dart';

/// Ekspor transaksi satu bulan ke CSV atau PDF, lalu buka lembar "Bagikan".
class ExportService {
  ExportService(this.db);
  final AppDatabase db;

  Future<List<TxEntry>> _rows(DateTime month) =>
      db.watchTx(from: DateId.monthStart(month), to: DateId.nextMonthStart(month)).first;

  Future<(Map<String, Category>, Map<String, Wallet>)> _lookups() async {
    final cats = await db.select(db.categories).get();
    final wallets = await db.select(db.wallets).get();
    return ({for (final c in cats) c.id: c}, {for (final w in wallets) w.id: w});
  }

  String _kind(TxKind k) => switch (k) { TxKind.income => 'Pemasukan', TxKind.expense => 'Pengeluaran', TxKind.transfer => 'Transfer' };

  Future<void> shareCsv(DateTime month) async {
    final rows = await _rows(month);
    final (cats, wallets) = await _lookups();
    final data = [
      ['Tanggal', 'Jenis', 'Kategori', 'Dompet', 'Ke dompet', 'Nominal', 'Catatan'],
      for (final t in rows.reversed)
        [
          t.occurredAt.toIso8601String().substring(0, 16).replaceFirst('T', ' '),
          _kind(t.kind),
          cats[t.categoryId]?.name ?? '',
          wallets[t.walletId]?.name ?? '',
          wallets[t.toWalletId]?.name ?? '',
          t.amount,
          t.note,
        ],
    ];
    final csv = excel.encode(data);
    final file = await _file('aura-${month.year}-${month.month.toString().padLeft(2, '0')}.csv');
    await file.writeAsString('﻿$csv'); // BOM supaya Excel membaca UTF-8
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Transaksi ${DateId.month(month)}'));
  }

  Future<void> sharePdf(DateTime month) async {
    final rows = await _rows(month);
    final (cats, wallets) = await _lookups();
    final income = rows.where((t) => t.kind == TxKind.income).fold<int>(0, (s, t) => s + t.amount);
    final expense = rows.where((t) => t.kind == TxKind.expense).fold<int>(0, (s, t) => s + t.amount);
    final byCat = <String, int>{};
    for (final t in rows.where((t) => t.kind == TxKind.expense)) {
      final name = cats[t.categoryId]?.name ?? 'Lainnya';
      byCat[name] = (byCat[name] ?? 0) + t.amount;
    }
    final topCats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    const rose = PdfColor.fromInt(0xFFAF2365);
    const muted = PdfColor.fromInt(0xFF574147);
    const soft = PdfColor.fromInt(0xFFFBF1F1);

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Text('Laporan Keuangan', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: rose)),
        pw.Text(DateId.month(month), style: const pw.TextStyle(fontSize: 12, color: muted)),
        pw.SizedBox(height: 18),
        pw.Row(children: [
          for (final (label, v) in [('Pemasukan', income), ('Pengeluaran', expense), ('Selisih', income - expense)])
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.only(right: 8),
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: muted)),
                  pw.SizedBox(height: 4),
                  pw.Text(Rupiah.format(v), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ]),
              ),
            ),
        ]),
        pw.SizedBox(height: 18),
        if (topCats.isNotEmpty) ...[
          pw.Text('Pengeluaran per kategori', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          for (final e in topCats.take(8))
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text(e.key, style: const pw.TextStyle(fontSize: 10))),
                pw.Text('${(e.value / (expense == 0 ? 1 : expense) * 100).toStringAsFixed(0)}%   ${Rupiah.format(e.value)}',
                    style: const pw.TextStyle(fontSize: 10)),
              ]),
            ),
          pw.SizedBox(height: 18),
        ],
        pw.TableHelper.fromTextArray(
          headers: ['Tanggal', 'Jenis', 'Kategori', 'Dompet', 'Nominal', 'Catatan'],
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: rose),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          oddRowDecoration: const pw.BoxDecoration(color: soft),
          cellAlignments: {4: pw.Alignment.centerRight},
          data: [
            for (final t in rows.reversed)
              [
                DateId.short(t.occurredAt),
                _kind(t.kind),
                t.kind == TxKind.transfer ? '→ ${wallets[t.toWalletId]?.name ?? ''}' : cats[t.categoryId]?.name ?? '',
                wallets[t.walletId]?.name ?? '',
                Rupiah.format(t.amount),
                t.note,
              ],
          ],
        ),
      ],
    ));
    final file = await _file('aura-${month.year}-${month.month.toString().padLeft(2, '0')}.pdf');
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Laporan ${DateId.month(month)}'));
  }

  Future<File> _file(String name) async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$name');
  }
}
