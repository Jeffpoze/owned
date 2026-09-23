import 'dart:convert';

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/constants.dart';
import '../domain/models.dart';

/// A product found in a catalog.
class ProductMatch {
  const ProductMatch({
    required this.title,
    this.brand = '',
    this.model = '',
    this.upc = '',
    this.category = Category.other,
    this.imageUrls = const [],
  });

  final String title;
  final String brand;
  final String model;
  final String upc;
  final Category category;
  final List<String> imageUrls;

  static final _bundleWords = RegExp(
    r'\bbundle\b|\s(?:with|w/|\+)\s(?:an?\s)?',
    caseSensitive: false,
  );

  /// A listing that packs this product with something else (e.g. "TV with a soundbar").
  bool get isBundle =>
      model.toUpperCase().startsWith('BNDL') || _bundleWords.hasMatch(title);

  /// The model number: the catalog's, or for bundles (whose model codes are made up)
  /// the first model-like code in the title.
  String get effectiveModel {
    if (model.isNotEmpty && !model.toUpperCase().startsWith('BNDL')) {
      return model.toUpperCase();
    }
    final m = RegExp(
      r'\b(?=[A-Z0-9-]*\d)(?=[A-Z0-9-]*[A-Z])[A-Z0-9][A-Z0-9-]{4,}\b',
    ).firstMatch(title);
    return m?.group(0) ?? '';
  }

  /// A shorter everyday name: drops a leading "Brand - " and what a bundle adds.
  String get displayName {
    var t = title.trim();
    if (isBundle) {
      final cut = _bundleWords.firstMatch(t);
      if (cut != null && cut.start > 10) t = t.substring(0, cut.start);
    }
    if (brand.isNotEmpty) {
      t = t.replaceFirst(
        RegExp('^${RegExp.escape(brand)}\\s*[-–:]\\s*', caseSensitive: false),
        '$brand ',
      );
    }
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 70 ? '${t.substring(0, 67).trimRight()}…' : t;
  }
}

class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class ProductCatalog {
  Future<List<ProductMatch>> search(String query);
  Future<ProductMatch?> lookupBarcode(String upc);

  /// The product with this exact model number (as printed on its label), or null.
  Future<ProductMatch?> findByModel(String brand, String model);

  /// Downloads a product image so it can be saved with the item (never shown from the catalog's servers).
  Future<Uint8List?> downloadImage(ProductMatch match);
}

/// Guesses our kind of item from a catalog category path and title.
Category categoryFromCatalog(String path, String title) {
  final p = path.toLowerCase();
  if (p.contains('furniture')) return Category.furniture;
  if (p.contains('musical') ||
      p.contains('instrument') ||
      p.contains('sporting') ||
      p.contains('bicycle')) {
    return Category.gear;
  }
  if (p.contains('tool') || p.contains('hardware')) return Category.tools;
  if (p.contains('smart home') ||
      p.contains('home automation') ||
      p.contains('security')) {
    return Category.smarthome;
  }
  if (p.contains('major appliance') ||
      p.contains('laundry') ||
      p.contains('refrigerat') ||
      p.contains('vacuum') ||
      p.contains('household appliance')) {
    return Category.appliance;
  }
  if (p.contains('kitchen')) {
    return p.contains('appliance') ? Category.appliance : Category.kitchen;
  }
  if (p.contains('electronic') ||
      p.contains('computer') ||
      p.contains('camera') ||
      p.contains('video game')) {
    return Category.electronics;
  }
  final t = title.toLowerCase();
  for (final entry in categories.entries) {
    if (entry.value.words.any((w) => RegExp('\\b$w\\b').hasMatch(t))) {
      return entry.key;
    }
  }
  return Category.other;
}

/// Normalised for comparing model numbers: "QN65-QN90AAF" and "qn65qn90aaf" match.
String normalizeModel(String s) =>
    s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Picks the search result whose model best matches a model read from a label.
ProductMatch? bestModelMatch(List<ProductMatch> results, String model) {
  final want = normalizeModel(model);
  if (want.length < 3) return null;
  ProductMatch? best;
  var bestScore = 0;
  for (final r in results) {
    final have = normalizeModel(r.model);
    final inTitle = normalizeModel(r.title).contains(want);
    final score = have == want
        ? 3
        : (have.isNotEmpty && (have.startsWith(want) || want.startsWith(have)))
        ? 2
        : inTitle
        ? 1
        : 0;
    if (score > bestScore) {
      best = r;
      bestScore = score;
    }
  }
  return best;
}

