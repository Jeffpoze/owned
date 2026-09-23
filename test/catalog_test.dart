import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:owned/domain/models.dart';
import 'package:owned/services/catalog.dart';

void main() {
  test('catalog categories map to our kinds', () {
    expect(
      categoryFromCatalog('Electronics > Video > Televisions', ''),
      Category.electronics,
    );
    expect(
      categoryFromCatalog('Home & Garden > Household Appliances > Vacuums', ''),
      Category.appliance,
    );
    expect(
      categoryFromCatalog('Home & Garden > Kitchen & Dining > Cookware', ''),
      Category.kitchen,
    );
    expect(categoryFromCatalog('Furniture > Chairs', ''), Category.furniture);
    expect(
      categoryFromCatalog('Arts & Entertainment > Musical Instruments', ''),
      Category.gear,
    );
    expect(categoryFromCatalog('', 'Cordless drill kit'), Category.tools);
    expect(categoryFromCatalog('', 'Mystery object'), Category.other);
  });

  test('display name drops the "Brand - " prefix and stays short', () {
    const m = ProductMatch(
      title: 'Samsung - 65" Class QN90A Neo QLED 4K UHD Smart Tizen TV',
      brand: 'Samsung',
    );
    expect(
      m.displayName,
      'Samsung 65" Class QN90A Neo QLED 4K UHD Smart Tizen TV',
    );
    final long = ProductMatch(title: 'A' * 120);
    expect(long.displayName.length, lessThanOrEqualTo(70));
  });

  test('best model match prefers exact models, then prefixes, then titles', () {
    const results = [
      ProductMatch(title: 'Bundle with soundbar', model: 'BNDL QN90AA-Q60T-65'),
      ProductMatch(title: 'Samsung 65" QN90A', model: 'QN65QN90AAF'),
      ProductMatch(title: 'Samsung QN65QN90AAFXZA TV', model: ''),
    ];
    expect(bestModelMatch(results, 'QN65QN90AAF')!.model, 'QN65QN90AAF');
    expect(
      bestModelMatch(results, 'qn65-qn90aafxza')!.model,
      'QN65QN90AAF',
    ); // prefix
    expect(bestModelMatch(results, 'XYZ123'), isNull);
  });

  test(
    'bundles: detected, named without the add-on, model read from the title',
    () {
      const bundle = ProductMatch(
        title: 'Samsung QN65QN90AA 65" Neo QLED QN90 Series 4K Smart TV with a Samsung HW-Q60T Wireless 5.1 Channel Soundbar',
        brand: 'SAMSUNG',
        model: 'BNDL QN90AA-Q60T-65',
      );
      expect(bundle.isBundle, isTrue);
      expect(bundle.effectiveModel, 'QN65QN90AA');
      expect(
        bundle.displayName,
        'Samsung QN65QN90AA 65" Neo QLED QN90 Series 4K Smart TV',
      );
      const plain = ProductMatch(
        title: 'Samsung 65" Class QN90A Neo QLED',
        model: 'QN65QN90AAF',
      );
      expect(plain.isBundle, isFalse);
      expect(plain.effectiveModel, 'QN65QN90AAF');
    },
  );

  group('UPCitemdb request savings', () {
    Map<String, Object?> item(String title, String model) => {
      'title': title,
      'brand': 'Samsung',
      'model': model,
    };

    test(
      'longer queries are answered from earlier results without a new request',
      () async {
        var requests = 0;
        final client = MockClient((req) async {
          requests++;
          return http.Response(
            jsonEncode({
              'items': [
                item('Samsung QN90A TV', 'QN65QN90AAF'),
                item('Samsung Galaxy S24', 'SM-S921'),
              ],
            }),
            200,
          );
        });
        final catalog = UpcItemDbCatalog(client: client);
        await catalog.search('samsung');
        final refined = await catalog.search('samsung qn90');
        expect(requests, 1);
        expect(refined.map((m) => m.model), ['QN65QN90AAF']);
        await catalog.search('samsung');
        expect(requests, 1, reason: 'repeat searches come from the cache');
      },
    );

    test(
      'after the daily limit is hit, no more requests are made that day',
      () async {
        var requests = 0;
        final client = MockClient((req) async {
          requests++;
          return http.Response('{"code":"TOO_FAST"}', 429);
        });
        final catalog = UpcItemDbCatalog(client: client);
        await expectLater(
          catalog.search('dyson'),
          throwsA(isA<CatalogException>()),
        );
        await expectLater(
          catalog.search('bosch'),
          throwsA(isA<CatalogException>()),
        );
        expect(requests, 1);
      },
    );
  });

  group('Open Icecat', () {
    final icecatTv = {
      'msg': 'OK',
      'data': {
        'GeneralInfo': {
          'Title':
              'Samsung QN90A 163.8 cm (64.5") 4K Ultra HD Smart TV Wi-Fi Black',
          'Brand': 'Samsung',
          'BrandPartCode': 'QN65QN90AAFXZA',
          'Category': {
            'Name': {'Value': 'TVs'},
          },
        },
        'Image': {'HighPic': 'https://images.icecat.biz/img/gallery/tv.jpg'},
      },
    };

    test('reads a product from a barcode lookup', () async {
      final client = MockClient((req) async {
        expect(req.url.queryParameters['GTIN'], '887276520803');
        return http.Response(jsonEncode(icecatTv), 200);
      });
      final m = await IcecatCatalog(client: client)
          .lookupBarcode('887276520803');
      expect(m!.brand, 'Samsung');
      expect(m.model, 'QN65QN90AAFXZA');
      expect(m.imageUrls, ['https://images.icecat.biz/img/gallery/tv.jpg']);
    });

    test(
      'not found or restricted brands give no match, not an error',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            '{"msg":"Product has brand restrictions","StatusCode":14}',
            403,
          ),
        );
        expect(
          await IcecatCatalog(client: client).findByModel('Apple', 'MFYD4VC/A'),
          isNull,
        );
      },
    );

    test('combined catalog tries Icecat first, then UPCitemdb', () async {
      final hosts = <String>[];
      final client = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'live.icecat.biz') {
          return http.Response('{"msg":"not present","StatusCode":8}', 404);
        }
        return http.Response(
          jsonEncode({
            'items': [
              {'title': 'Dyson V15 Detect', 'brand': 'Dyson', 'model': 'SV22'},
            ],
          }),
          200,
        );
      });
      final catalog = CombinedCatalog(
        IcecatCatalog(client: client),
        UpcItemDbCatalog(client: client),
      );
      final m = await catalog.findByModel('Dyson', 'SV22');
      expect(m!.title, 'Dyson V15 Detect');
      expect(hosts, ['live.icecat.biz', 'api.upcitemdb.com']);
    });
  });
}
