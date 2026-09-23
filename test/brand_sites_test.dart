import 'package:flutter_test/flutter_test.dart';
import 'package:owned/domain/brand_sites.dart';

void main() {
  test('known brand: search limited to its site, by model', () {
    final l = productPageLink('Samsung', 'QN65QN90AAF', 'Samsung TV')!;
    expect(l.label, 'Look it up on samsung.com');
    expect(l.url.host, 'www.google.com');
    expect(l.url.queryParameters['q'], 'site:samsung.com QN65QN90AAF');
  });

  test('brand names match regardless of case', () {
    expect(
      productPageLink('APPLE', 'MFYD4VC/A', '')!.label,
      'Look it up on apple.com',
    );
  });

  test('no model: uses the name', () {
    expect(
      productPageLink(
        'Dyson',
        '',
        'Dyson V15 Detect',
      )!.url.queryParameters['q'],
      'site:dyson.com Dyson V15 Detect',
    );
  });

  test('unknown brand: a general search', () {
    final l = productPageLink('Acme', 'X100', '')!;
    expect(l.label, 'Look it up online');
    expect(l.url.queryParameters['q'], 'Acme X100');
  });

  test('nothing to search for', () {
    expect(productPageLink('', '', ''), isNull);
    expect(productPageLink('', '', 'Lemon tree'), isNull);
  });
}
