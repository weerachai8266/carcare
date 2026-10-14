import 'package:shared_preferences/shared_preferences.dart';

import '../data/sync_dao.dart';
import 'api_client.dart';

/// ผลของการซิงก์หนึ่งรอบ ใช้แสดงให้ผู้ใช้เห็นว่าทำอะไรไปบ้าง
class SyncResult {
  final int pushed;
  final int pulled;
  final DateTime at;

  const SyncResult({required this.pushed, required this.pulled, required this.at});

  String get summary => pushed == 0 && pulled == 0
      ? 'ข้อมูลตรงกับเซิร์ฟเวอร์อยู่แล้ว'
      : 'ส่งขึ้น $pushed รายการ · รับลง $pulled รายการ';
}

/// ซิงก์ข้อมูลสองทางกับเซิร์ฟเวอร์
///
/// รอบหนึ่งคือ: รวบรวมแถวที่ dirty → ส่งขึ้นพร้อมเคอร์เซอร์ `since` →
/// เขียนแถวที่ได้กลับมาลงเครื่อง → ล้างธง dirty → จำเคอร์เซอร์ใหม่
class SyncService {
  SyncService({required this.api, SyncDao? dao}) : dao = dao ?? SyncDao();

  static const _sinceKey = 'sync_since';
  static const _lastSyncKey = 'sync_last_at';

  final ApiClient api;
  final SyncDao dao;

  /// กันไม่ให้ซิงก์สองรอบทับกัน — รอบที่สองจะส่งแถวเดิมซ้ำและอาจล้างธง dirty
  /// ของการแก้ที่เกิดระหว่างรอบแรกทิ้ง
  bool _running = false;

  DateTime? _lastAttempt;

  bool get isRunning => _running;

  Future<int> get _since async =>
      (await SharedPreferences.getInstance()).getInt(_sinceKey) ?? 0;

  /// เวลาที่ซิงก์สำเร็จครั้งล่าสุด — null ถ้ายังไม่เคยซิงก์
  Future<DateTime?> lastSyncedAt() async {
    final millis = (await SharedPreferences.getInstance()).getInt(_lastSyncKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// ซิงก์แบบเบื้องหลัง — ไม่โยน exception ออกมา และข้ามรอบเมื่อไม่ควรทำ
  ///
  /// เน็ตหลุดระหว่างขับรถเป็นเรื่องปกติ ถ้าปล่อยให้ error เด้งขึ้นจอทุกครั้ง
  /// ผู้ใช้จะรำคาญจนปิดการซิงก์ทิ้ง ข้อมูลที่ยังไม่ได้ส่งยังคงธง dirty ไว้อยู่แล้ว
  /// รอบหน้าจึงส่งขึ้นไปได้เอง
  ///
  /// คืน true เมื่อซิงก์สำเร็จจริงในรอบนี้
  Future<bool> autoSync({Duration minInterval = const Duration(seconds: 20)}) async {
    if (_running) return false;
    if (api.token == null) return false;

    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return false;
    }

    try {
      await sync();
      return true;
    } catch (_) {
      // เงียบไว้ตั้งใจ — ดูสถานะได้ที่หน้าบัญชี ซึ่งบอกเวลาที่ซิงก์สำเร็จล่าสุด
      return false;
    }
  }

  Future<SyncResult> sync() async {
    _running = true;
    _lastAttempt = DateTime.now();
    try {
      return await _syncOnce();
    } finally {
      _running = false;
    }
  }

  Future<SyncResult> _syncOnce() async {
    final since = await _since;

    // เก็บแถวที่ส่งไว้ก่อน เพื่อล้างธง dirty เฉพาะแถวที่ส่งไปจริง
    // ถ้าไปล้างทั้งตารางหลังซิงก์ การแก้ที่เกิดระหว่างรอเซิร์ฟเวอร์ตอบจะหายไปเงียบ ๆ
    final sentUserRows = <String, List<Map<String, Object?>>>{};
    for (final table in SyncDao.userTables) {
      sentUserRows[table] = await dao.dirtyRows(table);
    }

    final sentCatalogRows = <String, List<Map<String, Object?>>>{};
    for (final table in SyncDao.catalogTables) {
      sentCatalogRows[table] = await dao.dirtyCustomRows(table);
    }

    final response = await api.post('/sync', {
      'since': since,
      'changes': sentUserRows,
      'catalog': sentCatalogRows,
    });

    var pulled = 0;
    final changes = (response['changes'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final table in SyncDao.userTables) {
      pulled += await dao.applyRows(table, _rowsOf(changes[table]));
    }

    final catalog = (response['catalog'] as Map?)?.cast<String, dynamic>() ?? {};
    pulled += await dao.applyRows('car_makes', _rowsOf(catalog['makes']));
    pulled += await dao.applyRows('car_models', _rowsOf(catalog['models']));

    for (final entry in sentUserRows.entries) {
      await dao.markClean(entry.key, entry.value);
    }
    for (final entry in sentCatalogRows.entries) {
      await dao.markClean(entry.key, entry.value);
    }

    final serverTime = (response['server_time'] as num?)?.toInt() ?? since;
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sinceKey, serverTime);
    await prefs.setInt(_lastSyncKey, now.millisecondsSinceEpoch);

    final pushed = sentUserRows.values.fold<int>(0, (sum, rows) => sum + rows.length) +
        sentCatalogRows.values.fold<int>(0, (sum, rows) => sum + rows.length);

    return SyncResult(pushed: pushed, pulled: pulled, at: now);
  }

  /// ล้างเคอร์เซอร์ ใช้ตอนออกจากระบบ เพื่อให้บัญชีถัดไปดึงข้อมูลใหม่ทั้งหมด
  Future<void> resetCursor() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sinceKey);
    await prefs.remove(_lastSyncKey);
  }

  /// ส่งข้อมูลในเครื่องขึ้นใหม่ทั้งหมด ใช้เมื่อข้อมูลฝั่งเซิร์ฟเวอร์หายไป
  ///
  /// ล้างเคอร์เซอร์อย่างเดียวไม่พอ เพราะมันคุมแค่ขาดึงลง ต้องตั้งธง dirty
  /// ให้ทุกแถวด้วยถึงจะถูกหยิบไปส่ง
  Future<SyncResult> resyncEverything() async {
    await dao.markAllDirty();
    await resetCursor();

    return sync();
  }

  List<Map<String, Object?>> _rowsOf(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList();
  }
}
