import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  for (final name in ['loading', 'success', 'error', 'coin', 'confetti', 'sparkle']) {
    test('animasi Lottie $name bisa dibaca', () async {
      final bytes = await File('assets/lottie/$name.json').readAsBytes();
      final comp = await LottieComposition.fromBytes(bytes);
      expect(comp.duration, greaterThan(Duration.zero));
      expect(comp.layers, isNotEmpty);
    });
  }
}
