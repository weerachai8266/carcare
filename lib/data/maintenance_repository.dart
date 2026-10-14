import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/maintenance_task.dart';
import '../models/service_record.dart';
import 'app_database.dart';
import 'local_changes.dart';
import 'upsert.dart';

/// อ่าน/เขียนรายการบำรุงรักษาและประวัติที่ทำไปแล้ว
///
/// สองอย่างนี้อยู่ใน repository เดียวกันเพราะใช้คู่กันตลอด:
/// รายการบำรุงรักษาบอก "ต้องทำทุกเท่าไร" ส่วนประวัติบอก "ทำครั้งล่าสุดเมื่อไร"
/// ต้องมีทั้งคู่ถึงจะรู้ว่าครบกำหนดหรือยัง
class MaintenanceRepository {
  MaintenanceRepository({Database? db}) : _override = db;

  final Database? _override;
  static const _uuid = Uuid();

  Future<Database> get _db async => _override ?? await AppDatabase.instance.database;

  // ---------- รายการบำรุงรักษา ----------

  Future<List<MaintenanceTask>> tasksForVehicle(
    String vehicleId, {
    bool includeInactive = false,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'maintenance_tasks',
      where: includeInactive
          ? 'vehicle_id = ? AND deleted = 0'
          : 'vehicle_id = ? AND deleted = 0 AND is_active = 1',
      whereArgs: [vehicleId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(MaintenanceTask.fromMap).toList();
  }

  Future<MaintenanceTask?> taskById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'maintenance_tasks',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : MaintenanceTask.fromMap(rows.first);
  }

  Future<MaintenanceTask> createTask({
    required String vehicleId,
    required String name,
    String? category,
    double? intervalKm,
    int? intervalMonths,
    double notifyKmBefore = 500,
    int notifyDaysBefore = 7,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxOrder = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT MAX(sort_order) FROM maintenance_tasks WHERE vehicle_id = ? AND deleted = 0',
            [vehicleId],
          ),
        ) ??
        -1;

    final task = MaintenanceTask(
      id: _uuid.v4(),
      vehicleId: vehicleId,
      name: name,
      category: category,
      intervalKm: intervalKm,
      intervalMonths: intervalMonths,
      notifyKmBefore: notifyKmBefore,
      notifyDaysBefore: notifyDaysBefore,
      sortOrder: maxOrder + 1,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('maintenance_tasks', task.toMap());
    LocalChanges.instance.notifyChanged();
    return task;
  }

  /// ใส่รายการบำรุงรักษามาตรฐานให้รถคันใหม่ เรียกครั้งเดียวตอนสร้างรถ
  Future<void> seedDefaultTasks(String vehicleId) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < TaskTemplate.defaults.length; i++) {
      final t = TaskTemplate.defaults[i];
      batch.insert(
        'maintenance_tasks',
        MaintenanceTask(
          id: _uuid.v4(),
          vehicleId: vehicleId,
          name: t.name,
          category: t.category,
          intervalKm: t.intervalKm,
          intervalMonths: t.intervalMonths,
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
    }
    await batch.commit(noResult: true);
    LocalChanges.instance.notifyChanged();
  }

  Future<void> upsertTask(MaintenanceTask task) async {
    await upsertRow(await _db, 'maintenance_tasks', task.toMap());
  }

  Future<void> softDeleteTask(String id) async {
    await softDeleteRow(await _db, 'maintenance_tasks', id);
  }

  // ---------- ประวัติการเข้าอู่ ----------

  Future<List<ServiceRecord>> recordsForVehicle(String vehicleId, {int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      'service_records',
      where: 'vehicle_id = ? AND deleted = 0',
      whereArgs: [vehicleId],
      orderBy: 'date DESC, odometer DESC',
      limit: limit,
    );
    return rows.map(ServiceRecord.fromMap).toList();
  }

  Future<List<ServiceRecord>> recordsForTask(String taskId) async {
    final db = await _db;
    final rows = await db.query(
      'service_records',
      where: 'task_id = ? AND deleted = 0',
      whereArgs: [taskId],
      orderBy: 'date DESC, odometer DESC',
    );
    return rows.map(ServiceRecord.fromMap).toList();
  }

  /// ครั้งล่าสุดที่ทำของทุกรายการในรถคันหนึ่ง คืนเป็น map ตาม task_id
  ///
  /// ดึงทีเดียวทั้งคันเพื่อไม่ให้หน้ารายการยิงคิวรีต่อหนึ่งรายการ
  Future<Map<String, ServiceRecord>> latestRecordPerTask(String vehicleId) async {
    final db = await _db;
    final rows = await db.query(
      'service_records',
      where: 'vehicle_id = ? AND deleted = 0 AND task_id IS NOT NULL',
      whereArgs: [vehicleId],
      orderBy: 'odometer DESC, date DESC',
    );

    final result = <String, ServiceRecord>{};
    for (final row in rows) {
      final record = ServiceRecord.fromMap(row);
      // แถวแรกของแต่ละ task คือครั้งล่าสุดอยู่แล้วเพราะเรียงมาจากมากไปน้อย
      result.putIfAbsent(record.taskId!, () => record);
    }
    return result;
  }

  Future<ServiceRecord> createRecord({
    required String vehicleId,
    String? taskId,
    required String title,
    required int date,
    required double odometer,
    double? cost,
    String? workshop,
    String? note,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = ServiceRecord(
      id: _uuid.v4(),
      vehicleId: vehicleId,
      taskId: taskId,
      title: title,
      date: date,
      odometer: odometer,
      cost: cost,
      workshop: workshop,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('service_records', record.toMap());
    LocalChanges.instance.notifyChanged();
    return record;
  }

  Future<void> upsertRecord(ServiceRecord record) async {
    await upsertRow(await _db, 'service_records', record.toMap());
  }

  Future<void> softDeleteRecord(String id) async {
    await softDeleteRow(await _db, 'service_records', id);
  }
}
