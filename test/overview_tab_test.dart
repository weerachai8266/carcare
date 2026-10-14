import 'package:carcare/models/fuel_entry.dart';
import 'package:carcare/models/service_record.dart';
import 'package:carcare/models/vehicle.dart';
import 'package:carcare/services/expense_stats.dart';
import 'package:carcare/services/fuel_stats.dart';
import 'package:carcare/services/maintenance_status.dart';
import 'package:carcare/ui/overview_tab.dart';
import 'package:carcare/ui/vehicle_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// เทสต์นี้เรนเดอร์แท็บภาพรวมของจริง เพราะข้อผิดพลาดของกราฟ (เช่นค่าที่ทำให้
/// แกนคำนวณไม่ได้ หรือ stack item ที่ย้อนหลัง) ไม่ขึ้นตอน analyze แต่โยน
/// exception ตอนวาดเท่านั้น — ต้อง pump จริงถึงจะเจอ

int _day(int dayOffset) =>
    DateTime(2025, 1, 1).add(Duration(days: dayOffset)).millisecondsSinceEpoch;

FuelEntry _fuel({
  required String id,
  required int dayOffset,
  required double odometer,
  double liters = 40,
  double? totalCost,
}) {
  return FuelEntry(
    id: id,
    vehicleId: 'v1',
    date: _day(dayOffset),
    odometer: odometer,
    liters: liters,
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

VehicleData _data({
  required List<FuelEntry> entries,
  required List<ServiceRecord> records,
}) {
  const vehicle = Vehicle(id: 'v1', name: 'รถทดสอบ', createdAt: 0, updatedAt: 0);

  return VehicleData(
    vehicle: vehicle,
    odometer: entries.isEmpty ? 0 : entries.last.odometer,
    entries: entries,
    segments: computeSegments(entries),
    summary: summarize(entries),
    avgKmPerDay: avgKmPerDay(entries),
    tasks: const [],
    statuses: const <TaskStatus>[],
    records: records,
    expenses: summarizeExpenses(entries, records),
    months: monthlyExpenses(entries, records),
  );
}

Future<void> _pumpOverview(WidgetTester tester, VehicleData data) async {
  // จอเทสต์ปริยายสูงแค่ 600 พิกเซล ซึ่งเตี้ยกว่าหมดที่หน้านี้ยาว
  // ListView สร้างเฉพาะสิ่งที่อยู่ในจอ ของที่อยู่ใต้ fold จึงหาไม่เจอทั้งที่โค้ดถูก
  // ตั้งจอให้สูงพอเห็นทั้งหน้า จะได้ตรวจได้โดยไม่ต้องไล่ scroll ทีละจุด
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: OverviewTab(data: data, onChanged: () {})),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('มีค่าน้ำมันและค่าบำรุงรักษา แสดงยอดรวมทั้งสองส่วน', (tester) async {
    await _pumpOverview(
      tester,
      _data(
        entries: [
          _fuel(id: 'a', dayOffset: 0, odometer: 10000, totalCost: 1400),
          _fuel(id: 'b', dayOffset: 30, odometer: 10600, totalCost: 1600),
          _fuel(id: 'c', dayOffset: 60, odometer: 11200, totalCost: 1500),
        ],
        records: [
          _service(id: 's1', dayOffset: 20, odometer: 10400, cost: 2000),
          _service(id: 's2', dayOffset: 50, odometer: 11000, cost: 1000),
        ],
      ),
    );

    expect(find.text('ค่าใช้จ่าย'), findsOneWidget);
    expect(find.text('รวมทั้งหมด'), findsOneWidget);
    // 1400 + 1600 + 1500 + 2000 + 1000
    expect(find.text('7,500 บ.'), findsOneWidget);
    expect(find.text('ค่าน้ำมัน'), findsOneWidget);
    expect(find.text('4,500 บ.'), findsOneWidget);
    expect(find.text('ค่าบำรุงรักษา (2 ครั้ง)'), findsOneWidget);
    expect(find.text('3,000 บ.'), findsOneWidget);

    expect(find.text('ค่าใช้จ่ายรายเดือน'), findsOneWidget);
    expect(find.text('น้ำมัน'), findsOneWidget);
    expect(find.text('บำรุงรักษา'), findsOneWidget);
  });

  testWidgets('ป้ายเดือนบนแกนใส่ปีเฉพาะป้ายแรกกับตอนข้ามปี', (tester) async {
    // เคยพังจริง: ใส่ "มิ.ย. 2026" ทุกป้าย พอครบ 6 เดือนตัวหนังสือทับกันบนมือถือ
    await _pumpOverview(
      tester,
      _data(
        entries: [
          // พ.ย. 2024 ถึง ก.พ. 2025 — ข้ามปีหนึ่งครั้ง
          _fuel(id: 'a', dayOffset: -55, odometer: 9000, totalCost: 1000),
          _fuel(id: 'b', dayOffset: -25, odometer: 9500, totalCost: 1000),
          _fuel(id: 'c', dayOffset: 5, odometer: 10000, totalCost: 1000),
          _fuel(id: 'd', dayOffset: 35, odometer: 10500, totalCost: 1000),
        ],
        records: const [],
      ),
    );

    expect(find.text('พ.ย.'), findsOneWidget);
    expect(find.text('ธ.ค.'), findsOneWidget);
    expect(find.text('ม.ค.'), findsOneWidget);
    expect(find.text('ก.พ.'), findsOneWidget);

    // ปีขึ้นสองครั้งเท่านั้น: ป้ายแรก (2024) และตอนข้ามมา 2025
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    // ต้องไม่มีป้ายแบบเต็มที่รวมปีไว้ในบรรทัดเดียวหลงเหลือ
    expect(find.text('พ.ย. 2024'), findsNothing);
  });

  testWidgets('ยังไม่มีค่าใช้จ่ายเลย ต้องบอกวิธีเริ่มบันทึก ไม่ใช่โชว์ 0 บ.',
      (tester) async {
    await _pumpOverview(tester, _data(entries: const [], records: const []));

    expect(find.text('รวมทั้งหมด'), findsNothing);
    expect(find.textContaining('ยังไม่มีค่าใช้จ่ายที่บันทึกไว้'), findsOneWidget);
    expect(find.text('ค่าใช้จ่ายรายเดือน'), findsNothing);
  });

  testWidgets('เติมน้ำมันโดยไม่กรอกราคา ต้องไม่พังและไม่โชว์ค่าใช้จ่ายมั่ว',
      (tester) async {
    await _pumpOverview(
      tester,
      _data(
        entries: [
          _fuel(id: 'a', dayOffset: 0, odometer: 10000),
          _fuel(id: 'b', dayOffset: 30, odometer: 10600),
        ],
        records: const [],
      ),
    );

    expect(find.textContaining('ยังไม่มีค่าใช้จ่ายที่บันทึกไว้'), findsOneWidget);
    // อัตราสิ้นเปลืองยังคำนวณได้แม้ไม่รู้ราคา
    expect(find.text('อัตราสิ้นเปลืองเฉลี่ย'), findsOneWidget);
  });

  testWidgets('มีเฉพาะค่าบำรุงรักษา ไม่มีการเติมน้ำมันเลย ก็ต้องวาดกราฟได้',
      (tester) async {
    await _pumpOverview(
      tester,
      _data(
        entries: const [],
        records: [
          _service(id: 's1', dayOffset: 0, odometer: 10000, cost: 2500),
          _service(id: 's2', dayOffset: 40, odometer: 11000, cost: 800),
        ],
      ),
    );

    expect(find.text('รวมทั้งหมด'), findsOneWidget);
    // ยอดรวมกับค่าบำรุงรักษาเท่ากันพอดี เพราะไม่มีค่าน้ำมันเลย
    expect(find.text('3,300 บ.'), findsNWidgets(2));
    expect(find.text('ค่าน้ำมัน'), findsOneWidget);
    expect(find.text('0 บ.'), findsOneWidget);
    expect(find.text('ค่าใช้จ่ายรายเดือน'), findsOneWidget);
  });
}
