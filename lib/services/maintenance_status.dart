import '../models/maintenance_task.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';

/// ระดับความเร่งด่วนของรายการบำรุงรักษา
enum DueLevel {
  /// ยังไม่ตั้งรอบ จึงเตือนไม่ได้
  noInterval,

  /// ยังไม่ถึงเวลา
  ok,

  /// ใกล้ถึงกำหนดตามระยะเตือนล่วงหน้าที่ตั้งไว้
  dueSoon,

  /// เลยกำหนดแล้ว
  overdue,
}

/// สถานะครบกำหนดของรายการบำรุงรักษาหนึ่งรายการ ณ เวลาหนึ่ง
class TaskStatus {
  final MaintenanceTask task;

  /// ครั้งล่าสุดที่ทำ — null แปลว่ายังไม่เคยบันทึกไว้เลย
  final ServiceRecord? lastRecord;

  /// จุดตั้งต้นของการนับรอบ (ครั้งล่าสุดที่ทำ หรือวันที่/เลขไมล์เริ่มใช้รถ)
  final int baselineDate;
  final double baselineOdometer;

  /// เลขไมล์ที่ครบกำหนด — null ถ้าไม่ได้ตั้งรอบตามระยะทาง
  final double? dueOdometer;

  /// วันที่ครบกำหนด — null ถ้าไม่ได้ตั้งรอบตามเวลา
  final DateTime? dueDate;

  /// เหลืออีกกี่กิโลเมตร (ติดลบ = เลยมาแล้ว)
  final double? remainingKm;

  /// เหลืออีกกี่วัน (ติดลบ = เลยมาแล้ว)
  final int? remainingDays;

  /// วันที่คาดว่าจะถึงกำหนด รวมทั้งเกณฑ์ระยะทางที่แปลงเป็นวันด้วยอัตราการใช้รถ
  /// ใช้ตั้งการแจ้งเตือนล่วงหน้า — null ถ้าประเมินไม่ได้
  final DateTime? estimatedDueDate;

  final DueLevel level;

  const TaskStatus({
    required this.task,
    this.lastRecord,
    required this.baselineDate,
    required this.baselineOdometer,
    this.dueOdometer,
    this.dueDate,
    this.remainingKm,
    this.remainingDays,
    this.estimatedDueDate,
    required this.level,
  });

  bool get neverServiced => lastRecord == null;

  bool get needsAttention => level == DueLevel.overdue || level == DueLevel.dueSoon;

  /// ความคืบหน้าของรอบปัจจุบัน 0 = เพิ่งทำ, 1 = ครบกำหนดพอดี, >1 = เลยกำหนด
  /// ยึดเกณฑ์ที่คืบหน้าไปมากกว่าเมื่อกำหนดไว้ทั้งระยะทางและเวลา
  double? get progress {
    double? byKm;
    double? byTime;
    if (task.intervalKm != null && task.intervalKm! > 0 && remainingKm != null) {
      byKm = (task.intervalKm! - remainingKm!) / task.intervalKm!;
    }
    if (dueDate != null && remainingDays != null) {
      final total = dueDate!.difference(DateTime.fromMillisecondsSinceEpoch(baselineDate)).inDays;
      if (total > 0) byTime = (total - remainingDays!) / total;
    }
    if (byKm == null) return byTime;
    if (byTime == null) return byKm;
    return byKm > byTime ? byKm : byTime;
  }

  /// ข้อความสรุปสั้น ๆ สำหรับแสดงในรายการ
  String get summaryLabel {
    switch (level) {
      case DueLevel.noInterval:
        return 'ไม่ได้ตั้งรอบ';
      case DueLevel.overdue:
        final parts = <String>[];
        if (remainingKm != null && remainingKm! <= 0) {
          parts.add('เกิน ${_km(-remainingKm!)} กม.');
        }
        if (remainingDays != null && remainingDays! <= 0) {
          parts.add('เกิน ${-remainingDays!} วัน');
        }
        return parts.isEmpty ? 'เลยกำหนดแล้ว' : 'เลยกำหนด ${parts.join(' / ')}';
      case DueLevel.dueSoon:
      case DueLevel.ok:
        final parts = <String>[];
        if (remainingKm != null) parts.add('อีก ${_km(remainingKm!)} กม.');
        if (remainingDays != null) parts.add('อีก $remainingDays วัน');
        return parts.isEmpty ? '-' : parts.join(' / ');
    }
  }

