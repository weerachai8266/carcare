import '../data/fuel_repository.dart';
import '../data/maintenance_repository.dart';
import '../data/vehicle_repository.dart';
import '../models/fuel_entry.dart';
import '../models/maintenance_task.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';
import '../services/expense_stats.dart';
import '../services/fuel_stats.dart';
import '../services/maintenance_status.dart';

/// ข้อมูลทั้งหมดของรถหนึ่งคันที่หน้าจอต้องใช้ โหลดทีเดียวจบ
///
/// รวมไว้ก้อนเดียวเพราะแท็บภาพรวม/น้ำมัน/บำรุงรักษาใช้ข้อมูลชุดเดียวกัน
/// และต้องเห็นตรงกันเสมอ เช่น เลขไมล์ล่าสุดที่ใช้คำนวณกำหนดบำรุงรักษา
class VehicleData {
  final Vehicle vehicle;
  final double odometer;

  /// เรียงตามเลขไมล์จากน้อยไปมาก (ลำดับที่ตรรกะคำนวณต้องการ)
  final List<FuelEntry> entries;

  final List<FuelSegment> segments;
  final FuelSummary summary;
  final double? avgKmPerDay;

  final List<MaintenanceTask> tasks;
  final List<TaskStatus> statuses;

  /// ประวัติการเข้าอู่ เรียงจากใหม่ไปเก่า
  final List<ServiceRecord> records;

  /// ค่าใช้จ่ายรวม (น้ำมัน + บำรุงรักษา)
  final ExpenseSummary expenses;

  /// ค่าใช้จ่ายรายเดือน เรียงจากเดือนเก่าไปใหม่ ใช้วาดกราฟ
  final List<MonthlyExpense> months;

  VehicleData({
    required this.vehicle,
    required this.odometer,
    required this.entries,
    required this.segments,
    required this.summary,
    required this.avgKmPerDay,
    required this.tasks,
    required this.statuses,
    required this.records,
    required this.expenses,
    required this.months,
  });

  /// รายการเติมน้ำมันเรียงจากใหม่ไปเก่า สำหรับแสดงผล
  List<FuelEntry> get entriesNewestFirst => entries.reversed.toList();

  /// อัตราสิ้นเปลืองของแต่ละรายการ (เฉพาะรายการที่ปิดช่วงคำนวณได้)
  late final Map<String, FuelSegment> segmentByEntryId = {
    for (final s in segments) s.entry.id: s,
  };

  List<TaskStatus> get attentionStatuses =>
      statuses.where((s) => s.needsAttention).toList();
}

/// โหลดข้อมูลรถทั้งก้อน คืน null ถ้ารถถูกลบไปแล้ว
Future<VehicleData?> loadVehicleData(
  String vehicleId, {
  VehicleRepository? vehicles,
  FuelRepository? fuel,
  MaintenanceRepository? maintenance,
}) async {
  final vehicleRepo = vehicles ?? VehicleRepository();
  final fuelRepo = fuel ?? FuelRepository();
  final maintenanceRepo = maintenance ?? MaintenanceRepository();

  final vehicle = await vehicleRepo.byId(vehicleId);
  if (vehicle == null) return null;

  final odometer = await vehicleRepo.currentOdometer(vehicleId);
  final entries = await fuelRepo.forVehicleByOdometer(vehicleId);
  final tasks = await maintenanceRepo.tasksForVehicle(vehicleId);
  final latestRecords = await maintenanceRepo.latestRecordPerTask(vehicleId);
  final records = await maintenanceRepo.recordsForVehicle(vehicleId);

  final perDay = avgKmPerDay(entries);

  return VehicleData(
    vehicle: vehicle,
    odometer: odometer,
    entries: entries,
    segments: computeSegments(entries),
    summary: summarize(entries),
    avgKmPerDay: perDay,
    tasks: tasks,
    statuses: computeStatuses(
      vehicle: vehicle,
      tasks: tasks,
      latestRecords: latestRecords,
      currentOdometer: odometer,
      avgKmPerDay: perDay,
    ),
    records: records,
    expenses: summarizeExpenses(entries, records),
    months: monthlyExpenses(entries, records),
  );
}
