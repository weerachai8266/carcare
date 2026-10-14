import 'dart:convert';

import 'package:http/http.dart' as http;

/// ข้อผิดพลาดที่ได้จากเซิร์ฟเวอร์ พร้อมข้อความภาษาไทยที่เอาไปแสดงให้ผู้ใช้ได้เลย
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  /// เซสชันหมดอายุหรือถูกเพิกถอน — ฝั่งเรียกใช้ต้องพาผู้ใช้ไปล็อกอินใหม่
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// ตัวเรียก API ของเซิร์ฟเวอร์ carcare
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// เช่น `https://carcare.example.com` (ไม่ต้องมี /api ต่อท้าย)
  final String baseUrl;
  final http.Client _client;

  /// โทเคนเซสชัน — ตั้งค่าใหม่ทุกครั้งที่ล็อกอิน/ออกจากระบบ
  String? token;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/api$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    final response = await _client.get(_uri(path, query), headers: _headers);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json;
    try {
      // อ่านเป็น utf8 เองแทน response.body เพราะ http จะเดา latin-1
      // เมื่อ header ไม่ได้ระบุ charset ทำให้ข้อความไทยกลายเป็นตัวขยะ
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(response.statusCode, 'เซิร์ฟเวอร์ตอบกลับมาไม่ถูกรูปแบบ');
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        json['error'] as String? ?? 'เกิดข้อผิดพลาด (${response.statusCode})',
      );
    }
    return json;
  }

  void close() => _client.close();
}
