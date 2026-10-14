import 'dart:convert';

import 'package:carcare/services/api_client.dart';
import 'package:carcare/services/feedback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// ตรวจรูปร่างของสิ่งที่ส่งขึ้น /api/feedback
///
/// ฝั่งเซิร์ฟเวอร์ปฏิเสธชนิดที่ไม่รู้จักและข้อความสั้นเกินไป ถ้าคีย์หรือค่าที่ส่ง
/// ไม่ตรงกับที่ตกลงกันไว้ ผู้ใช้จะเจอ error ทั้งที่กรอกถูก — เทสต์นี้กันจุดนั้น
void main() {
  /// เซิร์ฟเวอร์จำลองที่รับฟีดแบ็คสำเร็จ และเก็บคำขอไว้ให้ตรวจ
  http.Client okServer({
    void Function(http.Request request, Map<String, dynamic> body)? onPost,
  }) {
    return MockClient((request) async {
      onPost?.call(request, jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({'ok': true, 'id': 7, 'duplicate': false}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  FeedbackService serviceWith(http.Client client, {String? token = 'tok'}) {
    final api = ApiClient(baseUrl: 'https://example.invalid', client: client);
    api.token = token;

    return FeedbackService(api: api);
  }

  test('ยังไม่ล็อกอิน ต้องรู้ตัวว่าส่งไม่ได้', () {
    expect(serviceWith(okServer(), token: null).canSend, isFalse);
    expect(serviceWith(okServer()).canSend, isTrue);
  });

  test('ส่งขึ้น /api/feedback พร้อมโทเคนและข้อมูลเครื่อง', () async {
    http.Request? request;
    Map<String, dynamic>? body;
    final service = serviceWith(okServer(onPost: (req, sent) {
      request = req;
      body = sent;
    }));

    await service.send(
      kind: FeedbackKind.bug,
      message: 'กราฟค่าน้ำมันหายไปหลังลบรายการ',
      rating: 4,
      contact: 'me@example.com',
    );

    expect(request!.method, 'POST');
    expect(request!.url.path, '/api/feedback');
    expect(request!.headers['Authorization'], 'Bearer tok');

    expect(body!['kind'], 'bug');
    expect(body!['message'], 'กราฟค่าน้ำมันหายไปหลังลบรายการ');
    expect(body!['rating'], 4);
    expect(body!['contact'], 'me@example.com');
    // ต้องมีค่าจริง ไม่ใช่คีย์เปล่า ไม่งั้นตามบั๊กตามเวอร์ชันไม่ได้
    expect(body!['app_version'], isNotEmpty);
    expect(body!['platform'], isNotEmpty);
  });

  test('ค่าที่ผู้ใช้ไม่ได้ให้ ต้องไม่ส่งคีย์ขึ้นไปเลย', () async {
    Map<String, dynamic>? body;
    final service = serviceWith(okServer(onPost: (_, sent) => body = sent));

    // contact เป็นช่องว่างล้วน = ไม่ได้กรอก ต้องไม่กลายเป็นสตริงว่างในฐานข้อมูล
    await service.send(
      kind: FeedbackKind.idea,
      message: '  อยากได้กราฟเทียบรายเดือน  ',
      contact: '   ',
    );

    expect(body!.containsKey('rating'), isFalse);
    expect(body!.containsKey('contact'), isFalse);
    expect(body!['message'], 'อยากได้กราฟเทียบรายเดือน');
    expect(body!['kind'], 'idea');
  });

  test('ชนิดทุกค่าต้องตรงกับที่เซิร์ฟเวอร์รับ', () {
    // ค่าเหล่านี้คือ CarCare\Feedback::KINDS — เปลี่ยนฝั่งใดฝั่งหนึ่งแล้วพัง 400
    expect(
      FeedbackKind.values.map((k) => k.wire),
      containsAll(<String>['bug', 'idea', 'other']),
    );
  });

  test('ส่งถี่เกินไป (429) ต้องได้ข้อความของเซิร์ฟเวอร์ออกมาแสดง', () async {
    final service = serviceWith(MockClient((_) async => http.Response(
          jsonEncode({'error': 'ส่งฟีดแบ็คถี่เกินไป กรุณารอสักครู่แล้วลองใหม่'}),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        )));

    await expectLater(
      service.send(kind: FeedbackKind.other, message: 'ทดสอบส่งซ้ำ ๆ'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having((e) => e.message, 'message', contains('ถี่เกินไป'))
          // 429 ไม่ใช่เซสชันหมดอายุ ต้องไม่พาผู้ใช้ไปล็อกอินใหม่
          .having((e) => e.isUnauthorized, 'isUnauthorized', isFalse)),
    );
  });
}
