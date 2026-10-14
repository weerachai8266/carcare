import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/app_services.dart';
import 'ui/vehicle_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // อ่านเซสชันที่เก็บไว้ก่อนวาดหน้าแรก เพื่อไม่ให้หน้าจอกะพริบจาก
  // "ยังไม่ได้ล็อกอิน" ไปเป็น "ล็อกอินแล้ว"
  await AppServices.instance.init();
  runApp(const CarCareApp());
}

class CarCareApp extends StatefulWidget {
  const CarCareApp({super.key});

  @override
  State<CarCareApp> createState() => _CarCareAppState();
}

class _CarCareAppState extends State<CarCareApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ซิงก์ตอนเปิดแอพ เผื่อมีข้อมูลจากเครื่องอื่นหรือของค้างที่ยังส่งไม่สำเร็จ
    AppServices.instance.syncOnResume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // กลับมาจากพื้นหลังคือจังหวะที่ผู้ใช้กำลังจะดูข้อมูล ควรให้ตรงกับเซิร์ฟเวอร์ก่อน
    if (state == AppLifecycleState.resumed) {
      AppServices.instance.syncOnResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'บันทึกรถ',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const VehicleListScreen(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}
