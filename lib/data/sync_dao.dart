import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'upsert.dart';

/// อ่าน/เขียนแถวแบบดิบ ๆ สำหรับงานซิงก์โดยเฉพาะ
///
/// งานซิงก์สนใจแค่ "แถวไหนยังไม่ได้ส่ง" กับ "เอาแถวนี้ไปเขียนทับ" เหมือนกันหมดทุกตาราง
/// จึงทำเป็นตัวเดียวที่รับชื่อตาราง แทนการไปเพิ่มเมธอดซ้ำ ๆ ใน repository ทุกตัว
class SyncDao {
  SyncDao({Database? db}) : _override = db;

  final Database? _override;

  /// ตารางข้อมูลผู้ใช้ที่ซิงก์ขึ้นเซิร์ฟเวอร์ เรียงตามลำดับที่ต้องเขียน
  /// (รถต้องมาก่อน เพราะตารางอื่นอ้างถึงรถด้วย foreign key)
  static const userTables = [
    'vehicles',
    'fuel_entries',
    'maintenance_tasks',
    'service_records',
  ];

  /// ตารางแคตตาล็อกที่ส่งขึ้นเฉพาะแถวที่ผู้ใช้เพิ่มเอง
  static const catalogTables = ['car_makes', 'car_models'];

  Future<Database> get _db async => _override ?? await AppDatabase.instance.database;

  /// แถวที่แก้ในเครื่องแล้วยังไม่ได้ส่งขึ้นเซิร์ฟเวอร์
  Future<List<Map<String, Object?>>> dirtyRows(String table) async {
    final db = await _db;
    return db.query(table, where: 'dirty = 1');
  }

  /// แถวแคตตาล็อกที่ผู้ใช้เพิ่มเอง (แถวมาตรฐานไม่ต้องส่งกลับขึ้นไป)
  Future<List<Map<String, Object?>>> dirtyCustomRows(String table) async {
    final db = await _db;
    return db.query(table, where: 'dirty = 1 AND is_custom = 1');
  }

  /// ตั้งธง dirty ให้ทุกแถวในเครื่อง เพื่อบังคับส่งขึ้นเซิร์ฟเวอร์ใหม่ทั้งหมด
  ///
  /// จำเป็นเมื่อข้อมูลฝั่งเซิร์ฟเวอร์หายไป (ล้างฐานข้อมูล/ย้ายเครื่อง/เปลี่ยนบัญชี)
  /// เพราะการล้างเคอร์เซอร์อย่างเดียวแก้ได้แค่ขา "ดึงลง" ส่วนขา "ส่งขึ้น" ดูที่ธง
  /// dirty ซึ่งถูกล้างไปแล้วตั้งแต่ซิงก์สำเร็จครั้งก่อน ผลคือทั้งสองฝั่งเงียบสนิท
  /// โดยที่เครื่องยังเข้าใจว่าสำรองข้อมูลไว้แล้ว
  ///
  /// คืนจำนวนแถวที่ถูกตั้งธง
  Future<int> markAllDirty() async {
    final db = await _db;
    var count = 0;

    await db.transaction((txn) async {
      for (final table in userTables) {
        count += await txn.update(table, {'dirty': 1});
      }
      // แคตตาล็อกส่งขึ้นเฉพาะแถวที่ผู้ใช้เพิ่มเอง แถวมาตรฐานมีอยู่บนเซิร์ฟเวอร์แล้ว
      for (final table in catalogTables) {
        count += await txn.update(table, {'dirty': 1}, where: 'is_custom = 1');
      }
    });

    return count;
  }

  /// ล้างธง dirty หลังเซิร์ฟเวอร์ตอบรับแล้ว
  ///
  /// เช็ค `updated_at` ซ้ำเพื่อไม่ให้ล้างธงของแถวที่ผู้ใช้เพิ่งแก้ระหว่างรอเซิร์ฟเวอร์ตอบ
  /// ไม่งั้นการแก้ครั้งนั้นจะค้างอยู่ในเครื่องและไม่ถูกส่งขึ้นไปอีกเลย
  Future<void> markClean(String table, List<Map<String, Object?>> sentRows) async {
    if (sentRows.isEmpty) return;

    final db = await _db;
    final batch = db.batch();
    for (final row in sentRows) {
      batch.update(
        table,
        {'dirty': 0},
        where: 'id = ? AND updated_at = ?',
        whereArgs: [row['id'], row['updated_at']],
      );
    }
    await batch.commit(noResult: true);
  }

  /// เขียนแถวที่ได้จากเซิร์ฟเวอร์ลงเครื่อง
  ///
  /// ตั้ง `dirty = 0` เสมอ เพราะแถวนี้ตรงกับเซิร์ฟเวอร์อยู่แล้ว
  /// และข้ามแถวที่ในเครื่องใหม่กว่า เพื่อไม่ให้ทับงานที่ผู้ใช้เพิ่งแก้และยังไม่ได้ส่ง
  Future<int> applyRows(String table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return 0;

    final db = await _db;
    var applied = 0;

    await db.transaction((txn) async {
      for (final row in rows) {
        final id = row['id'];
        final incomingUpdatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;

        final existing = await txn.query(
          table,
          columns: ['updated_at'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final localUpdatedAt = (existing.first['updated_at'] as num?)?.toInt() ?? 0;
          if (localUpdatedAt >= incomingUpdatedAt) continue;
        }

        await upsertRow(txn, table, {...row, 'dirty': 0});
        applied++;
      }
    });

    return applied;
  }
}
