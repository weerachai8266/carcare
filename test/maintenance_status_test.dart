import 'package:carcare/models/maintenance_task.dart';
import 'package:carcare/models/service_record.dart';
import 'package:carcare/models/vehicle.dart';
import 'package:carcare/services/maintenance_status.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2025, 6, 1);

Vehicle _vehicle({double initialOdo = 0, DateTime? createdAt}) => Vehicle(
      id: 'v1',
      name: 'รถบ้าน',
      initialOdo: initialOdo,
      createdAt: (createdAt ?? DateTime(2024, 1, 1)).millisecondsSinceEpoch,
      updatedAt: 0,
    );

MaintenanceTask _task({
  double? intervalKm,
  int? intervalMonths,
  double notifyKmBefore = 500,
  int notifyDaysBefore = 7,
}) =>
    MaintenanceTask(
      id: 't1',
      vehicleId: 'v1',
      name: 'เปลี่ยนถ่ายน้ำมันเครื่อง',
      intervalKm: intervalKm,
      intervalMonths: intervalMonths,
      notifyKmBefore: notifyKmBefore,
      notifyDaysBefore: notifyDaysBefore,
      createdAt: 0,
      updatedAt: 0,
    );

ServiceRecord _record({required DateTime date, required double odometer}) => ServiceRecord(
      id: 's1',
      vehicleId: 'v1',
      taskId: 't1',
      title: 'เปลี่ยนถ่ายน้ำมันเครื่อง',
      date: date.millisecondsSinceEpoch,
      odometer: odometer,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  group('เกณฑ์ระยะทาง', () {
    test('นับจากเลขไมล์ครั้งล่าสุดที่ทำ', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalKm: 10000),
        lastRecord: _record(date: DateTime(2025, 1, 1), odometer: 50000),
        currentOdometer: 53000,
        now: _now,
      );

      expect(status.dueOdometer, 60000);
      expect(status.remainingKm, 7000);
      expect(status.level, DueLevel.ok);
    });

    test('เข้าระยะเตือนล่วงหน้าแล้วขึ้นใกล้ครบกำหนด', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalKm: 10000, notifyKmBefore: 500),
        lastRecord: _record(date: DateTime(2025, 1, 1), odometer: 50000),
        currentOdometer: 59600,
        now: _now,
      );

      expect(status.remainingKm, 400);
      expect(status.level, DueLevel.dueSoon);
    });

    test('เลยเลขไมล์ที่ครบกำหนดแล้วขึ้นเลยกำหนด', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalKm: 10000),
        lastRecord: _record(date: DateTime(2025, 1, 1), odometer: 50000),
        currentOdometer: 60300,
        now: _now,
      );

      expect(status.remainingKm, -300);
      expect(status.level, DueLevel.overdue);
      expect(status.summaryLabel, contains('เกิน 300 กม.'));
    });
  });

  group('เกณฑ์เวลา', () {
    test('นับเดือนจากวันที่ทำครั้งล่าสุด', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalMonths: 6),
        lastRecord: _record(date: DateTime(2025, 3, 1), odometer: 50000),
        currentOdometer: 50000,
        now: _now,
      );

      expect(status.dueDate, DateTime(2025, 9, 1));
      expect(status.remainingDays, 92);
      expect(status.level, DueLevel.ok);
    });

    test('บวกเดือนแล้ววันต้องไม่ล้นเดือน', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalMonths: 1),
        lastRecord: _record(date: DateTime(2025, 1, 31), odometer: 50000),
        currentOdometer: 50000,
        now: _now,
      );

      expect(status.dueDate, DateTime(2025, 2, 28));
    });

    test('วันครบกำหนดคือวันนี้ ถือว่าเลยกำหนดแล้ว', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalMonths: 12),
        lastRecord: _record(date: DateTime(2024, 6, 1), odometer: 50000),
        currentOdometer: 50000,
        now: _now,
      );

      expect(status.remainingDays, 0);
      expect(status.level, DueLevel.overdue);
    });
  });

  group('กำหนดทั้งระยะทางและเวลา', () {
    test('ยึดเกณฑ์ที่ถึงกำหนดก่อน', () {
      // ระยะทางยังเหลือเยอะ แต่เวลาเลยมาแล้ว
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalKm: 10000, intervalMonths: 6),
        lastRecord: _record(date: DateTime(2024, 6, 1), odometer: 50000),
        currentOdometer: 51000,
        now: _now,
      );

      expect(status.remainingKm, 9000);
      expect(status.level, DueLevel.overdue);
    });
  });

  test('ยังไม่เคยบันทึกว่าทำ ให้นับจากวันที่กับเลขไมล์เริ่มใช้รถ', () {
    final status = computeStatus(
      vehicle: _vehicle(initialOdo: 20000, createdAt: DateTime(2025, 1, 1)),
      task: _task(intervalKm: 10000),
      lastRecord: null,
      currentOdometer: 25000,
      now: _now,
    );

    expect(status.neverServiced, isTrue);
    expect(status.baselineOdometer, 20000);
    expect(status.dueOdometer, 30000);
    expect(status.remainingKm, 5000);
  });

  test('ไม่ได้ตั้งรอบเลย เตือนไม่ได้', () {
    final status = computeStatus(
      vehicle: _vehicle(),
      task: _task(),
      currentOdometer: 50000,
      now: _now,
    );

    expect(status.level, DueLevel.noInterval);
    expect(status.summaryLabel, 'ไม่ได้ตั้งรอบ');
  });

  group('วันที่คาดว่าจะครบกำหนด', () {
    test('แปลงระยะทางที่เหลือเป็นวันด้วยอัตราการใช้รถ', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalKm: 10000),
        lastRecord: _record(date: DateTime(2025, 1, 1), odometer: 50000),
        currentOdometer: 59000,
        avgKmPerDay: 50,
        now: _now,
      );

      // เหลือ 1,000 กม. ที่ 50 กม./วัน = 20 วัน
      expect(status.estimatedDueDate, DateTime(2025, 6, 21));
    });

    test('เอาอันที่มาถึงก่อนระหว่างเกณฑ์เวลากับระยะทาง', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalKm: 10000, intervalMonths: 6),
        lastRecord: _record(date: DateTime(2025, 3, 1), odometer: 50000),
        currentOdometer: 59000,
        avgKmPerDay: 50,
        now: _now,
      );

      // ระยะทางจะถึงกำหนด 21 มิ.ย. ส่วนเวลาถึง 1 ก.ย.
      expect(status.estimatedDueDate, DateTime(2025, 6, 21));
    });

    test('ไม่มีอัตราการใช้รถ ก็ยังใช้เกณฑ์เวลาได้', () {
      final status = computeStatus(
        vehicle: _vehicle(),
        task: _task(intervalKm: 10000, intervalMonths: 6),
        lastRecord: _record(date: DateTime(2025, 3, 1), odometer: 50000),
        currentOdometer: 59000,
        now: _now,
      );

      expect(status.estimatedDueDate, DateTime(2025, 9, 1));
    });
  });

  test('เรียงรายการโดยเอาที่เร่งด่วนที่สุดขึ้นก่อน', () {
    final vehicle = _vehicle();
    final ok = MaintenanceTask(
      id: 'ok',
      vehicleId: 'v1',
      name: 'ยังไม่ถึง',
      intervalKm: 10000,
      createdAt: 0,
      updatedAt: 0,
    );
    final soon = MaintenanceTask(
      id: 'soon',
      vehicleId: 'v1',
      name: 'ใกล้ครบ',
      intervalKm: 1200,
      createdAt: 0,
      updatedAt: 0,
    );
    final late = MaintenanceTask(
      id: 'late',
      vehicleId: 'v1',
      name: 'เลยกำหนด',
      intervalKm: 500,
      createdAt: 0,
      updatedAt: 0,
    );

    final statuses = computeStatuses(
      vehicle: vehicle,
      tasks: [ok, soon, late],
      latestRecords: const {},
      currentOdometer: 1000,
      now: _now,
    );

    expect(statuses.map((s) => s.task.id).toList(), ['late', 'soon', 'ok']);
  });
}
