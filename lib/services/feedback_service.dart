import 'dart:io' show Platform;

import 'api_client.dart';

/// ชนิดของฟีดแบ็ค — ค่า [wire] ต้องตรงกับ `CarCare\Feedback::KINDS` ฝั่งเซิร์ฟเวอร์
/// (เซิร์ฟเวอร์ปฏิเสธค่าที่ไม่รู้จัก ไม่ได้แปลงเป็น other ให้)
enum FeedbackKind {
  bug('bug', 'แจ้งปัญหา / บั๊ก'),
  idea('idea', 'ข้อเสนอแนะ'),
  other('other', 'อื่น ๆ');

  const FeedbackKind(this.wire, this.label);

  final String wire;
  final String label;
}

/// ส่งฟีดแบ็คของผู้ใช้ขึ้นเซิร์ฟเวอร์ (POST /api/feedback)
///
/// ไม่เก็บลงเครื่องและไม่เข้าคิวรอเน็ต — ฟีดแบ็คเป็นข้อความที่ผู้ใช้กำลังตั้งใจส่ง
/// อยู่ตรงหน้า ถ้าส่งไม่ผ่านต้องบอกเขาเดี๋ยวนั้นให้กดส่งใหม่ ดีกว่าเงียบไว้แล้ว
/// ส่งเองทีหลังโดยที่เขาไม่รู้ว่าส่งไปหรือยัง
class FeedbackService {
  FeedbackService({required this.api});

  /// ความยาวข้อความที่เซิร์ฟเวอร์รับ — ตรงกับ `Feedback::MESSAGE_MIN/MAX`
  /// ตรวจฝั่งนี้ก่อนเพื่อไม่ต้องให้ผู้ใช้รอ round trip เพื่อรู้ว่าพิมพ์สั้นไป
  static const messageMin = 5;
  static const messageMax = 4000;

  /// เวอร์ชันแอพที่แนบไปกับฟีดแบ็ค ตั้งตอน build ด้วย
  /// `--dart-define=APP_VERSION=1.0.3+4` ให้ตรงกับ `version` ใน pubspec.yaml
  ///
  /// ใช้ dart-define แบบเดียวกับ CARCARE_API แทนการเพิ่ม package อ่าน pubspec
  /// ตอนรัน — ค่า 'dev' จึงหมายถึงบิลด์ที่ไม่ได้ระบุเวอร์ชันมา (เครื่องนักพัฒนา)
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.3+4',
  );

  final ApiClient api;

  /// ส่งได้เฉพาะเมื่อล็อกอินแล้ว — เส้นทางนี้ต้องมีโทเคน
  bool get canSend => api.token != null;

  /// ส่งฟีดแบ็คหนึ่งชิ้น
  ///
  /// โยน [ApiException] เมื่อเซิร์ฟเวอร์ปฏิเสธ — ข้อความในนั้นเป็นภาษาไทย
  /// ที่เอาไปแสดงให้ผู้ใช้ได้เลย (รวมถึงกรณีส่งถี่เกินไป ซึ่งได้ 429 กลับมา)
  Future<void> send({
    required FeedbackKind kind,
    required String message,
    int? rating,
    String? contact,
  }) async {
    final trimmedContact = contact?.trim() ?? '';

    await api.post('/feedback', {
      'kind': kind.wire,
      'message': message.trim(),
      if (rating != null) 'rating': rating,
      if (trimmedContact.isNotEmpty) 'contact': trimmedContact,
      // สามค่านี้แนบให้เองเพราะบั๊กส่วนใหญ่ผูกกับเวอร์ชัน/ระบบปฏิบัติการ
      // ถ้าให้ผู้ใช้พิมพ์เองจะได้มาไม่ครบและไม่ตรงรูปแบบ
      'app_version': appVersion,
      'platform': Platform.operatingSystem,
      'device': _osVersion,
    });
  }

  /// เวอร์ชันของ OS — ตัดให้พอดีคอลัมน์ device (191) ก่อนส่ง
  ///
  /// เซิร์ฟเวอร์ตัดให้อยู่แล้ว แต่บางเครื่องคืนสตริงยาวหลายร้อยตัวอักษร
  /// ไม่มีเหตุให้ส่งส่วนที่ถูกทิ้งแน่ ๆ ขึ้นไป
  String get _osVersion {
    final version = Platform.operatingSystemVersion;

    return version.length <= 191 ? version : version.substring(0, 191);
  }
}
