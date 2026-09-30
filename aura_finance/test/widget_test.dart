import 'package:aura_finance/core/utils/rupiah.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('format rupiah penuh & ringkas', () {
    expect(Rupiah.format(84520000), 'Rp 84.520.000');
    expect(Rupiah.format(-68000), '-Rp 68.000');
    expect(Rupiah.format(7500000, signed: true), '+Rp 7.500.000');
    expect(Rupiah.compact(1200000), 'Rp 1,2 jt');
    expect(Rupiah.compact(450000), 'Rp 450 rb');
    expect(Rupiah.compact(2000000000), 'Rp 2 M');
  });
}
