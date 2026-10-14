import 'package:sqflite/sqflite.dart';

import 'local_changes.dart';

/// เขียนแถวลงตาราง: มีอยู่แล้วก็อัปเดต ไม่มีก็เพิ่มใหม่
///
/// ห้ามใช้ `ConflictAlgorithm.replace` แทนฟังก์ชันนี้เด็ดขาด
/// เพราะ SQLite ทำ REPLACE เป็น DELETE แล้ว INSERT ใหม่ และเมื่อเปิด
/// `PRAGMA foreign_keys = ON` การลบแถวแม่จะลาก ON DELETE CASCADE ไปด้วย
/// ผลคือแก้ข้อมูลรถหนึ่งครั้ง ประวัติเติมน้ำมันและรายการบำรุงรักษาทั้งคันหายเกลี้ยง
/// (เจอจริงตอนทดสอบบนอีมูเลเตอร์ ไม่ใช่ปัญหาทางทฤษฎี)
///
/// ไม่ใช้ไวยากรณ์ UPSERT ของ SQLite (`ON CONFLICT DO UPDATE`) เพราะ Android
/// รุ่นเก่าบางรุ่นมากับ SQLite ที่เก่ากว่า 3.24 ซึ่งยังไม่รองรับ
Future<void> upsertRow(
  DatabaseExecutor db,
  String table,
  Map<String, Object?> row,
) async {
  final updated = await db.update(
    table,
    row,
    where: 'id = ?',
    whereArgs: [row['id']],
  );

  if (updated == 0) {
    await db.insert(table, row);
  }

  // แจ้งเฉพาะแถวที่ผู้ใช้แก้เอง แถวที่ดึงลงมาจากเซิร์ฟเวอร์เขียนด้วย dirty = 0
  // ถ้าแจ้งด้วยจะกลายเป็นซิงก์เสร็จแล้วสั่งซิงก์ใหม่วนไปเรื่อย ๆ
  if (row['dirty'] == 1 || row['dirty'] == true) {
    LocalChanges.instance.notifyChanged();
  }
}

/// ลบแบบ soft delete: ทำเครื่องหมายไว้แล้วให้การซิงก์กระจายการลบไปเครื่องอื่น
///
/// ทุกตารางลบเหมือนกันหมด ต่างแค่ชื่อตาราง จึงรวบไว้ที่เดียว
/// (ก่อนหน้านี้ก๊อปโค้ดชุดเดียวกันไว้สี่ที่ ซึ่งแก้ตกหล่นได้ง่าย)
Future<void> softDeleteRow(
  DatabaseExecutor db,
  String table,
  String id,
) async {
  await db.update(
    table,
    {
      'deleted': 1,
      'dirty': 1,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  LocalChanges.instance.notifyChanged();
}
