import 'package:carcare/services/interval_stats.dart';
import 'package:flutter_test/flutter_test.dart';

int _day(int dayOffset) =>
    DateTime(2025, 1, 1).add(Duration(days: dayOffset)).millisecondsSinceEpoch;

ServiceObservation _obs({
  String task = 'oil',
  String taskName = 'เปลี่ยนถ่ายน้ำมันเครื่อง',
  String? category = 'เครื่องยนต์',
  String vehicle = 'v1',
  required double odometer,
  int dayOffset = 0,
}) {
  return ServiceObservation(
    taskKey: task,
    taskName: taskName,
    category: category,
    vehicleKey: vehicle,
    odometer: odometer,
    date: _day(dayOffset),
  );
}

void main() {
  group('observedIntervals', () {
    test('ทำครั้งเดียวยังวัดระยะไม่ได้', () {
      expect(observedIntervals([_obs(odometer: 10000)]), isEmpty);
    });

    test('วัดระยะห่างระหว่างสองครั้งติดกัน', () {
      final intervals = observedIntervals([
        _obs(odometer: 10000, dayOffset: 0),
        _obs(odometer: 20000, dayOffset: 180),
      ]);

      expect(intervals, hasLength(1));
      expect(intervals.first.km, 10000);
      expect(intervals.first.days, 180);
    });

    test('ไม่จับคู่ข้ามรถคนละคัน', () {
      final intervals = observedIntervals([
        _obs(vehicle: 'v1', odometer: 10000),
        _obs(vehicle: 'v2', odometer: 80000),
      ]);
      expect(intervals, isEmpty);
    });

    test('ไม่จับคู่ข้ามรายการคนละอย่าง', () {
      final intervals = observedIntervals([
        _obs(task: 'oil', odometer: 10000),
        _obs(task: 'brake', odometer: 15000),
      ]);
      expect(intervals, isEmpty);
    });

    test('เรียงตามเลขไมล์เองแม้ข้อมูลเข้ามาสลับลำดับ', () {
      final intervals = observedIntervals([
        _obs(odometer: 30000, dayOffset: 360),
        _obs(odometer: 10000, dayOffset: 0),
        _obs(odometer: 20000, dayOffset: 180),
      ]);

      expect(intervals.map((i) => i.km).toList(), [10000, 10000]);
    });

    test('ข้ามคู่ที่เลขไมล์ไม่เดินหน้า', () {
      final intervals = observedIntervals([
        _obs(odometer: 10000),
        _obs(odometer: 10000),
      ]);
      expect(intervals, isEmpty);
    });
  });

  group('summarizeIntervals', () {
    test('ข้อมูลน้อยกว่าเกณฑ์ขั้นต่ำถูกตัดทิ้ง', () {
      final summaries = summarizeIntervals([
        ObservedInterval(
          taskKey: 'oil',
          taskName: 'น้ำมันเครื่อง',
          vehicleKey: 'v1',
          km: 10000,
          days: 180,
        ),
      ]);
      expect(summaries, isEmpty);
    });

    test('ใช้มัธยฐาน ไม่ให้ค่าสุดโต่งดึงผลลัพธ์', () {
      // 9,000 / 10,000 / 10,000 / 11,000 / 100,000 → มัธยฐาน 10,000
      // ถ้าใช้ค่าเฉลี่ยจะได้ 28,000 ซึ่งไม่สะท้อนความจริง
      const kms = [9000.0, 10000.0, 10000.0, 11000.0, 100000.0];
      final intervals = [
        for (var i = 0; i < kms.length; i++)
          ObservedInterval(
            taskKey: 'oil',
            taskName: 'น้ำมันเครื่อง',
            category: 'เครื่องยนต์',
            vehicleKey: 'v$i',
            km: kms[i],
            days: 180,
          ),
      ];

      final summary = summarizeIntervals(intervals).single;
      expect(summary.medianKm, 10000);
      expect(summary.sampleCount, 5);
      expect(summary.vehicleCount, 5);
      expect(summary.p25Km, 10000);
      expect(summary.p75Km, 11000);
    });

    test('นับจำนวนคันแยกจากจำนวนตัวอย่าง', () {
      final intervals = [
        for (var i = 0; i < 4; i++)
          ObservedInterval(
            taskKey: 'oil',
            taskName: 'น้ำมันเครื่อง',
            vehicleKey: 'v1',
            km: 10000,
            days: 180,
          ),
      ];

      final summary = summarizeIntervals(intervals).single;
      expect(summary.sampleCount, 4);
      expect(summary.vehicleCount, 1);
    });
  });

  group('rankByCategory', () {
    IntervalSummary summary(String key, String category, int vehicles, int samples) {
      return IntervalSummary(
        taskKey: key,
        taskName: key,
        category: category,
        sampleCount: samples,
        vehicleCount: vehicles,
        medianKm: 10000,
        p25Km: 9000,
        p75Km: 11000,
        medianDays: 180,
      );
    }

    test('เรียงตามจำนวนคันก่อน แล้วค่อยจำนวนตัวอย่าง', () {
      final ranked = rankByCategory([
        summary('a', 'เครื่องยนต์', 5, 6),
        summary('b', 'เครื่องยนต์', 20, 25),
        summary('c', 'เครื่องยนต์', 20, 40),
      ]);

      expect(
        ranked['เครื่องยนต์']!.map((s) => s.taskKey).toList(),
        ['c', 'b', 'a'],
      );
    });

    test('แยกตามหมวด และตัดที่หมวดละ 10 อันดับ', () {
      final ranked = rankByCategory([
        for (var i = 0; i < 15; i++) summary('engine$i', 'เครื่องยนต์', 15 - i, 1),
        for (var i = 0; i < 3; i++) summary('brake$i', 'เบรก', 3 - i, 1),
      ]);

      expect(ranked.keys.toSet(), {'เครื่องยนต์', 'เบรก'});
      expect(ranked['เครื่องยนต์'], hasLength(10));
      expect(ranked['เบรก'], hasLength(3));
      expect(ranked['เครื่องยนต์']!.first.taskKey, 'engine0');
    });

    test('รายการที่ไม่มีหมวดไปรวมกันที่ "อื่น ๆ"', () {
      final ranked = rankByCategory([
        IntervalSummary(
          taskKey: 'x',
          taskName: 'x',
          sampleCount: 3,
          vehicleCount: 3,
          medianKm: 10000,
          p25Km: 9000,
          p75Km: 11000,
          medianDays: 180,
        ),
      ]);

      expect(ranked.keys.single, 'อื่น ๆ');
    });
  });

  group('percentile', () {
    test('คำนวณแบบเทียบสัดส่วนระหว่างสองค่าที่ขนาบอยู่', () {
      expect(percentile([10, 20, 30, 40], 0.5), 25);
      expect(percentile([10, 20, 30, 40], 0.25), 17.5);
      expect(percentile([10, 20, 30], 0.5), 20);
    });

    test('ลิสต์ว่างหรือมีค่าเดียวไม่พัง', () {
      expect(percentile([], 0.5), 0);
      expect(percentile([42], 0.9), 42);
    });
  });

  test('normalizeTaskName ยุบช่องว่างและตัวพิมพ์ให้เทียบกันได้', () {
    expect(normalizeTaskName('  Oil   Change '), 'oil change');
    expect(
      normalizeTaskName('เปลี่ยนถ่ายน้ำมันเครื่อง '),
      'เปลี่ยนถ่ายน้ำมันเครื่อง',
    );
  });
}
