import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'catalog_seed.dart';

/// ฐานข้อมูล SQLite ในเครื่อง
///
/// ทุกตารางออกแบบให้พร้อมซิงก์ขึ้นคลาวด์:
/// - `id` เป็น UUID (ไม่ใช่ autoincrement) เพื่อไม่ให้ id ชนกันเวลาสร้างจากหลายเครื่อง
/// - `updated_at` เป็น epoch millisecond ใช้ตัดสินว่าฝั่งไหนใหม่กว่า (last-write-wins)
/// - `deleted` เป็น soft delete เพื่อให้ลบฝั่งหนึ่งแล้วซิงก์ไปลบอีกฝั่งได้
/// - `dirty` = 1 แปลว่าแถวนี้ถูกแก้ในเครื่องแล้วยังไม่ได้ส่งขึ้นเซิร์ฟเวอร์
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _dbName = 'carcare.db';

  /// v2: เพิ่มแคตตาล็อกยี่ห้อ/รุ่นรถ และผูก vehicles เข้ากับแคตตาล็อกด้วย id
  static const _dbVersion = 2;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await applySchema(db);
        await seedCarCatalog(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final stmt in _catalogSchema) {
            await db.execute(stmt);
          }
          await db.execute('ALTER TABLE vehicles ADD COLUMN make_id TEXT');
          await db.execute('ALTER TABLE vehicles ADD COLUMN model_id TEXT');
          await seedCarCatalog(db);
        }
      },
      onOpen: (db) async {
        // รุ่นรถใหม่ ๆ ออกตลอด การ seed ซ้ำตอนเปิดจึงเติมรุ่นที่เพิ่มเข้ามา
        // ในเวอร์ชันแอพใหม่ให้ผู้ใช้เดิม โดยไม่ต้องขึ้น db version ใหม่ทุกครั้ง
        await seedCarCatalog(db);
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// สร้างตารางทั้งหมดลงฐานข้อมูลที่ส่งเข้ามา
  ///
  /// แยกออกมาเป็น public เพื่อให้เทสต์เปิดฐานข้อมูลในหน่วยความจำแล้วสร้างสคีมา
  /// ชุดเดียวกับของจริงได้ ไม่ต้องเขียน CREATE TABLE ซ้ำในเทสต์ให้เพี้ยนจากกัน
  static Future<void> applySchema(DatabaseExecutor db) async {
    for (final stmt in _schema) {
      await db.execute(stmt);
    }
  }

  /// ใช้ในเทสต์เท่านั้น
  Future<void> wipe() async {
    final db = await database;
    for (final t in ['service_records', 'maintenance_tasks', 'fuel_entries', 'vehicles']) {
      await db.delete(t);
    }
  }

  static const List<String> _schema = [
    '''
    CREATE TABLE vehicles (
      id            TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      make          TEXT,
      model         TEXT,
      -- อ้างถึงแคตตาล็อกกลาง ใช้จับกลุ่มสถิติของรถรุ่นเดียวกันข้ามผู้ใช้
      -- เก็บชื่อเป็นข้อความไว้ด้วยเพื่อให้แสดงผลได้แม้แถวในแคตตาล็อกหาย
      make_id       TEXT,
      model_id      TEXT,
      year          INTEGER,
      plate         TEXT,
      fuel_type     TEXT,
      tank_capacity REAL,
      initial_odo   REAL NOT NULL DEFAULT 0,
      is_active     INTEGER NOT NULL DEFAULT 1,
      sort_order    INTEGER NOT NULL DEFAULT 0,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL,
      deleted       INTEGER NOT NULL DEFAULT 0,
      dirty         INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE fuel_entries (
      id              TEXT PRIMARY KEY,
      vehicle_id      TEXT NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
      date            INTEGER NOT NULL,
      odometer        REAL NOT NULL,
      liters          REAL NOT NULL,
      price_per_liter REAL,
      total_cost      REAL,
      is_full_tank    INTEGER NOT NULL DEFAULT 1,
      missed_entries  INTEGER NOT NULL DEFAULT 0,
      fuel_type       TEXT,
      station         TEXT,
      note            TEXT,
      created_at      INTEGER NOT NULL,
      updated_at      INTEGER NOT NULL,
      deleted         INTEGER NOT NULL DEFAULT 0,
      dirty           INTEGER NOT NULL DEFAULT 1
    )
    ''',
    'CREATE INDEX idx_fuel_vehicle_odo ON fuel_entries(vehicle_id, odometer)',
    'CREATE INDEX idx_fuel_vehicle_date ON fuel_entries(vehicle_id, date)',
    '''
    CREATE TABLE maintenance_tasks (
      id                 TEXT PRIMARY KEY,
      vehicle_id         TEXT NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
      name               TEXT NOT NULL,
      category           TEXT,
      interval_km        REAL,
      interval_months    INTEGER,
      notify_km_before   REAL    NOT NULL DEFAULT 500,
      notify_days_before INTEGER NOT NULL DEFAULT 7,
      is_active          INTEGER NOT NULL DEFAULT 1,
      sort_order         INTEGER NOT NULL DEFAULT 0,
      created_at         INTEGER NOT NULL,
      updated_at         INTEGER NOT NULL,
      deleted            INTEGER NOT NULL DEFAULT 0,
      dirty              INTEGER NOT NULL DEFAULT 1
    )
    ''',
    'CREATE INDEX idx_task_vehicle ON maintenance_tasks(vehicle_id)',
    '''
    CREATE TABLE service_records (
      id         TEXT PRIMARY KEY,
      vehicle_id TEXT NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
      task_id    TEXT REFERENCES maintenance_tasks(id) ON DELETE SET NULL,
      title      TEXT NOT NULL,
      date       INTEGER NOT NULL,
      odometer   REAL NOT NULL,
      cost       REAL,
      workshop   TEXT,
      note       TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted    INTEGER NOT NULL DEFAULT 0,
      dirty      INTEGER NOT NULL DEFAULT 1
    )
    ''',
    'CREATE INDEX idx_service_vehicle_date ON service_records(vehicle_id, date)',
    'CREATE INDEX idx_service_task ON service_records(task_id, date)',
    ..._catalogSchema,
  ];

  /// แคตตาล็อกยี่ห้อ/รุ่นรถ แยกออกมาเพราะต้องสร้างทั้งตอน onCreate และตอน migrate จาก v1
  static const List<String> _catalogSchema = [
    '''
    CREATE TABLE car_makes (
      id         TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      name_th    TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_custom  INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted    INTEGER NOT NULL DEFAULT 0,
      dirty      INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE car_models (
      id         TEXT PRIMARY KEY,
      make_id    TEXT NOT NULL REFERENCES car_makes(id) ON DELETE CASCADE,
      name       TEXT NOT NULL,
      body_type  TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_custom  INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted    INTEGER NOT NULL DEFAULT 0,
      dirty      INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_model_make ON car_models(make_id, sort_order)',
  ];
}