  static String _km(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// คำนวณสถานะของทุกรายการบำรุงรักษาในรถหนึ่งคัน
///
/// [currentOdometer] เลขไมล์ล่าสุดเท่าที่แอพรู้
/// [avgKmPerDay] ระยะทางเฉลี่ยต่อวัน ใช้ประเมินว่าเกณฑ์ระยะทางจะถึงกำหนดวันไหน
/// ส่ง null ถ้ายังไม่มีข้อมูลพอ
///
/// ผลลัพธ์เรียงตามความเร่งด่วน (เลยกำหนดก่อน แล้วค่อยใกล้ครบกำหนด)
List<TaskStatus> computeStatuses({
  required Vehicle vehicle,
  required List<MaintenanceTask> tasks,
  required Map<String, ServiceRecord> latestRecords,
  required double currentOdometer,
  double? avgKmPerDay,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final statuses = tasks
      .map((t) => computeStatus(
            vehicle: vehicle,
            task: t,
            lastRecord: latestRecords[t.id],
            currentOdometer: currentOdometer,
            avgKmPerDay: avgKmPerDay,
            now: at,
          ))
      .toList();

  statuses.sort((a, b) {
    final byLevel = b.level.index.compareTo(a.level.index);
    if (byLevel != 0) return byLevel;
    final pa = a.progress, pb = b.progress;
    if (pa == null && pb == null) return a.task.sortOrder.compareTo(b.task.sortOrder);
    if (pa == null) return 1;
    if (pb == null) return -1;
    return pb.compareTo(pa);
  });
  return statuses;
}

TaskStatus computeStatus({
  required Vehicle vehicle,
  required MaintenanceTask task,
  ServiceRecord? lastRecord,
  required double currentOdometer,
  double? avgKmPerDay,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();

  // ยังไม่เคยบันทึกว่าทำ ให้ถือว่านับรอบจากวันที่เริ่มใช้รถกับเลขไมล์ตั้งต้น
  final baselineDate = lastRecord?.date ?? vehicle.createdAt;
  final baselineOdo = lastRecord?.odometer ?? vehicle.initialOdo;

  double? dueOdo;
  double? remainingKm;
  if (task.intervalKm != null && task.intervalKm! > 0) {
    dueOdo = baselineOdo + task.intervalKm!;
    remainingKm = dueOdo - currentOdometer;
  }

  DateTime? dueDate;
  int? remainingDays;
  if (task.intervalMonths != null && task.intervalMonths! > 0) {
    dueDate = _addMonths(
      DateTime.fromMillisecondsSinceEpoch(baselineDate),
      task.intervalMonths!,
    );
    remainingDays = _wholeDaysBetween(at, dueDate);
  }

  final level = _levelOf(
    task: task,
    remainingKm: remainingKm,
    remainingDays: remainingDays,
  );

  return TaskStatus(
    task: task,
    lastRecord: lastRecord,
    baselineDate: baselineDate,
    baselineOdometer: baselineOdo,
    dueOdometer: dueOdo,
    dueDate: dueDate,
    remainingKm: remainingKm,
    remainingDays: remainingDays,
    estimatedDueDate: _estimateDueDate(
      at: at,
      dueDate: dueDate,
      remainingKm: remainingKm,
      avgKmPerDay: avgKmPerDay,
    ),
    level: level,
  );
}

DueLevel _levelOf({
  required MaintenanceTask task,
  double? remainingKm,
  int? remainingDays,
}) {
  if (remainingKm == null && remainingDays == null) return DueLevel.noInterval;

  final overdue = (remainingKm != null && remainingKm <= 0) ||
      (remainingDays != null && remainingDays <= 0);
  if (overdue) return DueLevel.overdue;

  final soon = (remainingKm != null && remainingKm <= task.notifyKmBefore) ||
      (remainingDays != null && remainingDays <= task.notifyDaysBefore);
  return soon ? DueLevel.dueSoon : DueLevel.ok;
}

/// วันที่คาดว่าจะครบกำหนด = อันที่มาถึงก่อนระหว่างเกณฑ์เวลากับเกณฑ์ระยะทาง
///
/// เกณฑ์ระยะทางแปลงเป็นวันโดยหารด้วยระยะทางเฉลี่ยต่อวัน
DateTime? _estimateDueDate({
  required DateTime at,
  DateTime? dueDate,
  double? remainingKm,
  double? avgKmPerDay,
}) {
  DateTime? byKm;
  if (remainingKm != null && avgKmPerDay != null && avgKmPerDay > 0) {
    final days = (remainingKm / avgKmPerDay).ceil();
    byKm = at.add(Duration(days: days));
  }
  if (dueDate == null) return byKm;
  if (byKm == null) return dueDate;
  return byKm.isBefore(dueDate) ? byKm : dueDate;
}

/// บวกเดือนแบบไม่ให้วันล้นเดือน เช่น 31 ม.ค. + 1 เดือน = 28/29 ก.พ.
DateTime _addMonths(DateTime from, int months) {
  final totalMonths = from.month - 1 + months;
  final year = from.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(
    year,
    month,
    from.day > lastDay ? lastDay : from.day,
    from.hour,
    from.minute,
  );
}

/// นับจำนวนวันเต็มจาก [from] ถึง [to] โดยตัดเวลาในวันทิ้ง
/// เพื่อให้ "อีก 1 วัน" หมายถึงพรุ่งนี้เสมอ ไม่ขึ้นกับว่าตอนนี้กี่โมง
int _wholeDaysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}