const _unreachable = CatalogException(
  "Couldn't reach the product catalog. Check your connection.",
);
const _usedUp = CatalogException(
  'Product suggestions are used up for today. Fill in the details by hand for now.',
);

/// Downloads the first usable image, so it can be saved with the item.
Future<Uint8List?> _downloadFirst(http.Client client, List<String> urls) async {
  for (final url in urls.take(4)) {
    try {
      final res = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode == 200 &&
          type.startsWith('image/') &&
          res.bodyBytes.length > 2000) {
        return res.bodyBytes;
      }
    } catch (_) {
      // Try the next image.
    }
  }
  return null;
}

/// UPCitemdb's free trial: text search and barcode lookups, no key, about 100
/// requests a day per network (shared by every device on the same Wi-Fi).
/// Development only; before launch, move to a licensed plan behind a server function.
class UpcItemDbCatalog implements ProductCatalog {
  UpcItemDbCatalog({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, List<ProductMatch>> _cache = {};
  static const _base = 'https://api.upcitemdb.com/prod/trial';

  /// Set when the daily allowance runs out, so the app stops asking until tomorrow.
  DateTime? _usedUpOn;

  bool get _usedUpToday {
    final d = _usedUpOn;
    final now = DateTime.now();
    return d != null &&
        d.year == now.year &&
        d.month == now.month &&
        d.day == now.day;
  }

  Future<Map<String, Object?>> _get(
    String path,
    Map<String, String> params,
  ) async {
    if (_usedUpToday) throw _usedUp;
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$_base/$path').replace(queryParameters: params))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw _unreachable;
    }
    if (res.statusCode == 429) {
      _usedUpOn = DateTime.now();
      throw _usedUp;
    }
    final body = jsonDecode(res.body) as Map<String, Object?>;
    if (res.statusCode == 400 && body['code'] == 'INVALID_UPC') {
      return const {'items': []};
    }
    if (res.statusCode != 200) {
      throw const CatalogException(
        'The product catalog had a problem. Try again.',
      );
    }
    return body;
  }

  ProductMatch _match(Map<String, Object?> j) {
    final title = (j['title'] as String? ?? '').trim();
    return ProductMatch(
      title: title,
      brand: (j['brand'] as String? ?? '').trim(),
      model: (j['model'] as String? ?? '').trim(),
      upc: (j['upc'] as String? ?? j['ean'] as String? ?? '').trim(),
      category: categoryFromCatalog(j['category'] as String? ?? '', title),
      imageUrls: [
        for (final u in (j['images'] as List? ?? const []))
          if (u is String && u.startsWith('https://')) u,
      ],
    );
  }

  /// Results already fetched for a shorter query, narrowed to [q] without a new request.
  List<ProductMatch>? _refineCached(String q) {
    final words = q.split(' ').where((w) => w.isNotEmpty).toList();
    for (final entry in _cache.entries) {
      if (entry.value.isEmpty || !q.startsWith(entry.key)) continue;
      final hits = entry.value.where((m) {
        final hay = '${m.title} ${m.brand} ${m.model}'.toLowerCase();
        return words.every(hay.contains);
      }).toList();
      if (hits.isNotEmpty) return hits;
    }
    return null;
  }

  @override
  Future<List<ProductMatch>> search(String query) async {
    final q = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final cached = _cache[q] ?? _refineCached(q);
    if (cached != null) return cached;
    final body = await _get('search', {
      's': q,
      'match_mode': '0',
      'type': 'product',
    });
    final seen = <String>{};
    final results = <ProductMatch>[];
    for (final j in (body['items'] as List? ?? const [])) {
      final m = _match((j as Map).cast<String, Object?>());
      // One row per model: catalogs list the same product from many sellers.
      final key = normalizeModel(m.model.isNotEmpty ? m.model : m.title);
      if (m.title.isEmpty || !seen.add(key)) continue;
      results.add(m);
    }
    // The plain product before bundles that include it (stable, so the catalog's order is kept otherwise).
    return _cache[q] = [
      ...results.where((m) => !m.isBundle),
      ...results.where((m) => m.isBundle),
    ];
  }

  @override
  Future<ProductMatch?> lookupBarcode(String upc) async {
    final items =
        (await _get('lookup', {'upc': upc}))['items'] as List? ?? const [];
    return items.isEmpty
        ? null
        : _match((items.first as Map).cast<String, Object?>());
  }

  @override
  Future<ProductMatch?> findByModel(String brand, String model) async =>
      bestModelMatch(
        await search([brand, model].where((s) => s.isNotEmpty).join(' ')),
        model,
      );

  @override
  Future<Uint8List?> downloadImage(ProductMatch match) =>
      _downloadFirst(_client, match.imageUrls);
}

/// Open Icecat: manufacturer data and images for brands that publish them openly
/// (Samsung, HP, Lenovo and many more; not Apple). Exact lookups only (barcode, or
/// brand + manufacturer part code), no daily limit, and images licensed for this use.
class IcecatCatalog implements ProductCatalog {
  IcecatCatalog({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://live.icecat.biz/api';

  Future<ProductMatch?> _lookup(Map<String, String> params) async {
    final http.Response res;
    try {
      res = await _client
          .get(
            Uri.parse(_base).replace(
              queryParameters: {
                'lang': 'en',
                'shopname': 'openicecat-live',
                'content': '',
                ...params,
              },
            ),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw _unreachable;
    }
    // Not found, or a brand that doesn't share its data openly.
    if (res.statusCode != 200) return null;
    final data =
        (jsonDecode(res.body) as Map<String, Object?>)['data']
            as Map<String, Object?>?;
    final info = data?['GeneralInfo'] as Map<String, Object?>?;
    if (info == null) return null;
    final image = data?['Image'] as Map<String, Object?>? ?? const {};
    final category =
        ((info['Category'] as Map?)?['Name'] as Map?)?['Value'] as String? ??
        '';
    final title = (info['Title'] as String? ?? '').trim();
    return ProductMatch(
      title: title,
      brand: (info['Brand'] as String? ?? '').trim(),
      model: (info['BrandPartCode'] as String? ?? '').trim(),
      upc: params['GTIN'] ?? '',
      category: categoryFromCatalog(category, title),
      imageUrls: [
        for (final k in ['HighPic', 'Pic500x500', 'LowPic'])
          if (image[k] is String && (image[k] as String).startsWith('https://'))
            image[k] as String,
      ],
    );
  }

  @override
  Future<List<ProductMatch>> search(String query) async => const [];

  @override
  Future<ProductMatch?> lookupBarcode(String upc) => _lookup({'GTIN': upc});

  @override
  Future<ProductMatch?> findByModel(String brand, String model) async =>
      brand.isEmpty ? null : _lookup({'Brand': brand, 'ProductCode': model});

  @override
  Future<Uint8List?> downloadImage(ProductMatch match) =>
      _downloadFirst(_client, match.imageUrls);
}

/// Exact lookups try Open Icecat first (free, no daily limit), then UPCitemdb.
/// Text search (the suggestions while typing) uses UPCitemdb.
class CombinedCatalog implements ProductCatalog {
  CombinedCatalog(this.exact, this.search_);
  final ProductCatalog exact;
  final ProductCatalog search_;

  @override
  Future<List<ProductMatch>> search(String query) => search_.search(query);

  @override
  Future<ProductMatch?> lookupBarcode(String upc) async =>
      await _quiet(() => exact.lookupBarcode(upc)) ??
      await search_.lookupBarcode(upc);

  @override
  Future<ProductMatch?> findByModel(String brand, String model) async =>
      await _quiet(() => exact.findByModel(brand, model)) ??
      await search_.findByModel(brand, model);

  @override
  Future<Uint8List?> downloadImage(ProductMatch match) =>
      search_.downloadImage(match);

  /// The first source failing shouldn't stop the second from being tried.
  static Future<ProductMatch?> _quiet(
    Future<ProductMatch?> Function() f,
  ) async {
    try {
      return await f();
    } on CatalogException {
      return null;
    }
  }
}

/// Shared so search results are cached across screens.
final ProductCatalog productCatalog = CombinedCatalog(
  IcecatCatalog(),
  UpcItemDbCatalog(),
);
