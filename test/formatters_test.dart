import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/core/utils/formatters.dart';

void main() {
  test('bytes formatting', () {
    expect(Formatters.bytes(500), '500 B');
    expect(Formatters.bytes(2048), '2.0 KB');
    expect(Formatters.bytes(1536 * 1024 * 1024), '1.5 GB');
    expect(Formatters.bytes(-1), '-');
  });

  test('duration formatting', () {
    expect(Formatters.duration(0), '0:00');
    expect(Formatters.duration(65000), '1:05');
    expect(Formatters.duration(3675000), '1:01:15');
  });

  test('eta formatting', () {
    expect(Formatters.eta(60000, 1000), '1:00');
    expect(Formatters.eta(1000, 0), '-');
  });

  test('speed formatting', () {
    expect(Formatters.speed(2 * 1024 * 1024), '2.0 MB/s');
    expect(Formatters.speed(0), '-');
  });

  test('percent clamps', () {
    expect(Formatters.percent(150), '100%');
    expect(Formatters.percent(42.5), '42.5%');
  });
}
