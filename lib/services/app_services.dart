import 'dart:async';

import '../data/local_changes.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'feedback_service.dart';
import 'sync_service.dart';

/// จุดรวมของบริการที่ต้องใช้ร่วมกันทั้งแอพ
///
/// แอพนี้ยังไม่ใหญ่พอจะต้องใช้ dependency injection เต็มรูปแบบ
/// แต่ ApiClient ต้องมีตัวเดียว เพราะโทเคนเซสชันอยู่ในนั้น
/// ถ้าสร้างใหม่ทีละหน้าจะกลายเป็นว่าบางหน้าล็อกอินอยู่ บางหน้าไม่
class AppServices {
  AppServices._();

  static final AppServices instance = AppServices._();

  /// ที่อยู่เซิร์ฟเวอร์ — ตั้งตอน build ได้ด้วย
  /// `flutter run --dart-define=CARCARE_API=https://carcare.example.com`
  static const apiBaseUrl = String.fromEnvironment(
    'CARCARE_API',
    defaultValue: 'https://carcare.example.com',
  );

  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.3+4',
  );

  /// web client id จาก Google Cloud Console
  ///
  /// จำเป็นบน Android — ไม่มีค่านี้ GoogleSignIn จะไม่คืน id_token ให้เลย
  /// ตั้งตอน build ด้วย `--dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com`
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  late final ApiClient api = ApiClient(baseUrl: apiBaseUrl);
  late final AuthService auth = AuthService(
    api: api,
    serverClientId: googleServerClientId,
  );
  late final SyncService sync = SyncService(api: api);
  late final FeedbackService feedback = FeedbackService(api: api);

  Timer? _debounce;

  /// อ่านเซสชันที่เก็บไว้ เรียกครั้งเดียวตอนเปิดแอพ
  Future<void> init() async {
    await auth.restore();

    // ฟังการแก้ข้อมูลในเครื่อง แล้วสั่งซิงก์ให้เอง ผู้ใช้จะได้ไม่ต้องจำว่าต้องกดปุ่ม
    LocalChanges.instance.addListener(_onLocalChange);
  }

  /// รวบการแก้หลายครั้งติด ๆ กันให้ซิงก์รอบเดียว
  ///
  /// การบันทึกหนึ่งครั้งของผู้ใช้แตะฐานข้อมูลหลายแถว (เช่น สร้างรถแล้ว seed
  /// รายการบำรุงรักษา 19 รายการ) ถ้ายิงซิงก์ทุกแถวจะกลายเป็นสิบกว่ารอบติดกัน
  void _onLocalChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      unawaited(sync.autoSync());
    });
  }

  /// เรียกตอนเปิดแอพและตอนกลับมาจากพื้นหลัง
  ///
  /// ใช้ minInterval สั้นกว่าปกติ เพราะการกลับมาเปิดแอพเป็นจังหวะที่ผู้ใช้
  /// คาดหวังจะเห็นข้อมูลล่าสุดจากเครื่องอื่นพอดี
  Future<void> syncOnResume() =>
      sync.autoSync(minInterval: const Duration(seconds: 5));
}
