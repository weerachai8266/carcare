// สร้างไฟล์ SQL สำหรับ seed แคตตาล็อกรถฝั่งเซิร์ฟเวอร์ จากข้อมูลชุดเดียวกับที่แอพใช้
//
// รัน: dart run tool/export_catalog_sql.dart
//
// สคริปต์เขียนไฟล์เองแทนการพ่นออก stdout เพราะการ redirect ด้วย PowerShell
// จะเติม BOM เข้าไปหน้าไฟล์ ซึ่งทำให้ mysql client บางเวอร์ชันอ่านบรรทัดแรกไม่ออก
//
// มีสคริปต์นี้เพื่อให้แคตตาล็อกมีต้นทางเดียว (lib/models/car_catalog.dart)
// ถ้าก็อปรายการรถไปเขียนซ้ำใน SQL อีกชุด สองฝั่งจะเพี้ยนจากกันทันทีที่มีรุ่นใหม่
// และ id ที่ไม่ตรงกันจะทำให้สถิติของรุ่นเดียวกันถูกแยกเป็นคนละกอง

import 'dart:convert';
import 'dart:io';

import 'package:carcare/models/car_catalog.dart';

String sqlString(String? value) {
  if (value == null) return 'NULL';
  return "'${value.replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'";
}

void main() {
  final buffer = StringBuffer();

  buffer.writeln('-- ไฟล์นี้ถูกสร้างอัตโนมัติ อย่าแก้ด้วยมือ');
  buffer.writeln('-- แก้ที่ lib/models/car_catalog.dart แล้วรัน:');
  buffer.writeln('--   dart run tool/export_catalog_sql.dart > server/sql/catalog_seed.sql');
  buffer.writeln();
  buffer.writeln('USE carcare;');
  buffer.writeln();
  buffer.writeln('SET @now = ROUND(UNIX_TIMESTAMP(NOW(3)) * 1000);');
  buffer.writeln();

  buffer.writeln('INSERT INTO car_makes');
  buffer.writeln('  (id, name, name_th, sort_order, is_custom, approved, created_at, updated_at, synced_at, deleted)');
  buffer.writeln('VALUES');

  final makeRows = <String>[];
  for (var i = 0; i < MakeSeed.all.length; i++) {
    final make = MakeSeed.all[i];
    makeRows.add(
      '  (${sqlString(make.id)}, ${sqlString(make.name)}, ${sqlString(make.nameTh)}, '
      '$i, 0, 1, @now, @now, @now, 0)',
    );
  }
  buffer.writeln(makeRows.join(',\n'));
  // seed ซ้ำได้โดยไม่ทับชื่อที่แอดมินแก้ไว้แล้ว
  buffer.writeln('ON DUPLICATE KEY UPDATE id = id;');
  buffer.writeln();

  buffer.writeln('INSERT INTO car_models');
  buffer.writeln('  (id, make_id, name, body_type, sort_order, is_custom, approved, created_at, updated_at, synced_at, deleted)');
  buffer.writeln('VALUES');

  final modelRows = <String>[];
  for (final make in MakeSeed.all) {
    var index = 0;
    for (final bodyType in BodyType.order) {
      for (final model in make.models[bodyType] ?? const <String>[]) {
        modelRows.add(
          '  (${sqlString(catalogSlug('${make.id}-$model'))}, ${sqlString(make.id)}, '
          '${sqlString(model)}, ${sqlString(bodyType)}, ${index++}, 0, 1, @now, @now, @now, 0)',
        );
      }
    }
  }
  buffer.writeln(modelRows.join(',\n'));
  buffer.writeln('ON DUPLICATE KEY UPDATE id = id;');

  final output = File('server/sql/catalog_seed.sql');
  output.writeAsBytesSync(utf8.encode(buffer.toString()));

  // ignore: avoid_print
  print('เขียน ${output.path} แล้ว '
      '(${MakeSeed.all.length} ยี่ห้อ, ${modelRows.length} รุ่น)');
}
