import 'package:sqflite/sqflite.dart';

import '../models/car_catalog.dart';

/// ใส่ยี่ห้อ/รุ่นตั้งต้นลงฐานข้อมูล
///
/// ใช้ `INSERT OR IGNORE` เพื่อให้เรียกซ้ำได้โดยไม่ทับข้อมูลเดิม
/// จำเป็นเพราะเวอร์ชันหน้าจะเพิ่มรุ่นใหม่เข้ามาแล้วเรียกฟังก์ชันนี้อีกครั้ง
/// และต้องไม่ไปลบรุ่นที่ผู้ใช้เพิ่มเองหรือแก้ชื่อไปแล้ว
Future<void> seedCarCatalog(DatabaseExecutor db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final batch = db.batch();

  for (var makeIndex = 0; makeIndex < MakeSeed.all.length; makeIndex++) {
    final make = MakeSeed.all[makeIndex];
    batch.insert(
      'car_makes',
      CarMake(
        id: make.id,
        name: make.name,
        nameTh: make.nameTh,
        sortOrder: makeIndex,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // เรียงรุ่นตามลำดับประเภทตัวถังก่อน แล้วค่อยตามลำดับที่เขียนไว้ใน seed
    var modelIndex = 0;
    for (final bodyType in BodyType.order) {
      for (final model in make.models[bodyType] ?? const <String>[]) {
        batch.insert(
          'car_models',
          CarModel(
            id: catalogSlug('${make.id}-$model'),
            makeId: make.id,
            name: model,
            bodyType: bodyType,
            sortOrder: modelIndex++,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  await batch.commit(noResult: true);
}

