import 'package:flutter_test/flutter_test.dart';
import 'package:owned/domain/label_parser.dart';

void main() {
  group('retail barcodes', () {
    test('valid UPC-A, EAN-13 and EAN-8 check digits', () {
      expect(isRetailBarcode('887276520803'), isTrue); // Samsung TV
      expect(isRetailBarcode('036000291452'), isTrue);
      expect(isRetailBarcode('4006381333931'), isTrue);
      expect(isRetailBarcode('96385074'), isTrue);
    });

    test('rejects wrong check digits and non-retail codes', () {
      expect(isRetailBarcode('887276520804'), isFalse);
      expect(isRetailBarcode('887276741289'), isFalse);
      expect(isRetailBarcode('0B7Z3CDX400123'), isFalse);
      expect(isRetailBarcode('12345'), isFalse);
    });
  });

  group('label text', () {
    test('Samsung TV label', () {
      final f = parseLabel('''
SAMSUNG
Model Code: QN65QN90DAFXZC
Serial No. : 0B7Z3CDX400123
AC 120V~ 60Hz 320W
Made in Mexico''');
      expect(f.brand, 'Samsung');
      expect(f.model, 'QN65QN90DAFXZC');
      expect(f.serial, '0B7Z3CDX400123');
    });

    test('field name and value on separate lines', () {
      final f = parseLabel('''
LG Electronics
MODEL NO.
LRFVS3006S
S/N
407KRAB12345''');
      expect(f.brand, 'LG');
      expect(f.model, 'LRFVS3006S');
      expect(f.serial, '407KRAB12345');
    });

    test('abbreviations: MOD and SN', () {
      final f = parseLabel('Dyson  MOD: SV22   SN: XA1-CA-PAB1234A');
      expect(f.brand, 'Dyson');
      expect(f.model, 'SV22');
      expect(f.serial, 'XA1-CA-PAB1234A');
    });

    test('a field name without a value is not a value', () {
      final f = parseLabel('Model Number\nSerial Number');
      expect(f.model, isNull);
      expect(f.serial, isNull);
    });

    test('brand serial pattern when the label has no "Serial" field', () {
      final f = parseLabel('LG\nMODEL: OLED65C4PUA\n407KRAB12345');
      expect(f.model, 'OLED65C4PUA');
      expect(f.serial, '407KRAB12345');
    });

    test('nothing recognisable', () {
      expect(parseLabel('Keep dry. Do not open.').isEmpty, isTrue);
    });

    test(
      'short brands only match in capitals, so "ge" inside words is ignored',
      () {
        expect(detectBrand('Please charge before use'), isNull);
        expect(detectBrand('GE Appliances'), 'GE');
      },
    );
  });

  group('barcodes on the label', () {
    test('a retail barcode becomes the UPC', () {
      final f = parseLabel('', barcodes: ['887276520803']);
      expect(f.upc, '887276520803');
      expect(f.serial, isNull);
    });

    test('another barcode fills the serial when the text had none', () {
      final f = parseLabel('Model: SV22', barcodes: ['XA1CAPAB1234A']);
      expect(f.serial, 'XA1CAPAB1234A');
    });

    test('the text serial wins over a barcode', () {
      final f = parseLabel('S/N: ABC123456', barcodes: ['ZZZ999999']);
      expect(f.serial, 'ABC123456');
    });
  });
}
