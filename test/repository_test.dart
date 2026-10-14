import 'package:carcare/data/app_database.dart';
import 'package:carcare/data/fuel_repository.dart';
import 'package:carcare/data/local_changes.dart';
import 'package:carcare/data/maintenance_repository.dart';
import 'package:carcare/data/sync_dao.dart';
import 'package:carcare/data/vehicle_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// เทสต์ที่แตะฐานข้อมูลจริง (ในหน่วยความจำ) เพื่อจับพฤติกรรมที่ mock จับไม่ได้
/// โดยเฉพาะเรื่อง foreign key กับการเขียนทับแถว
void main() {
  sqfliteFfiInit();

  late Database db;
  late VehicleRepository vehicles;
  late FuelRepository fuel;
  late MaintenanceRepository maintenance;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        // ต้องเปิดเหมือนของจริง ไม่งั้นเทสต์จะไม่เจอปัญหา CASCADE ที่ตั้งใจกัน
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    await AppDatabase.applySchema(db);

    vehicles = VehicleRepository(db: db);
    fuel = FuelRepository(db: db);
    maintenance = MaintenanceRepository(db: db);
  });

  tearDown(() async => db.close());

  test('แก้ข้อมูลรถแล้วประวัติของรถคันนั้นต้องอยู่ครบ', () async {
    // เคยพังจริง: upsert ที่ใช้ ConflictAlgorithm.replace ทำ DELETE+INSERT
    // แล้ว ON DELETE CASCADE ลบประวัติทั้งคันทิ้ง
    final vehicle = await vehicles.create(name: 'รถบ้าน', initialOdo: 50000);
    await fuel.create(
      vehicleId: vehicle.id,
      date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      odometer: 50000,
      liters: 40,
    );
    await maintenance.seedDefaultTasks(vehicle.id);
    final task = (await maintenance.tasksForVehicle(vehicle.id)).first;
    await maintenance.createRecord(
      vehicleId: vehicle.id,
      taskId: task.id,
      title: 'เปลี่ยนถ่ายน้ำมันเครื่อง',
      date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      odometer: 50000,
    );

    await vehicles.upsert(vehicle.copyWith(name: 'รถบ้าน (แก้ชื่อ)'));

    expect((await vehicles.byId(vehicle.id))!.name, 'รถบ้าน (แก้ชื่อ)');
    expect(await fuel.forVehicle(vehicle.id), hasLength(1));
    expect(await maintenance.tasksForVehicle(vehicle.id), hasLength(19));
    expect(await maintenance.recordsForVehicle(vehicle.id), hasLength(1));
  });

  test('แก้รายการบำรุงรักษาแล้วประวัติต้องยังผูกกับรายการเดิม', () async {
    // ON DELETE SET NULL ของ service_records.task_id ก็โดนผลจาก REPLACE เหมือนกัน
    final vehicle = await vehicles.create(name: 'รถบ้าน');
    final task = await maintenance.createTask(
      vehicleId: vehicle.id,
      name: 'เปลี่ยนถ่ายน้ำมันเครื่อง',
      intervalKm: 10000,
    );
    await maintenance.createRecord(
      vehicleId: vehicle.id,
      taskId: task.id,
      title: 'เปลี่ยนถ่ายน้ำมันเครื่อง',
      date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      odometer: 50000,
    );

    await maintenance.upsertTask(task.copyWith(intervalKm: 12000));

    final records = await maintenance.recordsForTask(task.id);
    expect(records, hasLength(1));
    expect(records.first.taskId, task.id);
  });

  test('เลขไมล์ล่าสุดเอาค่าสูงสุดจากทั้งการเติมน้ำมัน ประวัติ และเลขตั้งต้น', () async {
    final vehicle = await vehicles.create(name: 'รถบ้าน', initialOdo: 50000);
    expect(await vehicles.currentOdometer(vehicle.id), 50000);

    await fuel.create(
      vehicleId: vehicle.id,
      date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      odometer: 50500,
      liters: 40,
    );
    expect(await vehicles.currentOdometer(vehicle.id), 50500);

    await maintenance.createRecord(
      vehicleId: vehicle.id,
      title: 'เข้าศูนย์',
      date: DateTime(2025, 2, 1).millisecondsSinceEpoch,
      odometer: 51000,
    );
    expect(await vehicles.currentOdometer(vehicle.id), 51000);
  });

  test('ลบแบบ soft delete แล้วต้องไม่โผล่ในรายการอีก', () async {
    final vehicle = await vehicles.create(name: 'รถเก่า');
    await vehicles.softDelete(vehicle.id);

    expect(await vehicles.byId(vehicle.id), isNull);
    expect(await vehicles.all(), isEmpty);

    // แถวยังอยู่ในตาราง เพื่อให้ซิงก์ไปลบที่เครื่องอื่นได้
    final rows = await db.query('vehicles', where: 'id = ?', whereArgs: [vehicle.id]);
    expect(rows, hasLength(1));
    expect(rows.first['deleted'], 1);
    expect(rows.first['dirty'], 1);
  });

  test('ครั้งล่าสุดของแต่ละรายการดึงมาถูกตัว', () async {
    final vehicle = await vehicles.create(name: 'รถบ้าน');
    final task = await maintenance.createTask(
      vehicleId: vehicle.id,
      name: 'เปลี่ยนถ่ายน้ำมันเครื่อง',
      intervalKm: 10000,
    );

    await maintenance.createRecord(
      vehicleId: vehicle.id,
      taskId: task.id,
      title: 'ครั้งแรก',
      date: DateTime(2024, 1, 1).millisecondsSinceEpoch,
      odometer: 40000,
    );
    await maintenance.createRecord(
      vehicleId: vehicle.id,
      taskId: task.id,
      title: 'ครั้งล่าสุด',
      date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      odometer: 50000,
    );

    final latest = await maintenance.latestRecordPerTask(vehicle.id);
    expect(latest[task.id]!.title, 'ครั้งล่าสุด');
  });

  group('LocalChanges', () {
    test('เขียนข้อมูลที่ผู้ใช้แก้ ต้องส่งสัญญาณให้ไปซิงก์', () async {
      var notified = 0;
      void listener() => notified++;
      LocalChanges.instance.addListener(listener);
      addTearDown(() => LocalChanges.instance.removeListener(listener));

      final vehicle = await vehicles.create(name: 'รถบ้าน', initialOdo: 1000);
      expect(notified, greaterThan(0), reason: 'สร้างรถ');

      notified = 0;
      await vehicles.upsert(vehicle.copyWith(name: 'ชื่อใหม่'));
      expect(notified, greaterThan(0), reason: 'แก้ข้อมูลรถ');

      notified = 0;
      await fuel.create(
        vehicleId: vehicle.id,
        date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        odometer: 1000,
        liters: 40,
      );
      expect(notified, greaterThan(0), reason: 'เพิ่มการเติมน้ำมัน');

      notified = 0;
      await vehicles.softDelete(vehicle.id);
      expect(notified, greaterThan(0), reason: 'ลบรถ');
    });

    test('ข้อมูลที่ดึงลงมาจากเซิร์ฟเวอร์ ต้องไม่สั่งซิงก์ซ้อน', () async {
      // แถวที่มาจากเซิร์ฟเวอร์เขียนด้วย dirty = 0 ถ้านับเป็นการแก้ในเครื่องด้วย
      // จะกลายเป็นซิงก์เสร็จแล้วสั่งซิงก์ใหม่วนไม่รู้จบ
      final dao = SyncDao(db: db);

      var notified = 0;
      void listener() => notified++;
      LocalChanges.instance.addListener(listener);
      addTearDown(() => LocalChanges.instance.removeListener(listener));

      await dao.applyRows('vehicles', [
        {
          'id': 'from-server',
          'name': 'รถจากเครื่องอื่น',
          'initial_odo': 0,
          'is_active': 1,
          'sort_order': 0,
          'created_at': 1,
          'updated_at': 1,
          'deleted': 0,
        },
      ]);

      expect(notified, 0);
    });
  });

  group('markAllDirty', () {
    test('ตั้งธงให้ทุกแถวที่เคยซิงก์ไปแล้ว เพื่อส่งขึ้นใหม่ได้ทั้งชุด', () async {
      // เคยพังจริง: ล้างฐานข้อมูลฝั่งเซิร์ฟเวอร์แล้วล็อกอินใหม่ ไม่มีอะไรถูกส่งขึ้นเลย
      // เพราะทุกแถวถูกล้างธง dirty ไปตั้งแต่ซิงก์สำเร็จครั้งก่อน
      final dao = SyncDao(db: db);
      final vehicle = await vehicles.create(name: 'รถบ้าน', initialOdo: 50000);
      await fuel.create(
        vehicleId: vehicle.id,
        date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
        odometer: 50000,
        liters: 40,
      );
      await maintenance.seedDefaultTasks(vehicle.id);

      // จำลองว่าซิงก์สำเร็จไปแล้วรอบหนึ่ง
      for (final table in SyncDao.userTables) {
        await dao.markClean(table, await dao.dirtyRows(table));
      }
      for (final table in SyncDao.userTables) {
        expect(await dao.dirtyRows(table), isEmpty, reason: table);
      }

      final marked = await dao.markAllDirty();

      expect(marked, greaterThan(0));
      expect(await dao.dirtyRows('vehicles'), hasLength(1));
      expect(await dao.dirtyRows('fuel_entries'), hasLength(1));
      expect(await dao.dirtyRows('maintenance_tasks'), isNotEmpty);
    });

    test('แคตตาล็อกมาตรฐานต้องไม่ถูกส่งกลับขึ้นไป มีแต่ที่ผู้ใช้เพิ่มเอง', () async {
      final dao = SyncDao(db: db);
      await db.insert('car_makes', {
        'id': 'custom-make',
        'name': 'ยี่ห้อที่เพิ่มเอง',
        'sort_order': 0,
        'is_custom': 1,
        'created_at': 0,
        'updated_at': 0,
        'dirty': 0,
      });

      await dao.markAllDirty();

      final custom = await dao.dirtyCustomRows('car_makes');
      expect(custom, hasLength(1));
      expect(custom.first['id'], 'custom-make');

      // แถวมาตรฐานที่ seed มาต้องไม่ติดธง ไม่งั้นจะส่งรุ่นรถ 253 รุ่นขึ้นไปทุกครั้ง
      final standard = await db.query(
        'car_makes',
        where: 'is_custom = 0 AND dirty = 1',
      );
      expect(standard, isEmpty);
    });
  });
}
