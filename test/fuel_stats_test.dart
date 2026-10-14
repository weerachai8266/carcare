import 'package:carcare/models/fuel_entry.dart';
import 'package:carcare/services/fuel_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// วันที่ 1 ม.ค. 2025 + [dayOffset] วัน
int _day(int dayOffset) =>
    DateTime(2025, 1, 1).add(Duration(days: dayOffset)).millisecondsSinceEpoch;

FuelEntry _entry({
  required String id,
  required int dayOffset,
  required double odometer,
  required double liters,
  double? pricePerLiter,
  double? totalCost,
  bool isFullTank = true,
  bool missedEntries = false,
}) {
  return FuelEntry(
    id: id,
    vehicleId: 'v1',
    date: _day(dayOffset),
    odometer: odometer,
    liters: liters,
    pricePerLiter: pricePerLiter,
    totalCost: totalCost,
    isFullTank: isFullTank,
    missedEntries: missedEntries,
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  group('computeSegments', () {
    test('เติมครั้งแรกยังคำนวณไม่ได้ ต้องมีเต็มถังสองครั้ง', () {
      final segments = computeSegments([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
      ]);
      expect(segments, isEmpty);
    });

    test('เต็มถังสองครั้งติดกัน คิดจากระยะทางหารน้ำมันครั้งหลัง', () {
      final segments = computeSegments([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
        _entry(id: 'b', dayOffset: 10, odometer: 10500, liters: 40),
      ]);

      expect(segments, hasLength(1));
      expect(segments.first.distanceKm, 500);
      expect(segments.first.liters, 40);
      expect(segments.first.kmPerLiter, 12.5);
      expect(segments.first.entry.id, 'b');
    });

    test('เติมไม่เต็มถังคั่นกลาง ต้องรวมลิตรเข้าช่วงเดียวกัน', () {
      final segments = computeSegments([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
        _entry(id: 'b', dayOffset: 5, odometer: 10200, liters: 15, isFullTank: false),
        _entry(id: 'c', dayOffset: 10, odometer: 10500, liters: 25),
      ]);

      expect(segments, hasLength(1));
      expect(segments.first.distanceKm, 500);
      expect(segments.first.liters, 40);
      expect(segments.first.kmPerLiter, 12.5);
    });

    test('รายการที่ลืมบันทึกครั้งก่อน ทำให้ข้ามเฉพาะช่วงที่จบที่มัน', () {
      final segments = computeSegments([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
        _entry(id: 'b', dayOffset: 10, odometer: 10600, liters: 40, missedEntries: true),
        _entry(id: 'c', dayOffset: 20, odometer: 11100, liters: 40),
      ]);

      expect(segments, hasLength(1));
      expect(segments.first.entry.id, 'c');
      expect(segments.first.startOdometer, 10600);
      expect(segments.first.kmPerLiter, 12.5);
    });

    test('เลขไมล์ไม่เดินหน้า ข้ามช่วงนั้นไป', () {
      final segments = computeSegments([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
        _entry(id: 'b', dayOffset: 1, odometer: 10000, liters: 5),
      ]);
      expect(segments, isEmpty);
    });

    test('ค่าน้ำมันของช่วงรวมทุกครั้งที่เติมในช่วงนั้น', () {
      final segments = computeSegments([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40, totalCost: 1400),
        _entry(
          id: 'b',
          dayOffset: 5,
          odometer: 10200,
          liters: 15,
          totalCost: 525,
          isFullTank: false,
        ),
        _entry(id: 'c', dayOffset: 10, odometer: 10500, liters: 25, totalCost: 875),
      ]);

      expect(segments, hasLength(1));
      expect(segments.first.cost, 1400);
      expect(segments.first.costPerKm, 2.8);
    });

    test('ถ้ามีรายการที่ไม่ได้กรอกราคา ค่าน้ำมันของช่วงเป็น null', () {
      final segments = computeSegments([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40, totalCost: 1400),
        _entry(id: 'b', dayOffset: 5, odometer: 10200, liters: 15, isFullTank: false),
        _entry(id: 'c', dayOffset: 10, odometer: 10500, liters: 25, totalCost: 875),
      ]);

      expect(segments, hasLength(1));
      expect(segments.first.cost, isNull);
      expect(segments.first.costPerKm, isNull);
    });
  });

  group('summarize', () {
    test('เฉลี่ยถ่วงน้ำหนักด้วยระยะทาง ไม่ใช่เฉลี่ยของค่าเฉลี่ยรายช่วง', () {
      // ช่วงแรก 12.5 กม./ล. (500 กม.), ช่วงสอง 10 กม./ล. (100 กม.)
      // เฉลี่ยรวม = 600 / 50 = 12 ไม่ใช่ (12.5 + 10) / 2 = 11.25
      final summary = summarize([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
        _entry(id: 'b', dayOffset: 10, odometer: 10500, liters: 40),
        _entry(id: 'c', dayOffset: 15, odometer: 10600, liters: 10),
      ]);

      expect(summary.distanceKm, 600);
      expect(summary.liters, 50);
      expect(summary.avgKmPerLiter, 12);
      expect(summary.bestKmPerLiter, 12.5);
      expect(summary.worstKmPerLiter, 10);
    });

    test('ค่าน้ำมันรวมนับทุกรายการ แม้รายการนั้นจะคำนวณอัตราสิ้นเปลืองไม่ได้', () {
      final summary = summarize([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40, pricePerLiter: 35),
        _entry(id: 'b', dayOffset: 10, odometer: 10500, liters: 40, pricePerLiter: 36),
      ]);

      expect(summary.totalLiters, 80);
      expect(summary.totalCost, closeTo(1400 + 1440, 0.001));
      expect(summary.avgPricePerLiter, closeTo(35.5, 0.001));
      expect(summary.entryCount, 2);
    });

    test('ค่าน้ำมันต่อกิโลเมตรคิดเฉพาะช่วงที่วัดได้ ไม่เอาถังแรกมารวม', () {
      // ถังแรก 1,400 บ. ยังไม่ได้ถูกใช้วิ่งในระยะที่วัดได้
      // ต้องคิดจาก 1,440 / 500 = 2.88 ไม่ใช่ 2,840 / 500 = 5.68
      final summary = summarize([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40, pricePerLiter: 35),
        _entry(id: 'b', dayOffset: 10, odometer: 10500, liters: 40, pricePerLiter: 36),
      ]);

      expect(summary.costPerKm, closeTo(2.88, 0.001));
      expect(summary.totalCost, closeTo(2840, 0.001));
    });

    test('ช่วงที่ไม่รู้ราคา ไม่ถูกนำมาคิดค่าน้ำมันต่อกิโลเมตร', () {
      final summary = summarize([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
        _entry(id: 'b', dayOffset: 10, odometer: 10500, liters: 40),
        _entry(id: 'c', dayOffset: 20, odometer: 11000, liters: 40, totalCost: 1600),
      ]);

      // นับเฉพาะช่วง b→c ที่รู้ราคา = 1,600 / 500
      expect(summary.costPerKm, closeTo(3.2, 0.001));
    });

    test('ไม่มีข้อมูลเลย ไม่พัง', () {
      final summary = summarize([]);
      expect(summary.hasConsumptionData, isFalse);
      expect(summary.avgKmPerLiter, isNull);
      expect(summary.costPerKm, isNull);
    });
  });

  group('avgKmPerDay', () {
    test('คิดจากรายการแรกถึงรายการสุดท้าย', () {
      final avg = avgKmPerDay([
        _entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40),
        _entry(id: 'b', dayOffset: 10, odometer: 10500, liters: 40),
      ]);
      expect(avg, 50);
    });

    test('ข้อมูลไม่พอ คืน null', () {
      expect(avgKmPerDay([]), isNull);
      expect(
        avgKmPerDay([_entry(id: 'a', dayOffset: 0, odometer: 10000, liters: 40)]),
        isNull,
      );
    });
  });
}
