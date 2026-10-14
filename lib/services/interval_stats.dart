/// สถิติ "คนอื่นเขาทำกันที่ระยะเท่าไร"
///
/// แนวคิด: รอบที่ผู้ใช้ตั้งไว้ในแอพเป็นแค่ความตั้งใจ ส่วนความจริงคือระยะห่าง
/// ระหว่างการทำสองครั้งติดกันของรายการเดียวกัน ตรรกะในไฟล์นี้จึงอ่านจาก
/// ประวัติที่ทำจริงเท่านั้น
///
/// ฟังก์ชันทั้งหมดเป็นฟังก์ชันบริสุทธิ์ที่รับ [ServiceObservation] เข้ามา
/// จึงใช้ได้ทั้งกับข้อมูลในเครื่องและกับแถวที่ดึงมาจากเซิร์ฟเวอร์ส่วนกลาง
library;

/// การบำรุงรักษาหนึ่งครั้งในรูปแบบที่ตัดข้อมูลส่วนตัวออกแล้ว
///
/// ตั้งใจไม่มี id ของผู้ใช้ ไม่มีทะเบียน ไม่มีชื่ออู่ เพราะข้อมูลชุดนี้
/// ถูกออกแบบมาให้รวมข้ามสมาชิกได้โดยไม่เปิดเผยว่าใครเป็นเจ้าของ
class ServiceObservation {
  /// คีย์ที่ใช้จับว่าเป็น "รายการเดียวกัน" ข้ามหลายครั้งที่ทำ
  /// ปกติคือ task_id ถ้าไม่ได้ผูกกับรายการก็ใช้ชื่อที่ทำให้เป็นมาตรฐานแล้ว
  final String taskKey;

  final String taskName;
  final String? category;

  /// รถคันไหน ใช้แยกว่าประวัติสองครั้งเป็นของรถคันเดียวกันหรือไม่
  final String vehicleKey;

  final double odometer;
  final int date;

  const ServiceObservation({
    required this.taskKey,
    required this.taskName,
    this.category,
    required this.vehicleKey,
    required this.odometer,
    required this.date,
  });
}

/// ระยะห่างระหว่างการทำสองครั้งติดกันของรายการเดียวกันในรถคันเดียวกัน
class ObservedInterval {
  final String taskKey;
  final String taskName;
  final String? category;
  final String vehicleKey;
  final double km;
  final int days;

  const ObservedInterval({
    required this.taskKey,
    required this.taskName,
    this.category,
    required this.vehicleKey,
    required this.km,
    required this.days,
  });
}

/// สรุปของรายการหนึ่งว่าคนทำกันที่ระยะประมาณเท่าไร
class IntervalSummary {
  final String taskKey;
  final String taskName;
  final String? category;

  /// จำนวนช่วงที่วัดได้ทั้งหมด (ไม่ใช่จำนวนครั้งที่ทำ)
  final int sampleCount;

  /// จำนวนคันที่มีข้อมูล ใช้กันไม่ให้รถคันเดียวที่ขยันบันทึกครองอันดับ
  final int vehicleCount;

  /// ใช้มัธยฐานแทนค่าเฉลี่ย เพราะข้อมูลจริงมีค่าสุดโต่ง
  /// (เช่น คนที่ปล่อยยาว 30,000 กม. หรือคนที่เปลี่ยนถี่ผิดปกติ) ที่ดึงค่าเฉลี่ยเพี้ยน
  final double medianKm;

  /// ช่วงที่คนส่วนใหญ่ทำกัน (เปอร์เซ็นไทล์ที่ 25 ถึง 75)
  final double p25Km;
  final double p75Km;

  final double medianDays;

  const IntervalSummary({
    required this.taskKey,
    required this.taskName,
    this.category,
    required this.sampleCount,
    required this.vehicleCount,
    required this.medianKm,
    required this.p25Km,
    required this.p75Km,
    required this.medianDays,
  });
}

