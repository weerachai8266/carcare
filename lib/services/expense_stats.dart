import '../models/fuel_entry.dart';
import '../models/service_record.dart';

/// สรุปค่าใช้จ่ายของรถ โดยนับทั้งค่าน้ำมันและค่าบำรุงรักษาเข้าด้วยกัน
///
/// แยกไฟล์จาก fuel_stats.dart เพราะคนละคำถาม: ไฟล์นั้นตอบว่ารถกินน้ำมันเท่าไร
/// (ซึ่งต้องใช้เฉพาะการเติมเต็มถังที่ปิดช่วงได้) ส่วนไฟล์นี้ตอบว่าจ่ายไปเท่าไร
/// ซึ่งต้องนับทุกบาทที่บันทึกไว้ ไม่ว่าการเติมครั้งนั้นจะคำนวณอัตราสิ้นเปลืองได้หรือไม่

/// ค่าใช้จ่ายของเดือนหนึ่ง แยกเป็นค่าน้ำมันกับค่าบำรุงรักษา
class MonthlyExpense {
  final int year;
  final int month;
  final double fuelCost;
  final double serviceCost;

  /// น้ำมันที่เติมในเดือนนั้น ใช้แสดงในทูลทิปคู่กับค่าใช้จ่าย
  final double liters;

  const MonthlyExpense({
    required this.year,
    required this.month,
    this.fuelCost = 0,
    this.serviceCost = 0,
    this.liters = 0,
  });

  double get total => fuelCost + serviceCost;

  DateTime get monthStart => DateTime(year, month);

  MonthlyExpense _add({double fuel = 0, double service = 0, double liters = 0}) {
    return MonthlyExpense(
      year: year,
      month: month,
      fuelCost: fuelCost + fuel,
      serviceCost: serviceCost + service,
      liters: this.liters + liters,
    );
  }
}

/// ค่าใช้จ่ายรายเดือน เรียงจากเดือนเก่าไปใหม่
///
/// เดือนที่ไม่ได้จ่ายอะไรเลยจะถูกใส่เป็นศูนย์ไว้ ไม่ข้ามไป — ถ้าข้ามจะทำให้กราฟ
/// อ่านผิด เพราะแท่งที่ติดกันดูเหมือนเดือนติดกันทั้งที่ห่างกันครึ่งปี
List<MonthlyExpense> monthlyExpenses(
  List<FuelEntry> entries,
  List<ServiceRecord> records,
) {
  final buckets = <String, MonthlyExpense>{};

  String keyOf(DateTime d) => '${d.year}-${d.month}';

  MonthlyExpense bucketFor(DateTime d) =>
      buckets[keyOf(d)] ?? MonthlyExpense(year: d.year, month: d.month);

  for (final e in entries) {
    final d = e.dateTime;
    buckets[keyOf(d)] = bucketFor(d)._add(
      fuel: e.effectiveTotalCost ?? 0,
      liters: e.liters,
    );
  }

  for (final r in records) {
    final d = r.dateTime;
    buckets[keyOf(d)] = bucketFor(d)._add(service: r.cost ?? 0);
  }

  if (buckets.isEmpty) return const [];

  final filled = buckets.values.toList()
    ..sort((a, b) => a.monthStart.compareTo(b.monthStart));

  final result = <MonthlyExpense>[];
  var cursor = filled.first.monthStart;
  final last = filled.last.monthStart;
  var i = 0;

  while (!cursor.isAfter(last)) {
    if (i < filled.length && filled[i].monthStart == cursor) {
      result.add(filled[i]);
      i++;
    } else {
      result.add(MonthlyExpense(year: cursor.year, month: cursor.month));
    }
    // DateTime(y, 13) กลายเป็นมกราคมปีถัดไปให้เอง จึงไม่ต้องเช็กข้ามปีเอง
    cursor = DateTime(cursor.year, cursor.month + 1);
  }

  return result;
}

/// ยอดรวมค่าใช้จ่ายทั้งหมดของรถคันหนึ่ง
class ExpenseSummary {
  final double fuelCost;
  final double serviceCost;

  /// จำนวนครั้งที่เข้าอู่โดยมีการบันทึกค่าใช้จ่ายไว้
  final int serviceCount;

  /// ระยะทางที่ข้อมูลชุดนี้ครอบคลุม (เลขไมล์สูงสุด − ต่ำสุด ของทุกรายการ)
  ///
  /// ใช้ตัวนี้แทนระยะจากช่วงเติมเต็มถัง เพราะค่าบำรุงรักษาเกิดขึ้นตลอดการใช้รถ
  /// ไม่ได้ผูกกับการเติมน้ำมันเป็นช่วง ๆ
  final double distanceKm;

  /// จำนวนเดือนที่ข้อมูลครอบคลุม นับรวมเดือนที่ไม่ได้จ่ายอะไร
  final int monthCount;

  const ExpenseSummary({
    required this.fuelCost,
    required this.serviceCost,
    required this.serviceCount,
    required this.distanceKm,
    required this.monthCount,
  });

  double get total => fuelCost + serviceCost;

  /// ค่าใช้จ่ายรวมต่อกิโลเมตร — คืน null เมื่อยังไม่รู้ระยะทาง
  double? get perKm => distanceKm > 0 ? total / distanceKm : null;

  /// เฉลี่ยต่อเดือน — คืน null เมื่อยังไม่มีข้อมูล
  double? get perMonth => monthCount > 0 ? total / monthCount : null;

  bool get hasData => total > 0;
}

ExpenseSummary summarizeExpenses(
  List<FuelEntry> entries,
  List<ServiceRecord> records,
) {
  var fuelCost = 0.0;
  var serviceCost = 0.0;
  var serviceCount = 0;

  double? minOdo;
  double? maxOdo;

  void track(double odometer) {
    if (minOdo == null || odometer < minOdo!) minOdo = odometer;
    if (maxOdo == null || odometer > maxOdo!) maxOdo = odometer;
  }

  for (final e in entries) {
    fuelCost += e.effectiveTotalCost ?? 0;
    track(e.odometer);
  }

  for (final r in records) {
    final cost = r.cost;
    if (cost != null && cost > 0) {
      serviceCost += cost;
      serviceCount++;
    }
    // นับเลขไมล์ของทุกครั้งที่เข้าอู่ แม้ครั้งที่ไม่ได้กรอกค่าใช้จ่าย
    // เพราะมันก็ยังเป็นหลักฐานว่ารถวิ่งไปถึงระยะนั้นจริง
    track(r.odometer);
  }

  final months = monthlyExpenses(entries, records);

  return ExpenseSummary(
    fuelCost: fuelCost,
    serviceCost: serviceCost,
    serviceCount: serviceCount,
    distanceKm: (minOdo == null || maxOdo == null) ? 0 : maxOdo! - minOdo!,
    monthCount: months.length,
  );
}
