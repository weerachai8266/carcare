import 'package:carcare/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('เปิดแอพแล้วเห็นหน้ารายการรถ', (WidgetTester tester) async {
    await tester.pumpWidget(const CarCareApp());
    // ไม่ pumpAndSettle เพราะหน้าแรกกำลังโหลดข้อมูลอยู่
    // และในเทสต์ไม่มี sqflite จริงให้เรียก
    await tester.pump();

    expect(find.text('รถของฉัน'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
