/// Reads a product's identity from its label: the text the phone recognised
/// plus any barcodes on it. Pure rules, no AI.
class LabelFields {
  const LabelFields({this.brand, this.model, this.serial, this.upc});
  final String? brand;
  final String? model;
  final String? serial;

  /// A retail barcode (UPC/EAN) that identifies the exact product.
  final String? upc;

  bool get isEmpty =>
      brand == null && model == null && serial == null && upc == null;
}

/// Brands we can recognise in label text, in their usual spelling.
const knownBrands = [
  'Samsung',
  'LG',
  'Sony',
  'Apple',
  'Dyson',
  'Whirlpool',
  'GE',
  'Bosch',
  'KitchenAid',
  'Frigidaire', //
  'Maytag',
  'Panasonic',
  'Philips',
  'Dell',
  'HP',
  'Lenovo',
  'Asus',
  'Acer',
  'Microsoft',
  'Nintendo',
  'Canon',
  'Nikon',
  'Bose',
  'Sonos',
  'iRobot',
  'Breville',
  'Vizio',
  'TCL',
  'Hisense',
  'DeWalt',
  'Makita',
  'Milwaukee',
  'Ryobi',
  'Yamaha',
  'Fender',
  'Google',
  'Amazon',
  'Electrolux',
  'Miele',
  'Haier',
  'Sharp',
  'Toshiba',
  'JBL',
  'Garmin',
  'GoPro',
  'Logitech',
  'Ninja',
  'Shark',
  'Cuisinart',
  'Vitamix',
  'Roomba',
  'Keurig',
  'Nespresso',
  'De\'Longhi',
  'Instant Pot',
  'Weber',
  'Traeger',
  'Eufy',
  'Anker',
  'Ring',
  'Nest',
];

/// Words that follow a field name on a label but aren't the value.
const _notValues = {
  'NO',
  'NUMBER',
  'NUM',
  'CODE',
  'NAME',
  'TYPE',
  'MODEL',
  'SERIAL',
  'N',
  'S',
};

final _modelLabel = RegExp(
  r'\b(?:MODEL|MOD|MDL|M/N)(?:\s*(?:NO|NUMBER|CODE|NAME|#))?\s*\.?\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-/.]{2,})',
  caseSensitive: false,
);
final _serialLabel = RegExp(
  r'\b(?:S/N|SN|SER(?:IAL)?)(?:\s*(?:NO|NUMBER|#))?\s*\.?\s*[:#.]?\s*([A-Z0-9][A-Z0-9\-]{4,})',
  caseSensitive: false,
);
final _modelLabelAlone = RegExp(
  r'^\s*(?:MODEL|MOD|MDL|M/N)(?:\s*(?:NO|NUMBER|CODE|NAME|#))?\s*\.?\s*[:#.]?\s*$',
  caseSensitive: false,
);
final _serialLabelAlone = RegExp(
  r'^\s*(?:S/N|SN|SER(?:IAL)?)(?:\s*(?:NO|NUMBER|#))?\s*\.?\s*[:#.]?\s*$',
  caseSensitive: false,
);
final _codeValue = RegExp(r'^[A-Z0-9][A-Z0-9\-/.]{2,}$', caseSensitive: false);

/// Serial formats for brands whose labels often print the number without a field name.
final _brandSerials = <String, RegExp>{
  // e.g. 407KRAB12345
  'LG': RegExp(r'\b\d{3}[A-Z]{3,4}[A-Z0-9]{5,7}\b'),
  // e.g. 0B7Z3CDX400123
  'Samsung': RegExp(r'\b[0-9A-Z]{4}[0-9A-Z]{4}\d{6}[A-Z]?\b'),
  // e.g. XA1-CA-PAB1234A
  'Dyson': RegExp(r'\b[A-Z0-9]{3}-[A-Z]{2}-[A-Z0-9]{7,9}\b'),
  // e.g. C02XK1ABCDEF, or newer 10-character random serials
  'Apple': RegExp(
    r'\b(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-HJ-NP-Z0-9]{10,12}\b',
  ),
};

String? _clean(String? v) {
  if (v == null) return null;
  final s = v.trim().replaceAll(RegExp(r'[.,;:]+$'), '').toUpperCase();
  if (s.length < 3 || _notValues.contains(s)) return null;
  return s;
}

/// True for a UPC-A, EAN-13, EAN-8 or UPC-E code with a valid check digit.
bool isRetailBarcode(String code) {
  if (!RegExp(r'^\d+$').hasMatch(code) || ![8, 12, 13].contains(code.length)) {
    return false;
  }
  final digits = code.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  // Weights alternate 3,1,3,... from the digit next to the check digit.
  for (var i = 0; i < digits.length; i++) {
    final fromRight = digits.length - 1 - i;
    sum += digits[i] * (fromRight.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == check;
}

String? detectBrand(String text) {
  String? best;
  var bestAt = 1 << 30;
  for (final b in knownBrands) {
    final m =
        RegExp(
          '\\b${RegExp.escape(b)}\\b',
          caseSensitive: b.length > 3,
        ).firstMatch(text) ??
        (b.length > 3
            ? RegExp(
                '\\b${RegExp.escape(b)}\\b',
                caseSensitive: false,
              ).firstMatch(text)
            : null);
    if (m != null && m.start < bestAt) {
      best = b;
      bestAt = m.start;
    }
  }
  return best;
}

LabelFields parseLabel(String text, {List<String> barcodes = const []}) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  String? model;
  String? serial;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final next = i + 1 < lines.length ? lines[i + 1] : null;
    model ??= _clean(_modelLabel.firstMatch(line)?.group(1));
    serial ??= _clean(_serialLabel.firstMatch(line)?.group(1));
    // "Model No." on one line, the value on the next.
    if (model == null &&
        _modelLabelAlone.hasMatch(line) &&
        next != null &&
        _codeValue.hasMatch(next)) {
      model = _clean(next);
    }
    if (serial == null &&
        _serialLabelAlone.hasMatch(line) &&
        next != null &&
        _codeValue.hasMatch(next)) {
      serial = _clean(next);
    }
  }

  final brand = detectBrand(text);
  String? upc;
  for (final raw in barcodes) {
    final code = raw.trim();
    if (upc == null && isRetailBarcode(code)) {
      upc = code;
    } else if (serial == null &&
        code.length >= 6 &&
        code.toUpperCase() != model &&
        _codeValue.hasMatch(code)) {
      // Serial labels usually repeat the serial number as a barcode.
      serial = code.toUpperCase();
    }
  }

  if (serial == null && brand != null && _brandSerials[brand] != null) {
    for (final m in _brandSerials[brand]!.allMatches(text.toUpperCase())) {
      final s = m.group(0)!;
      if (s != model) {
        serial = s;
        break;
      }
    }
  }

  return LabelFields(brand: brand, model: model, serial: serial, upc: upc);
}
