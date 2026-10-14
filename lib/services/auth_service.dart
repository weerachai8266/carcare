import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// ผู้ใช้ที่ล็อกอินอยู่
class AccountInfo {
  final String email;
  final String? name;
  final String? pictureUrl;

  const AccountInfo({required this.email, this.name, this.pictureUrl});

  Map<String, Object?> toJson() => {
        'email': email,
        'name': name,
        'picture': pictureUrl,
      };

  factory AccountInfo.fromJson(Map<String, Object?> json) => AccountInfo(
        email: json['email'] as String? ?? '',
        name: json['name'] as String?,
        pictureUrl: json['picture'] as String?,
      );
}

/// ล็อกอินด้วย Google แล้วแลกเป็นโทเคนของเซิร์ฟเวอร์เรา
///
/// โทเคนถูกเก็บใน shared_preferences ไม่ใช่ในหน่วยความจำ เพื่อให้ปิดแอพแล้ว
/// ไม่ต้องล็อกอินใหม่ทุกครั้ง
class AuthService {
  AuthService({
    required this.api,
    String serverClientId = '',
    GoogleSignIn? googleSignIn,
  }) : _google = googleSignIn ??
            GoogleSignIn(
              scopes: const ['email', 'profile'],
              // บน Android ถ้าไม่ส่ง serverClientId (web client id) มาด้วย
              // GoogleSignIn จะคืน idToken เป็น null เสมอ แล้วล็อกอินไม่ผ่านทั้งระบบ
              // ส่วน iOS ใช้ค่านี้เป็น audience ของ token ที่จะส่งให้เซิร์ฟเวอร์เช่นกัน
              serverClientId: serverClientId.isEmpty ? null : serverClientId,
            );

  static const _tokenKey = 'auth_token';
  static const _emailKey = 'auth_email';
  static const _nameKey = 'auth_name';
  static const _pictureKey = 'auth_picture';

  final ApiClient api;
  final GoogleSignIn _google;

  AccountInfo? _account;
  AccountInfo? get account => _account;
  bool get isSignedIn => api.token != null;

  /// อ่านโทเคนที่เก็บไว้ตอนเปิดแอพ เรียกครั้งเดียวตอนเริ่ม
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString(_tokenKey);

    final email = prefs.getString(_emailKey);
    if (email != null) {
      _account = AccountInfo(
        email: email,
        name: prefs.getString(_nameKey),
        pictureUrl: prefs.getString(_pictureKey),
      );
    }
  }

  /// เปิดหน้าเลือกบัญชี Google แล้วแลก id_token เป็นโทเคนของเรา
  ///
  /// คืน null ถ้าผู้ใช้กดยกเลิกเอง (ไม่ใช่ข้อผิดพลาด จึงไม่โยน exception)
  Future<AccountInfo?> signIn({String? deviceName}) async {
    final googleUser = await _google.signIn();
    if (googleUser == null) return null;

    final auth = await googleUser.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const ApiException(0, 'Google ไม่ได้ส่ง id_token กลับมา');
    }

    final response = await api.post('/auth/google', {
      'id_token': idToken,
      if (deviceName != null) 'device_name': deviceName,
    });

    final prefs = await SharedPreferences.getInstance();
    api.token = response['token'] as String;
    await prefs.setString(_tokenKey, api.token!);

    final user = (response['user'] as Map).cast<String, Object?>();
    _account = AccountInfo.fromJson(user);
    await prefs.setString(_emailKey, _account!.email);
    await _writeOrRemove(prefs, _nameKey, _account!.name);
    await _writeOrRemove(prefs, _pictureKey, _account!.pictureUrl);

    return _account;
  }

  Future<void> signOut() async {
    // แจ้งเซิร์ฟเวอร์ให้เพิกถอนโทเคน แต่ถ้าเน็ตล่มก็ต้องออกจากระบบในเครื่องให้ได้อยู่ดี
    try {
      if (api.token != null) await api.post('/auth/logout', const {});
    } on ApiException {
      // ตั้งใจกลืน — โทเคนจะหมดอายุเองตามกำหนด
    }

    await _google.signOut();
    api.token = null;
    _account = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_pictureKey);
  }

  /// เคลียร์เซสชันในเครื่องเมื่อเซิร์ฟเวอร์บอกว่าโทเคนใช้ไม่ได้แล้ว
  Future<void> handleUnauthorized() async {
    await signOut();
  }

  Future<void> _writeOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}
