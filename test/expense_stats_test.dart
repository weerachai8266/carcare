import 'package:carcare/models/fuel_entry.dart';
import 'package:carcare/models/service_record.dart';
import 'package:carcare/services/expense_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// วันที่ 1 ม.ค. 2025 + [dayOffset] วัน
int _day(int dayOffset) =>
    DateTime(2025, 1, 1).add(Duration(days: dayOffset)).millisecondsSinceEpoch;

FuelEntry _fuel({
  required String id,
  required int dayOffset,
  required double odometer,
  double liters = 40,
  double? pricePerLiter,
  double? totalCost,
}) {
  return FuelEntry(
    id: id,
    vehicleId: 'v1',
    date: _day(dayOffset),
    odometer: odometer,
    liters: liters,
    pricePerLiter: pricePerLiter,
    totalCost: totalCost,
    createdAt: 0,
    updatedAt: 0,
  );
}

ServiceRecord _service({
  required String id,
  required int dayOffset,
  required double odometer,
  double? cost,
}) {
  return ServiceRecord(
    id: id,
    vehicleId: 'v1',
    title: 'เปลี่ยนน้ำมันเครื่อง',
    date: _day(dayOffset),
    odometer: odometer,
    cost: cost,
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  group('monthlyExpenses', () {
    test('รวมตามเดือน แยกน้ำมันกับบำรุงรักษา เรียงจากเก่าไปใหม่', () {
      final months = monthlyExpenses(
        [
          _fuel(id: 'a', dayOffset: 40, odometer: 11000, totalCost: 1400),
          _fuel(id: 'b', dayOffset: 0, odometer: 10000, totalCost: 1400),
          _fuel(id: 'c', dayOffset: 10, odometer: 10500, liters: 30, totalCost: 1050),
        ],
        [_service(id: 's1', dayOffset: 5, odometer: 10200, cost: 900)],
      );

      expect(months, hasLength(2));
      expect(months.first.month, 1);
      expect(months.first.fuelCost, 2450);
      expect(months.first.serviceCost, 900);
      expect(months.first.liters, 70);
      expect(months.first.total, 3350);
      expect(months.last.month, 2);
      expect(months.last.fuelCost, 1400);
      expect(months.last.serviceCost, 0);
    });

    test('เดือนที่ไม่ได้จ่ายอะไรต้องอยู่ในผลลัพธ์เป็นศูนย์ ไม่ใช่หายไป', () {
      final months = monthlyExpenses(
        [
          _fuel(id: 'a', dayOffset: 0, odometer: 10000, totalCost: 1000),
          // ห่างจากครั้งแรกสามเดือน
          _fuel(id: 'b', dayOffset: 90, odometer: 13000, totalCost: 1000),
        ],
        const [],
      );

      expect(months, hasLength(4));
      expect(months[1].total, 0);
      expect(months[2].total, 0);
      expect(months[1].month, 2);
      expect(months[2].month, 3);
    });

    test('ข้ามปีได้ถูกต้อง', () {
      final months = monthlyExpenses(
        [
          _fuel(id: 'a', dayOffset: -40, odometer: 9000, totalCost: 500),
          _fuel(id: 'b', dayOffset: 0, odometer: 10000, totalCost: 500),
        ],
        const [],
      );

      expect(months, hasLength(3));
      expect(months.first.year, 2024);
      expect(months.first.month, 11);
      expect(months.last.year, 2025);
      expect(months.last.month, 1);
    });

    test('ไม่มีข้อมูลเลยก็คืนลิสต์ว่าง', () {
      expect(monthlyExpenses(const [], const []), isEmpty);
    });
  });

  group('summarizeExpenses', () {
    test('รวมค่าน้ำมันและค่าบำรุงรักษาเข้าด้วยกัน', () {
      final summary = summarizeExpenses(
        [
          _fuel(id: 'a', dayOffset: 0, odometer: 10000, totalCost: 1400),
          _fuel(id: 'b', dayOffset: 30, odometer: 11000, totalCost: 1600),
        ],
        [
          _service(id: 's1', dayOffset: 10, odometer: 10400, cost: 2000),
          _service(id: 's2', dayOffset: 20, odometer: 10700, cost: 1000),
        ],
      );

      expect(summary.fuelCost, 3000);
      expect(summary.serviceCost, 3000);
      expect(summary.total, 6000);
      expect(summary.serviceCount, 2);
    });

    test('ใช้ราคาต่อลิตรคำนวณแทนเมื่อไม่ได้กรอกยอดรวม', () {
      final summary = summarizeExpenses(
        [_fuel(id: 'a', dayOffset: 0, odometer: 10000, liters: 40, pricePerLiter: 35)],
        const [],
      );

      expect(summary.fuelCost, 1400);
    });

    test('ครั้งที่เข้าอู่โดยไม่ได้กรอกค่าใช้จ่าย ไม่ถูกนับเป็นจำนวนครั้ง', () {
      final summary = summarizeExpenses(
        const [],
        [
          _service(id: 's1', dayOffset: 0, odometer: 10000, cost: 500),
          _service(id: 's2', dayOffset: 10, odometer: 10500),
        ],
      );

      expect(summary.serviceCost, 500);
      expect(summary.serviceCount, 1);
    });

    test('ระยะทางนับจากเลขไมล์ต่ำสุดถึงสูงสุดของทั้งสองแหล่ง', () {
      final summary = summarizeExpenses(
        [_fuel(id: 'a', dayOffset: 0, odometer: 10000, totalCost: 1000)],
        // เข้าอู่ที่เลขไมล์สูงกว่าการเติมน้ำมันครั้งสุดท้าย
        [_service(id: 's1', dayOffset: 30, odometer: 12000, cost: 1000)],
      );

      expect(summary.distanceKm, 2000);
      expect(summary.perKm, 1.0);
    });

    test('ยังไม่รู้ระยะทาง ต้องไม่หารด้วยศูนย์', () {
      final summary = summarizeExpenses(
        [_fuel(id: 'a', dayOffset: 0, odometer: 10000, totalCost: 1000)],
        const [],
      );

      expect(summary.distanceKm, 0);
      expect(summary.perKm, isNull);
    });

    test('เฉลี่ยต่อเดือนหารด้วยจำนวนเดือนที่ครอบคลุม รวมเดือนที่ไม่ได้จ่าย', () {
      final summary = summarizeExpenses(
        [
          _fuel(id: 'a', dayOffset: 0, odometer: 10000, totalCost: 1000),
          _fuel(id: 'b', dayOffset: 90, odometer: 13000, totalCost: 3000),
        ],
        const [],
      );

      // ม.ค. ถึง เม.ย. = 4 เดือน แม้ ก.พ./มี.ค. จะไม่ได้จ่ายอะไร
      expect(summary.monthCount, 4);
      expect(summary.perMonth, 1000);
    });

    test('ไม่มีข้อมูลเลย ถือว่ายังไม่มีอะไรให้สรุป', () {
      final summary = summarizeExpenses(const [], const []);

      expect(summary.hasData, isFalse);
      expect(summary.perMonth, isNull);
      expect(summary.perKm, isNull);
    });
  });
}
