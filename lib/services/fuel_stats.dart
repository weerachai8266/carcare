import '../models/fuel_entry.dart';

/// อัตราสิ้นเปลืองของช่วงหนึ่ง = ระยะทางที่วิ่งได้ต่อน้ำมันที่เติมเข้าไปในช่วงนั้น
class FuelSegment {
  /// การเติมที่ปิดท้ายช่วงนี้ (เติมเต็มถัง)
  final FuelEntry entry;

  /// เลขไมล์ตอนเติมเต็มถังครั้งก่อน
  final double startOdometer;

  final double distanceKm;

  /// น้ำมันที่เติมทั้งหมดหลังจากเต็มถังครั้งก่อน จนถึงครั้งนี้
  final double liters;

  /// ค่าน้ำมันรวมของช่วง — null ถ้ามีบางรายการไม่ได้กรอกราคา
  final double? cost;

  const FuelSegment({
    required this.entry,
    required this.startOdometer,
    required this.distanceKm,
    required this.liters,
    this.cost,
  });

  double get kmPerLiter => distanceKm / liters;

  double get litersPer100Km => liters / distanceKm * 100;

  double? get costPerKm => cost == null ? null : cost! / distanceKm;
}

/// สรุปภาพรวมของรถหนึ่งคัน
class FuelSummary {
  /// ระยะทางรวมของช่วงที่คำนวณได้ (ไม่ใช่ระยะทางทั้งหมดของรถ)
  final double distanceKm;

  /// น้ำมันรวมเฉพาะช่วงที่คำนวณได้
  final double liters;

  /// ค่าน้ำมันรวมของ "ทุกรายการ" ที่กรอกราคาไว้ ใช้ดูค่าใช้จ่ายจริง
  final double totalCost;

  /// น้ำมันรวมของทุกรายการ ใช้คู่กับ [totalCost] หาราคาเฉลี่ยต่อลิตร
  final double totalLiters;

  /// ระยะทางเฉพาะช่วงที่รู้ค่าน้ำมันครบทุกรายการ
  final double costedDistanceKm;

  /// ค่าน้ำมันของช่วงตาม [costedDistanceKm]
  ///
  /// แยกจาก [totalCost] เพราะเอาค่าน้ำมันรวมมาหารระยะทางตรง ๆ ไม่ได้
  /// ถังแรกที่เติมยังไม่ได้ถูกใช้วิ่งในระยะที่วัดได้ ตัวหารกับตัวตั้งจึงคนละช่วงกัน
  final double costedAmount;

  final int entryCount;
  final double? bestKmPerLiter;
  final double? worstKmPerLiter;

  const FuelSummary({
    required this.distanceKm,
    required this.liters,
    required this.totalCost,
    required this.totalLiters,
    required this.costedDistanceKm,
    required this.costedAmount,
    required this.entryCount,
    this.bestKmPerLiter,
    this.worstKmPerLiter,
  });

  /// เฉลี่ยแบบถ่วงน้ำหนักด้วยระยะทาง ไม่ใช่เฉลี่ยของค่าเฉลี่ยรายช่วง
  double? get avgKmPerLiter => liters > 0 ? distanceKm / liters : null;

  double? get avgLitersPer100Km => distanceKm > 0 ? liters / distanceKm * 100 : null;

  double? get avgPricePerLiter => totalLiters > 0 ? totalCost / totalLiters : null;

  /// ค่าน้ำมันต่อกิโลเมตร คิดเฉพาะช่วงที่รู้ทั้งระยะทางและค่าน้ำมัน
  double? get costPerKm =>
      costedDistanceKm > 0 ? costedAmount / costedDistanceKm : null;

  bool get hasConsumptionData => liters > 0 && distanceKm > 0;
}