/// หาระยะที่ทำจริงจากประวัติทั้งหมด
///
/// จับคู่เฉพาะการทำสองครั้งติดกันของรายการเดียวกันในรถคันเดียวกัน
/// ข้ามคู่ที่เลขไมล์ไม่เดินหน้า (กรอกผิดหรือกรอกซ้ำ)
List<ObservedInterval> observedIntervals(List<ServiceObservation> observations) {
  final byKey = <String, List<ServiceObservation>>{};
  for (final o in observations) {
    byKey.putIfAbsent('${o.vehicleKey}::${o.taskKey}', () => []).add(o);
  }

  final intervals = <ObservedInterval>[];
  for (final group in byKey.values) {
    group.sort((a, b) => a.odometer.compareTo(b.odometer));

    for (var i = 1; i < group.length; i++) {
      final previous = group[i - 1];
      final current = group[i];
      final km = current.odometer - previous.odometer;
      if (km <= 0) continue;

      final days = DateTime.fromMillisecondsSinceEpoch(current.date)
          .difference(DateTime.fromMillisecondsSinceEpoch(previous.date))
          .inDays;

      intervals.add(ObservedInterval(
        taskKey: current.taskKey,
        taskName: current.taskName,
        category: current.category,
        vehicleKey: current.vehicleKey,
        km: km,
        days: days < 0 ? 0 : days,
      ));
    }
  }
  return intervals;
}

/// สรุปเป็นรายการเดียวต่อหนึ่งงานบำรุงรักษา
///
/// [minSamples] ตัดรายการที่ข้อมูลน้อยเกินจะเชื่อถือได้ทิ้ง
List<IntervalSummary> summarizeIntervals(
  List<ObservedInterval> intervals, {
  int minSamples = 3,
}) {
  final byTask = <String, List<ObservedInterval>>{};
  for (final i in intervals) {
    byTask.putIfAbsent(i.taskKey, () => []).add(i);
  }

  final summaries = <IntervalSummary>[];
  for (final group in byTask.values) {
    if (group.length < minSamples) continue;

    final kms = group.map((i) => i.km).toList()..sort();
    final days = group.map((i) => i.days.toDouble()).toList()..sort();

    summaries.add(IntervalSummary(
      taskKey: group.first.taskKey,
      taskName: group.first.taskName,
      category: group.first.category,
      sampleCount: group.length,
      vehicleCount: group.map((i) => i.vehicleKey).toSet().length,
      medianKm: percentile(kms, 0.5),
      p25Km: percentile(kms, 0.25),
      p75Km: percentile(kms, 0.75),
      medianDays: percentile(days, 0.5),
    ));
  }
  return summaries;
}

/// จัดอันดับในแต่ละหมวด เอาหมวดละไม่เกิน [limit] รายการ
///
/// เรียงตามจำนวนคันที่มีข้อมูลก่อน แล้วค่อยดูจำนวนตัวอย่าง
/// เพื่อให้อันดับสะท้อน "รายการที่คนทำกันเยอะ" ไม่ใช่ "รายการที่รถคันเดียวทำบ่อย"
Map<String, List<IntervalSummary>> rankByCategory(
  List<IntervalSummary> summaries, {
  int limit = 10,
}) {
  final byCategory = <String, List<IntervalSummary>>{};
  for (final s in summaries) {
    byCategory.putIfAbsent(s.category ?? 'อื่น ๆ', () => []).add(s);
  }

  return {
    for (final entry in byCategory.entries)
      entry.key: (entry.value
            ..sort((a, b) {
              final byVehicles = b.vehicleCount.compareTo(a.vehicleCount);
              if (byVehicles != 0) return byVehicles;
              return b.sampleCount.compareTo(a.sampleCount);
            }))
          .take(limit)
          .toList(),
  };
}

/// เปอร์เซ็นไทล์แบบ linear interpolation จากลิสต์ที่เรียงจากน้อยไปมากแล้ว
double percentile(List<double> sorted, double fraction) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted.first;

  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];

  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

/// ทำให้ชื่อรายการที่ผู้ใช้พิมพ์เองเทียบกันได้ ใช้เป็น taskKey เมื่อไม่ได้ผูกกับรายการ
///
/// ตัดช่องว่างซ้ำและตัวพิมพ์ใหญ่เล็กออก เพื่อให้ "เปลี่ยนถ่ายน้ำมันเครื่อง"
/// กับ "เปลี่ยนถ่ายน้ำมันเครื่อง " นับเป็นงานเดียวกัน
String normalizeTaskName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
