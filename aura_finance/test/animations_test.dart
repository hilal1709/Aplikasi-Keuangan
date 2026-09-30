import 'dart:async';

import 'package:aura_finance/core/illustrations/clay.dart';
import 'package:aura_finance/core/theme/app_theme.dart';
import 'package:aura_finance/core/theme/tokens.dart';
import 'package:aura_finance/core/widgets/aura_page.dart';
import 'package:aura_finance/core/widgets/form_sheet.dart';
import 'package:aura_finance/core/widgets/lottie.dart';
import 'package:aura_finance/core/widgets/neu_surface.dart';
import 'package:aura_finance/core/widgets/primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _app(Widget home) => ShadApp(
      theme: AppTheme.shad(AuraPalette.light),
      materialThemeBuilder: (context, theme) => AppTheme.material(AuraPalette.light),
      home: home,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('PrimaryAction async menampilkan loader lalu kembali ke label', (t) async {
    final done = Completer<void>();
    await t.pumpWidget(_app(Scaffold(body: PrimaryAction(label: 'Simpan', onPressed: () => done.future))));
    await t.pump(const Duration(milliseconds: 600));

    await t.tap(find.text('Simpan'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(AuraLoader), findsOneWidget);

    done.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(AuraLoader), findsNothing);
    expect(find.text('Simpan'), findsOneWidget);
  });

  testWidgets('NeuPressable & NeuIconButton: glow + miring tanpa error', (t) async {
    var taps = 0;
    await t.pumpWidget(_app(Scaffold(
      body: Column(children: [
        NeuPressable(onTap: () => taps++, width: 200, height: 80, child: const Text('Kartu')),
        NeuIconButton(HugeIcons.strokeRoundedAdd01, onTap: () => taps++),
      ]),
    )));
    await t.tap(find.text('Kartu'));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byType(NeuIconButton));
    await t.pumpAndSettle();
    expect(taps, 2);
  });

  testWidgets('SplitReveal selesai menjadi teks biasa', (t) async {
    await t.pumpWidget(_app(const Scaffold(body: SplitReveal('Target Tabungan'))));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('T'), findsWidgets);
    await t.pumpAndSettle();
    expect(find.text('Target Tabungan'), findsOneWidget);
  });

  testWidgets('ScrollReveal muncul saat digulir ke layar', (t) async {
    await t.pumpWidget(_app(Scaffold(
      body: ListView(children: [
        const SizedBox(height: 700),
        const Text('Bawah').reveal(),
        const SizedBox(height: 1200),
      ]),
    )));
    await t.pumpAndSettle();
    final opacity = find.ancestor(of: find.text('Bawah', skipOffstage: false), matching: find.byType(Opacity, skipOffstage: false)).first;
    expect(t.widget<Opacity>(opacity).opacity, 0);

    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pumpAndSettle();
    expect(t.widget<Opacity>(opacity).opacity, 1);
  });

  testWidgets('staggerIn: jeda dibatasi walau indeks besar', (t) async {
    await t.pumpWidget(_app(Scaffold(body: const Text('Item 90').staggerIn(90))));
    // 8 langkah × 90ms + 1000ms animasi — jauh di bawah 90 × 90ms.
    await t.pump(const Duration(milliseconds: 800));
    await t.pump(const Duration(milliseconds: 1000));
    final opacity = find.ancestor(of: find.text('Item 90'), matching: find.byType(Opacity)).first;
    expect(t.widget<Opacity>(opacity).opacity, 1);
  });

  testWidgets('staggerIn diputar ulang saat tab aktif lagi (TickerMode)', (t) async {
    Widget tab(bool on) => _app(Scaffold(body: TickerMode(enabled: on, child: const Text('Isi tab').staggerIn(0))));
    Opacity op() => t.widget<Opacity>(find.ancestor(of: find.text('Isi tab'), matching: find.byType(Opacity)).first);

    await t.pumpWidget(tab(true));
    await t.pumpAndSettle();
    expect(op().opacity, 1);

    await t.pumpWidget(tab(false));
    await t.pump();
    await t.pumpWidget(tab(true));
    await t.pump();
    expect(op().opacity, lessThan(0.1));
    await t.pumpAndSettle();
    expect(op().opacity, 1);
  });

  testWidgets('Form sheet: isi mengalir masuk, sorot fokus & goyang', (t) async {
    await t.pumpWidget(_app(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showFormSheet<void>(
            context,
            title: 'Tagihan baru',
            builder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Nama'),
                const ShadInput(placeholder: Text('mis. Listrik')),
                AmountField(initial: 0, onChanged: (_) {}),
                ShareToggle(title: 'Bersama', value: true, onChanged: (_) {}),
                Builder(builder: (c) => PrimaryAction(label: 'Simpan', onPressed: () => FormShake.shake(c))),
              ],
            ),
          ),
          child: const Text('Buka'),
        ),
      ),
    )));
    await t.tap(find.text('Buka'));
    await t.pumpAndSettle();
    expect(find.text('Tagihan baru'), findsOneWidget);

    await t.tap(find.byType(EditableText).first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(EditableText).at(1), '150000');
    await t.pumpAndSettle();
    expect(find.text('Rp 150.000'), findsOneWidget);

    await t.tap(find.text('Simpan'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('AuraPage & ClayEmpty dengan kilau Lottie ter-render', (t) async {
    await t.pumpWidget(_app(AuraPage(
      title: 'Tagihan',
      subtitle: 'Pengingat',
      actions: [NeuIconButton(HugeIcons.strokeRoundedAdd01, onTap: () {})],
      slivers: const [
        SliverToBoxAdapter(child: ClayEmpty(kind: ClayKind.calendar, title: 'Kosong', message: 'Belum ada')),
      ],
    )));
    for (var k = 0; k < 20; k++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Tagihan'), findsOneWidget);
    expect(find.byType(AuraSparkle), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
