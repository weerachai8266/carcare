import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/vehicle.dart';
import 'app_database.dart';
import 'local_changes.dart';
import 'upsert.dart';

/// อ่าน/เขียนข้อมูลรถ
///
/// การลบทุกที่ในแอพเป็น soft delete (`deleted = 1`) เพื่อให้ซิงก์ไปลบอีกเครื่องได้
/// คิวรีทุกอันจึงต้องกรอง `deleted = 0` เสมอ
class VehicleRepository {
  VehicleRepository({Database? db}) : _override = db;

  final Database? _override;
  static const _uuid = Uuid();

  Future<Database> get _db async => _override ?? await AppDatabase.instance.database;

  Future<List<Vehicle>> all({bool includeInactive = false}) async {
    final db = await _db;
    final rows = await db.query(
      'vehicles',
      where: includeInactive ? 'deleted = 0' : 'deleted = 0 AND is_active = 1',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  Future<Vehicle?> byId(String id) async {
    final db = await _db;
    final rows = await db.query(
      'vehicles',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Vehicle.fromMap(rows.first);
  }

  /// สร้างรถคันใหม่ ต่อท้ายลำดับที่มีอยู่
  Future<Vehicle> create({
    required String name,
    String? make,
    String? model,
    String? makeId,
    String? modelId,
    int? year,
    String? plate,
    String? fuelType,
    double? tankCapacity,
    double initialOdo = 0,
  }) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxOrder = Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(sort_order) FROM vehicles WHERE deleted = 0'),
        ) ??
        -1;

    final vehicle = Vehicle(
      id: _uuid.v4(),
      name: name,
      make: make,
      model: model,
      makeId: makeId,
      modelId: modelId,
      year: year,
      plate: plate,
      fuelType: fuelType,
      tankCapacity: tankCapacity,
      initialOdo: initialOdo,
      sortOrder: maxOrder + 1,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('vehicles', vehicle.toMap());
    LocalChanges.instance.notifyChanged();
    return vehicle;
  }

  /// เขียนทับทั้งแถว ใช้ทั้งตอนแก้ไขในเครื่องและตอนรับข้อมูลจากคลาวด์
  Future<void> upsert(Vehicle vehicle) async {
    await upsertRow(await _db, 'vehicles', vehicle.toMap());
  }

  Future<void> softDelete(String id) async {
    await softDeleteRow(await _db, 'vehicles', id);
  }

  /// สลับลำดับการแสดงผลตามที่ผู้ใช้ลากจัดเรียง
  Future<void> reorder(List<String> idsInOrder) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update(
        'vehicles',
        {'sort_order': i, 'dirty': 1, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [idsInOrder[i]],
      );
    }
    await batch.commit(noResult: true);

    // batch เขียนตรงไม่ผ่าน upsertRow จึงต้องแจ้งเอง
    LocalChanges.instance.notifyChanged();
  }

  /// เลขไมล์ล่าสุดเท่าที่แอพรู้ = ค่าที่มากที่สุดจากการเติมน้ำมัน ประวัติเข้าอู่ และเลขตั้งต้น
  ///
  /// ยอมให้เอาค่าสูงสุดแทนค่าล่าสุดตามวันที่ เพราะเลขไมล์เดินหน้าอย่างเดียว
  /// ถ้าผู้ใช้กรอกย้อนหลัง ค่าสูงสุดจึงยังเป็นค่าที่ใกล้ความจริงที่สุด
  Future<double> currentOdometer(String vehicleId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT MAX(odo) AS odo FROM (
        SELECT MAX(odometer) AS odo FROM fuel_entries
          WHERE vehicle_id = ? AND deleted = 0
        UNION ALL
        SELECT MAX(odometer) AS odo FROM service_records
          WHERE vehicle_id = ? AND deleted = 0
        UNION ALL
        SELECT initial_odo AS odo FROM vehicles WHERE id = ?
      )
      ''',
      [vehicleId, vehicleId, vehicleId],
    );
    return (rows.first['odo'] as num?)?.toDouble() ?? 0;
  }
}
