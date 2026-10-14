import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/fuel_entry.dart';
import 'app_database.dart';
import 'local_changes.dart';
import 'upsert.dart';

/// อ่าน/เขียนรายการเติมน้ำมัน
class FuelRepository {
  FuelRepository({Database? db}) : _override = db;

  final Database? _override;
  static const _uuid = Uuid();

  Future<Database> get _db async => _override ?? await AppDatabase.instance.database;

  /// เรียงจากใหม่ไปเก่า สำหรับหน้ารายการ
  Future<List<FuelEntry>> forVehicle(String vehicleId, {int? limit}) async {
    final db = await _db;
    final rows = await db.query(
      'fuel_entries',
      where: 'vehicle_id = ? AND deleted = 0',
      whereArgs: [vehicleId],
      orderBy: 'date DESC, odometer DESC',
      limit: limit,
    );
    return rows.map(FuelEntry.fromMap).toList();
  }

  /// เรียงจากเก่าไปใหม่ตามเลขไมล์ สำหรับคำนวณอัตราสิ้นเปลือง
  ///
  /// ใช้ odometer เป็นเกณฑ์หลักแทนวันที่ เพราะการคำนวณต้องอาศัยระยะทางที่วิ่งจริง
  /// ถ้าผู้ใช้กรอกวันที่ผิดเล็กน้อยก็ยังคำนวณได้ถูก
  Future<List<FuelEntry>> forVehicleByOdometer(String vehicleId) async {
    final db = await _db;
    final rows = await db.query(
      'fuel_entries',
      where: 'vehicle_id = ? AND deleted = 0',
      whereArgs: [vehicleId],
      orderBy: 'odometer ASC, date ASC',
    );
    return rows.map(FuelEntry.fromMap).toList();
  }

  Future<FuelEntry?> byId(String id) async {
    final db = await _db;
    final rows = await db.query(
      'fuel_entries',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : FuelEntry.fromMap(rows.first);
  }

  /// การเติมครั้งล่าสุดตามเลขไมล์ ใช้เป็นค่าตั้งต้นในฟอร์มเติมครั้งถัดไป
  Future<FuelEntry?> latest(String vehicleId) async {
    final db = await _db;
    final rows = await db.query(
      'fuel_entries',
      where: 'vehicle_id = ? AND deleted = 0',
      whereArgs: [vehicleId],
      orderBy: 'odometer DESC, date DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : FuelEntry.fromMap(rows.first);
  }

  Future<FuelEntry> create({
    required String vehicleId,
    required int date,
    required double odometer,
    required double liters,
    double? pricePerLiter,
    double? totalCost,
    bool isFullTank = true,
    bool missedEntries = false,
    String? fuelType,
    String? station,
    String? note,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = FuelEntry(
      id: _uuid.v4(),
      vehicleId: vehicleId,
      date: date,
      odometer: odometer,
      liters: liters,
      pricePerLiter: pricePerLiter,
      totalCost: totalCost,
      isFullTank: isFullTank,
      missedEntries: missedEntries,
      fuelType: fuelType,
      station: station,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('fuel_entries', entry.toMap());
    LocalChanges.instance.notifyChanged();
    return entry;
  }

  Future<void> upsert(FuelEntry entry) async {
    await upsertRow(await _db, 'fuel_entries', entry.toMap());
  }

  Future<void> softDelete(String id) async {
    await softDeleteRow(await _db, 'fuel_entries', id);
  }
}
