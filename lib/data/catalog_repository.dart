import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/car_catalog.dart';
import 'app_database.dart';
import 'local_changes.dart';
import 'upsert.dart';

/// อ่าน/เขียนแคตตาล็อกยี่ห้อและรุ่นรถ
///
/// แถวที่มาจาก seed มี id เป็น slug คงที่ ส่วนแถวที่ผู้ใช้เพิ่มเองใช้ UUID
/// และตั้ง `dirty = 1` ไว้เพื่อส่งขึ้นเซิร์ฟเวอร์ไปเติมแคตตาล็อกกลาง
class CatalogRepository {
  CatalogRepository({Database? db}) : _override = db;

  final Database? _override;
  static const _uuid = Uuid();

  Future<Database> get _db async => _override ?? await AppDatabase.instance.database;

  Future<List<CarMake>> makes() async {
    final db = await _db;
    final rows = await db.query(
      'car_makes',
      where: 'deleted = 0',
      // ยี่ห้อที่ผู้ใช้เพิ่มเองไปอยู่ท้ายสุด (sort_order ของ seed เริ่มที่ 0)
      orderBy: 'is_custom ASC, sort_order ASC, name ASC',
    );
    return rows.map(CarMake.fromMap).toList();
  }

  Future<CarMake?> makeById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'car_makes',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CarMake.fromMap(rows.first);
  }

  Future<List<CarModel>> modelsOfMake(String makeId) async {
    final db = await _db;
    final rows = await db.query(
      'car_models',
      where: 'make_id = ? AND deleted = 0',
      whereArgs: [makeId],
      orderBy: 'is_custom ASC, sort_order ASC, name ASC',
    );
    return rows.map(CarModel.fromMap).toList();
  }

  Future<CarModel?> modelById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'car_models',
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CarModel.fromMap(rows.first);
  }

  /// เพิ่มยี่ห้อที่ยังไม่มีในแคตตาล็อก
  ///
  /// ถ้าชื่อซ้ำกับที่มีอยู่ (ไม่สนตัวพิมพ์เล็กใหญ่) จะคืนแถวเดิมแทนการสร้างซ้ำ
  /// เพราะยี่ห้อซ้ำจะทำให้สถิติของรถรุ่นเดียวกันถูกแยกเป็นสองกอง
  Future<CarMake> addCustomMake(String name) async {
    final db = await _db;
    final trimmed = name.trim();

    final existing = await db.query(
      'car_makes',
      where: 'deleted = 0 AND LOWER(name) = ?',
      whereArgs: [trimmed.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return CarMake.fromMap(existing.first);

    final now = DateTime.now().millisecondsSinceEpoch;
    final make = CarMake(
      id: _uuid.v4(),
      name: trimmed,
      sortOrder: 0,
      isCustom: true,
      createdAt: now,
      updatedAt: now,
      dirty: true,
    );
    await db.insert('car_makes', make.toMap());
    LocalChanges.instance.notifyChanged();
    return make;
  }

  /// เพิ่มรุ่นที่ยังไม่มีในแคตตาล็อกให้ยี่ห้อหนึ่ง
  Future<CarModel> addCustomModel({
    required String makeId,
    required String name,
    String? bodyType,
  }) async {
    final db = await _db;
    final trimmed = name.trim();

    final existing = await db.query(
      'car_models',
      where: 'make_id = ? AND deleted = 0 AND LOWER(name) = ?',
      whereArgs: [makeId, trimmed.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return CarModel.fromMap(existing.first);

    final now = DateTime.now().millisecondsSinceEpoch;
    final model = CarModel(
      id: _uuid.v4(),
      makeId: makeId,
      name: trimmed,
      bodyType: bodyType,
      isCustom: true,
      createdAt: now,
      updatedAt: now,
      dirty: true,
    );
    await db.insert('car_models', model.toMap());
    LocalChanges.instance.notifyChanged();
    return model;
  }

  /// รับแถวจากเซิร์ฟเวอร์มาเขียนทับ ใช้ตอนซิงก์แคตตาล็อกกลางลงเครื่อง
  Future<void> upsertMake(CarMake make) async {
    await upsertRow(await _db, 'car_makes', make.toMap());
  }

  Future<void> upsertModel(CarModel model) async {
    await upsertRow(await _db, 'car_models', model.toMap());
  }
}
