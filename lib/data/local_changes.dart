import 'package:flutter/foundation.dart';

/// ประกาศว่ามีข้อมูลในเครื่องถูกแก้และยังไม่ได้ส่งขึ้นเซิร์ฟเวอร์
///
/// ชั้นข้อมูลไม่ควรรู้จักการซิงก์ (จะกลายเป็นพึ่งพากันย้อนทาง และเทสต์ของ
/// repository จะลากเอาเน็ตเวิร์กเข้ามาด้วย) จึงแค่ส่งสัญญาณออกมาเฉย ๆ
/// ใครสนใจก็ไปฟังเอง — ตอนนี้มี AppServices ตัวเดียวที่ฟังเพื่อสั่งซิงก์อัตโนมัติ
class LocalChanges extends ChangeNotifier {
  LocalChanges._();

  static final LocalChanges instance = LocalChanges._();

  /// เรียกหลังเขียนข้อมูลที่ผู้ใช้เป็นคนแก้ (ไม่ใช่ข้อมูลที่ดึงลงมาจากเซิร์ฟเวอร์)
  void notifyChanged() => notifyListeners();
}
