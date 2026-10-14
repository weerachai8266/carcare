import 'package:carcare/models/fuel_entry.dart';
import 'package:carcare/models/vehicle.dart';
import 'package:carcare/services/expense_stats.dart';
import 'package:carcare/services/fuel_stats.dart';
import 'package:carcare/services/maintenance_status.dart';
import 'package:carcare/ui/fuel_form_screen.dart';
import 'package:carcare/ui/vehicle_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// เทสต์การคำนวณสามช่อง (ลิตร · ราคา/ลิตร · ยอดรวม) ผ่านฟอร์มจริง
/// เพราะกติกา "ช่องไหนถูกคำนวณ" อยู่ที่ลำดับการแตะช่อง ซึ่งทดสอบแยกจาก UI ไม่ได้

VehicleData _emptyData() {
  const vehicle = Vehicle(id: 'v1', name: 'รถทดสอบ', createdAt: 0, updatedAt: 0);

  return VehicleData(
    vehicle: vehicle,
    odometer: 10000,
    entries: const <FuelEntry>[],
    segments: const [],
    summary: summarize(const []),
    avgKmPerDay: null,
    tasks: const [],
    statuses: const <TaskStatus>[],
    records: const [],
    expenses: summarizeExpenses(const [], const []),
    months: monthlyExpenses(const [], const []),
  );
}

Future<void> _pumpForm(WidgetTester tester, {FuelEntry? entry}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: FuelFormScreen(data: _emptyData(), entry: entry)),
  );
  await tester.pumpAndSettle();
}

final _liters = find.byKey(const Key('fuel-liters'));
final _price = find.byKey(const Key('fuel-price'));
final _total = find.byKey(const Key('fuel-total'));

String _textOf(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(find.descendant(of: field, matching: find.byType(TextField)))
        .controller!
        .text;

void main() {
  testWidgets('กรอกลิตรกับราคา แล้วยอดรวมคำนวณให้', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(_liters, '40');
    await tester.enterText(_price, '35');
    await tester.pump();

    expect(_textOf(tester, _total), '1400');
  });

  testWidgets('กรอกลิตรกับยอดรวม แล้วราคาต่อลิตรคำนวณให้', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(_liters, '40');
    await tester.enterText(_total, '1500');
    await tester.pump();

    expect(_textOf(tester, _price), '37.5');
  });

  testWidgets('กรอกราคากับยอดรวม แล้วจำนวนลิตรคำนวณให้', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(_price, '35');
    await tester.enterText(_total, '1400');
    await tester.pump();

    expect(_textOf(tester, _liters), '40');
  });

  testWidgets('แก้ช่องที่เคยถูกคำนวณ ระบบต้องย้ายไปคำนวณอีกช่องแทน', (tester) async {
    await _pumpForm(tester);

    // รอบแรก: ยอดรวมถูกคำนวณ
    await tester.enterText(_liters, '40');
    await tester.enterText(_price, '35');
    await tester.pump();
    expect(_textOf(tester, _total), '1400');

    // ผู้ใช้แก้ยอดรวมเอง — ห้ามถูกเขียนทับกลับเป็น 1400
    // ช่องที่ถูกคำนวณย้ายไปเป็นลิตร เพราะเป็นช่องที่แตะนานที่สุดในสามช่อง
    // (ลำดับตอนนี้: ยอดรวม → ราคา → ลิตร) 1500 ÷ 35 = 42.86
    await tester.enterText(_total, '1500');
    await tester.pump();

    expect(_textOf(tester, _total), '1500');
    expect(_textOf(tester, _price), '35');
    expect(_textOf(tester, _liters), '42.86');
  });

  testWidgets('อยากให้คำนวณช่องไหน แค่ไปแตะอีกสองช่องให้ล่าสุด', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(_liters, '40');
    await tester.enterText(_price, '35');
    await tester.enterText(_total, '1500');
    await tester.pump();
    // ตอนนี้ลิตรเป็นช่องที่ถูกคำนวณ
    expect(_textOf(tester, _liters), '42.86');

    // ยืนยันจำนวนลิตรว่า 40 จริง — พอแตะลิตรเป็นช่องล่าสุด
    // ช่องที่ถูกคำนวณจะย้ายไปเป็นราคาต่อลิตรแทน 1500 ÷ 40 = 37.5
    await tester.enterText(_liters, '40');
    await tester.pump();

    expect(_textOf(tester, _liters), '40');
    expect(_textOf(tester, _total), '1500');
    expect(_textOf(tester, _price), '37.5');
  });

  testWidgets('ลบตัวเลขออกกลางคัน ค่าที่คำนวณไว้ต้องไม่หายไปด้วย', (tester) async {
    await _pumpForm(tester);

    await tester.enterText(_liters, '40');
    await tester.enterText(_price, '35');
    await tester.pump();
    expect(_textOf(tester, _total), '1400');

    // ระหว่างพิมพ์แก้ราคา ผู้ใช้ลบจนว่างชั่วขณะ
    await tester.enterText(_price, '');
    await tester.pump();

    expect(_textOf(tester, _total), '1400');
    expect(_textOf(tester, _liters), '40');
  });

  testWidgets('เปิดแก้รายการที่มีลิตรกับยอดรวม ต้องคำนวณราคาให้ ไม่ทับยอดรวมเดิม',
      (tester) async {
    final entry = FuelEntry(
      id: 'f1',
      vehicleId: 'v1',
      date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      odometer: 10000,
      liters: 40,
      totalCost: 1400,
      createdAt: 0,
      updatedAt: 0,
    );

    await _pumpForm(tester, entry: entry);

    // ยังไม่ได้แตะอะไร ค่าที่โหลดมาต้องอยู่ครบ
    expect(_textOf(tester, _liters), '40');
    expect(_textOf(tester, _total), '1400');

    // พอแก้ลิตร ราคาต่อลิตรต้องเป็นช่องที่คำนวณ ไม่ใช่ยอดรวมที่ผู้ใช้กรอกไว้เอง
    await tester.enterText(_liters, '35');
    await tester.pump();

    expect(_textOf(tester, _total), '1400');
    expect(_textOf(tester, _price), '40');
  });
}
