import 'package:carcare/services/fuel_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveFuelValue', () {
    test('ลิตร × ราคา = ยอดรวม', () {
      expect(
        deriveFuelValue(target: FuelField.total, liters: 40, pricePerLiter: 35),
        1400,
      );
    });

    test('ยอดรวม ÷ ลิตร = ราคาต่อลิตร', () {
      expect(
        deriveFuelValue(target: FuelField.pricePerLiter, liters: 40, total: 1500),
        37.5,
      );
    });

    test('ยอดรวม ÷ ราคาต่อลิตร = ลิตร', () {
      expect(
        deriveFuelValue(target: FuelField.liters, pricePerLiter: 35, total: 1400),
        40,
      );
    });

    test('ปัดสองตำแหน่ง', () {
      // 1000 / 38.54 = 25.9470...
      expect(
        deriveFuelValue(target: FuelField.liters, pricePerLiter: 38.54, total: 1000),
        25.95,
      );
      // 1000 / 27 = 37.037...
      expect(
        deriveFuelValue(target: FuelField.pricePerLiter, liters: 27, total: 1000),
        37.04,
      );
    });

    test('ข้อมูลไม่ครบสองช่อง คำนวณไม่ได้', () {
      expect(deriveFuelValue(target: FuelField.total, liters: 40), isNull);
      expect(deriveFuelValue(target: FuelField.total, pricePerLiter: 35), isNull);
      expect(deriveFuelValue(target: FuelField.liters, total: 1400), isNull);
      expect(deriveFuelValue(target: FuelField.pricePerLiter), isNull);
    });

    test('ตัวหารเป็นศูนย์ ต้องไม่คืน infinity', () {
      expect(
        deriveFuelValue(target: FuelField.liters, pricePerLiter: 0, total: 1400),
        isNull,
      );
      expect(
        deriveFuelValue(target: FuelField.pricePerLiter, liters: 0, total: 1400),
        isNull,
      );
    });

    test('ค่าติดลบหรือศูนย์ ไม่ถือว่าคำนวณได้', () {
      expect(
        deriveFuelValue(target: FuelField.total, liters: 40, pricePerLiter: 0),
        isNull,
      );
      expect(
        deriveFuelValue(target: FuelField.liters, pricePerLiter: 35, total: -100),
        isNull,
      );
    });
  });
}