/// คำนวณอัตราสิ้นเปลืองด้วยวิธี "เต็มถังถึงเต็มถัง"
///
/// วิธีนี้เชื่อถือได้เพราะระดับน้ำมันในถังตอนต้นและตอนจบช่วงเท่ากันพอดี
/// น้ำมันที่เติมระหว่างทางจึงเท่ากับน้ำมันที่ใช้ไปจริง
///
/// ข้ามช่วงที่คำนวณไม่ได้ในกรณีต่อไปนี้:
/// - มีรายการที่ผู้ใช้ทำเครื่องหมายว่าเติมครั้งก่อนแล้วลืมบันทึก ([FuelEntry.missedEntries])
/// - เลขไมล์ไม่เดินหน้า (กรอกผิดหรือซ้ำ)
///
/// [entries] ต้องเรียงตามเลขไมล์จากน้อยไปมาก
List<FuelSegment> computeSegments(List<FuelEntry> entries) {
  final segments = <FuelSegment>[];

  FuelEntry? start; // การเติมเต็มถังครั้งล่าสุดที่ใช้เป็นจุดตั้งต้นได้
  var litersSinceStart = 0.0;
  var costSinceStart = 0.0;
  var costKnown = true;
  var brokenChain = false; // มีรายการที่ทำให้ช่วงนี้เชื่อถือไม่ได้

  for (final entry in entries) {
    if (start != null) {
      litersSinceStart += entry.liters;
      final cost = entry.effectiveTotalCost;
      if (cost == null) {
        costKnown = false;
      } else {
        costSinceStart += cost;
      }
      if (entry.missedEntries) brokenChain = true;
    }

    if (!entry.isFullTank) continue;

    // เติมเต็มถัง = ปิดช่วงเดิม (ถ้าใช้ได้) แล้วเริ่มช่วงใหม่
    if (start != null && !brokenChain) {
      final distance = entry.odometer - start.odometer;
      if (distance > 0 && litersSinceStart > 0) {
        segments.add(FuelSegment(
          entry: entry,
          startOdometer: start.odometer,
          distanceKm: distance,
          liters: litersSinceStart,
          cost: costKnown ? costSinceStart : null,
        ));
      }
    }

    start = entry;
    litersSinceStart = 0;
    costSinceStart = 0;
    costKnown = true;
    // รายการที่บอกว่าลืมบันทึกครั้งก่อน กระทบเฉพาะช่วงที่จบที่มัน ช่วงถัดไปเริ่มนับใหม่ได้
    brokenChain = false;
  }

  return segments;
}

/// สรุปภาพรวมจากรายการเติมทั้งหมด
///
/// [entries] ต้องเรียงตามเลขไมล์จากน้อยไปมาก
FuelSummary summarize(List<FuelEntry> entries) {
  final segments = computeSegments(entries);

  var distance = 0.0;
  var liters = 0.0;
  var costedDistance = 0.0;
  var costedAmount = 0.0;
  double? best;
  double? worst;
  for (final s in segments) {
    distance += s.distanceKm;
    liters += s.liters;
    if (s.cost != null) {
      costedDistance += s.distanceKm;
      costedAmount += s.cost!;
    }
    final kpl = s.kmPerLiter;
    if (best == null || kpl > best) best = kpl;
    if (worst == null || kpl < worst) worst = kpl;
  }

  var totalCost = 0.0;
  var totalLiters = 0.0;
  for (final e in entries) {
    totalLiters += e.liters;
    totalCost += e.effectiveTotalCost ?? 0;
  }

  return FuelSummary(
    distanceKm: distance,
    liters: liters,
    totalCost: totalCost,
    totalLiters: totalLiters,
    costedDistanceKm: costedDistance,
    costedAmount: costedAmount,
    entryCount: entries.length,
    bestKmPerLiter: best,
    worstKmPerLiter: worst,
  );
}

/// ระยะทางเฉลี่ยต่อวันจากประวัติการเติมน้ำมัน
///
/// ใช้ประเมินว่ารายการบำรุงรักษาที่นับตามระยะทางจะครบกำหนดวันไหน
/// คืน null ถ้าข้อมูลน้อยเกินไปจนประเมินไม่ได้
///
/// [entries] ต้องเรียงตามเลขไมล์จากน้อยไปมาก
double? avgKmPerDay(List<FuelEntry> entries) {
  if (entries.length < 2) return null;

  final first = entries.first;
  final last = entries.last;
  final km = last.odometer - first.odometer;
  final days = last.dateTime.difference(first.dateTime).inDays;
  if (km <= 0 || days <= 0) return null;

  return km / days;
}
