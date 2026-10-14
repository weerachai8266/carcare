import 'package:intl/intl.dart';

/// ตัวจัดรูปแบบตัวเลข/วันที่ให้ทั้งแอพแสดงผลเหมือนกันหมด
///
/// ปีแสดงเป็น ค.ศ. ให้ตรงกับปฏิทินเลือกวันที่ของระบบ ซึ่งเป็น ค.ศ. อย่างเดียว
/// (Flutter ยังไม่มีปฏิทินพุทธศักราชให้ใช้) ถ้าฝั่งเราแสดง พ.ศ. แต่ตอนกดเลือก
/// เป็น ค.ศ. คนกรอกจะไม่แน่ใจว่าที่บันทึกไปคือปีไหน — ผิดกันอยู่ 543 ปี
/// ส่วนชื่อเดือนเขียนเองแทนการพึ่ง locale data ของ intl เพื่อคุมรูปแบบให้คงที่
class Fmt {
  Fmt._();

  static final _int = NumberFormat('#,##0');
  static final _oneDecimal = NumberFormat('#,##0.0');
  static final _twoDecimal = NumberFormat('#,##0.00');

  static const _monthsShort = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  static const _monthsFull = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
    'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
  ];

  /// "1 มิ.ย. 2025"
  static String date(DateTime d) =>
      '${d.day} ${_monthsShort[d.month - 1]} ${d.year}';

  /// "1 มิถุนายน 2025"
  static String dateFull(DateTime d) =>
      '${d.day} ${_monthsFull[d.month - 1]} ${d.year}';

  /// "มิ.ย. 2025" ใช้ในทูลทิปและที่ที่มีที่ว่างพอ
  static String month(DateTime d) => '${_monthsShort[d.month - 1]} ${d.year}';

  /// "มิ.ย." สำหรับแกนกราฟที่มีหลายเดือนเรียงกัน
  ///
  /// แกนกราฟกว้างไม่พอจะใส่ปีทุกป้าย พอมี 6 เดือนแล้วตัวหนังสือจะทับกัน
  /// จึงแยกปีออกไปแสดงเฉพาะตอนที่มันเปลี่ยน
  static String monthShort(DateTime d) => _monthsShort[d.month - 1];

  /// "12,345 กม."
  static String km(double v) => '${_int.format(v.round())} กม.';

  static String kmNumber(double v) => _int.format(v.round());

  /// "40.5 ล."
  static String liters(double v) => '${_oneDecimal.format(v)} ล.';

  /// "1,234.50 บ."
  static String baht(double v) => '${_twoDecimal.format(v)} บ.';

  /// "1,234 บ." สำหรับยอดรวมที่ไม่ต้องละเอียดถึงสตางค์
  static String bahtRound(double v) => '${_int.format(v.round())} บ.';

  /// "12.5 กม./ล."
  static String kmPerLiter(double v) => '${_oneDecimal.format(v)} กม./ล.';

  static String number(double v, {int decimals = 1}) =>
      decimals == 0 ? _int.format(v) : _oneDecimal.format(v);

  /// ข้อความบอกว่านานแค่ไหนแล้ว เช่น "3 วันที่แล้ว", "2 เดือนที่แล้ว"
  static String ago(DateTime d, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final days = DateTime(at.year, at.month, at.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;

    if (days < 0) return 'อีก ${-days} วัน';
    if (days == 0) return 'วันนี้';
    if (days == 1) return 'เมื่อวาน';
    if (days < 30) return '$days วันที่แล้ว';
    if (days < 365) return '${days ~/ 30} เดือนที่แล้ว';
    return '${days ~/ 365} ปีที่แล้ว';
  }
}
