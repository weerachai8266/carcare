import 'dart:convert';

import 'package:carcare/data/app_database.dart';
import 'package:carcare/data/fuel_repository.dart';
import 'package:carcare/data/sync_dao.dart';
import 'package:carcare/data/vehicle_repository.dart';
import 'package:carcare/services/api_client.dart';
import 'package:carcare/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ตรวจกติกาของการซิงก์อัตโนมัติ ซึ่งทำงานเบื้องหลังและผู้ใช้ไม่เห็นว่าพลาด
/// จึงต้องมั่นใจว่ามันข้ามรอบตอนที่ควรข้าม และไม่ทำให้แอพพังตอนเน็ตหลุด
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SyncDao dao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    await AppDatabase.applySchema(db);
    dao = SyncDao(db: db);
  });

  tearDown(() async => db.close());

  /// เซิร์ฟเวอร์จำลองที่ตอบว่าไม่มีอะไรเปลี่ยนฝั่งโน้น
  http.Client okServer({void Function(Map<String, dynamic> body)? onPush}) {
    return MockClient((request) async {
      onPush?.call(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({
          'server_time': 1700000000000,
          'pushed': 0,
          'changes': <String, dynamic>{},
          'catalog': <String, dynamic>{},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  SyncService serviceWith(http.Client client, {String? token}) {
    final api = ApiClient(baseUrl: 'https://example.invalid', client: client);
    api.token = token;
    return SyncService(api: api, dao: dao);
  }

  test('ยังไม่ล็อกอิน ต้องไม่ยิงอะไรออกไปเลย', () async {
    var called = false;
    final service = serviceWith(
      MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    expect(await service.autoSync(), isFalse);
    expect(called, isFalse);
  });

  test('เน็ตล่ม ต้องไม่โยน error ออกมา', () async {
    final service = serviceWith(
      MockClient((_) async => throw const SocketExceptionLike()),
      token: 'tok',
    );

    expect(await service.autoSync(), isFalse);
  });

  test('เซิร์ฟเวอร์ตอบ 500 ก็ต้องเงียบเหมือนกัน', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{"error":"พัง"}', 500)),
      token: 'tok',
    );

    expect(await service.autoSync(), isFalse);
  });

  test('ซิงก์ติดกันถี่เกินไป ให้ข้ามรอบที่สอง', () async {
    var requests = 0;
    final service = serviceWith(
      okServer(onPush: (_) => requests++),
      token: 'tok',
    );

    expect(await service.autoSync(), isTrue);
    expect(await service.autoSync(), isFalse);
    expect(requests, 1);
  });

  test('ข้อมูลที่แก้ในเครื่องถูกส่งขึ้นในรอบถัดไป', () async {
    final vehicles = VehicleRepository(db: db);
    final fuel = FuelRepository(db: db);
    final vehicle = await vehicles.create(name: 'รถบ้าน', initialOdo: 1000);
    await fuel.create(
      vehicleId: vehicle.id,
      date: DateTime(2025, 1, 1).millisecondsSinceEpoch,
      odometer: 1000,
      liters: 40,
    );

    Map<String, dynamic>? sent;
    final service = serviceWith(
      okServer(onPush: (body) => sent = body),
      token: 'tok',
    );

    expect(await service.autoSync(), isTrue);

    final changes = sent!['changes'] as Map<String, dynamic>;
    expect((changes['vehicles'] as List), hasLength(1));
    expect((changes['fuel_entries'] as List), hasLength(1));

    // ส่งสำเร็จแล้วต้องไม่ค้างธง dirty ไว้ ไม่งั้นจะส่งซ้ำทุกรอบ
    expect(await dao.dirtyRows('vehicles'), isEmpty);
    expect(await dao.dirtyRows('fuel_entries'), isEmpty);
  });

  test('ซิงก์ล้มเหลว ธง dirty ต้องยังอยู่เพื่อส่งใหม่รอบหน้า', () async {
    final vehicles = VehicleRepository(db: db);
    await vehicles.create(name: 'รถบ้าน', initialOdo: 1000);

    final service = serviceWith(
      MockClient((_) async => http.Response('{"error":"พัง"}', 500)),
      token: 'tok',
    );

    expect(await service.autoSync(), isFalse);
    expect(await dao.dirtyRows('vehicles'), hasLength(1));
  });
}

/// ข้อผิดพลาดระดับเครือข่ายแบบที่ http โยนออกมาตอนต่อไม่ติด
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();

  @override
  String toString() => 'ต่อเซิร์ฟเวอร์ไม่ได้';
}
