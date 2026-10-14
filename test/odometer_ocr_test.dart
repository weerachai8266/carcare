import 'package:carcare/services/odometer_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

/// เลือกตัวเลขจากข้อความที่ OCR อ่านได้ — ส่วนที่พลาดง่ายที่สุดของฟีเจอร์นี้
/// เพราะบนเรือนไมล์มีตัวเลขเต็มไปหมด ทั้งทริป อุณหภูมิ นาฬิกา และอัตราสิ้นเปลือง
void main() {
  double? best(List<String> lines, {double? current}) {
    final list = odometerCandidates(lines, currentOdometer: current);
    return list.isEmpty ? null : list.first.value;
  }

  test('หน้าปัดที่มีแต่เลขไมล์ อ่านตรง ๆ', () {
    expect(best(['96800 km']), 96800);
  });

  test('เลือกเลขไมล์รวม ไม่ใช่ทริปมิเตอร์', () {
    // ทริปมิเตอร์เป็นตัวหลอกที่เจอบ่อยที่สุด อยู่ติดกันและหน้าตาเหมือนกัน
    expect(
      best([
        'ODO 96800 km',
        'TRIP A 312.5 km',
      ]),
      96800,
    );
  });

  test('ไม่หลงนาฬิกากับอุณหภูมิ', () {
    expect(
      best([
        '10:42',
        '32°C',
        '96800',
      ]),
      96800,
    );
  });

  test('ไม่หลงอัตราสิ้นเปลืองกับระยะที่วิ่งได้', () {
    expect(
      best([
        '16.7 km/L',
        'RANGE 420 km',
        '96800 km',
      ]),
      96800,
    );
  });

  test('เลขไมล์ล่าสุดช่วยตัดสินเมื่อมีเลขหลายตัวที่หน้าตาเหมือนกัน', () {
    // 96850 คือค่าที่สมเหตุสมผล ส่วน 12345 เป็นเลขอื่นบนหน้าปัด
    expect(
      best(['12345', '96850'], current: 96800),
      96850,
    );
  });

  test('ตัวเลขที่น้อยกว่าเลขไมล์เดิม ถูกลดความสำคัญ', () {
    // เลขไมล์เดินหน้าอย่างเดียว 45000 จึงเป็นไปไม่ได้ถ้าเดิมอยู่ที่ 96800
    expect(
      best(['45000', '96900'], current: 96800),
      96900,
    );
  });

  test('เว้นวรรคหลักพันบนจอ LCD ต้องรวมเป็นเลขเดียว', () {
    expect(best(['96 800 km']), 96800);
  });

  test('คอมมาคั่นหลักพันก็อ่านได้', () {
    expect(best(['96,800']), 96800);
  });

  test('จุดคั่นหลักพันแบบยุโรป ไม่ใช่ทศนิยม', () {
    expect(best(['96.800']), 96800);
  });

  test('ไม่มีตัวเลขในรูป คืนลิสต์ว่าง', () {
    expect(odometerCandidates(['ไม่มีอะไรเลย', 'abc']), isEmpty);
  });

  test('ตัวเลขสั้นกว่าสามหลักไม่เข้ารายการเลย', () {
    // นาฬิกา อุณหภูมิ และเกียร์ ทำให้รายการที่ผู้ใช้ต้องเลือกรกโดยไม่จำเป็น
    final list = odometerCandidates([
      '10:42',
      '32 C',
      'D',
      '96800 km',
    ]);

    expect(list.map((c) => c.value), [96800]);
  });

  test('คืนทุกตัวที่เจอไว้ให้ผู้ใช้เลือกเอง ไม่ตัดทิ้ง', () {
    // OCR พลาดได้เสมอ ถ้าตัวที่คะแนนดีที่สุดผิด ผู้ใช้ต้องมีตัวอื่นให้เลือก
    final list = odometerCandidates([
      'ODO 96800 km',
      'TRIP A 312.5 km',
    ]);

    expect(list.map((c) => c.value), containsAll([96800.0, 312.5]));
    expect(list.first.value, 96800);
  });

  test('ตัวเลขเดียวกันอ่านเจอสองที่ ไม่ซ้ำในรายการ', () {
    final list = odometerCandidates(['96800', '96800 km']);

    expect(list.where((c) => c.value == 96800), hasLength(1));
  });

  test('เก็บบรรทัดดิบไว้ให้ผู้ใช้ดูว่าเลขมาจากตรงไหน', () {
    final list = odometerCandidates(['ODO 96800 km']);

    expect(list.first.source, 'ODO 96800 km');
  });
}
