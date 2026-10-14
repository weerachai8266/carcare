import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// อ่านข้อความจากรูปเรือนไมล์ด้วย ML Kit ที่ทำงานในเครื่อง
///
/// แยกไฟล์ออกจาก [odometer_ocr.dart] เพราะไฟล์นี้แตะปลั๊กอินของแพลตฟอร์ม
/// ทดสอบด้วย unit test ไม่ได้ ส่วนตรรกะการเลือกตัวเลข ซึ่งเป็นจุดที่พลาดง่ายจริง ๆ
/// อยู่ในอีกไฟล์และทดสอบได้เต็มที่
class OdometerScanner {
  const OdometerScanner();

  /// ถ่ายรูป/เลือกรูป แล้วคืนข้อความที่อ่านได้ทีละบรรทัด
  ///
  /// คืน null ถ้าผู้ใช้ยกเลิกก่อนได้รูป
  Future<List<String>?> readLines(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // ตัวเลขบนหน้าปัดเล็ก ถ้าย่อรูปมากจะอ่านไม่ออก
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (picked == null) return null;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(picked.path),
      );

      return [
        for (final block in result.blocks)
          for (final line in block.lines) line.text,
      ];
    } finally {
      // ต้องปิดเสมอ ไม่งั้นโมเดลค้างในหน่วยความจำจนกว่าแอพจะถูกปิด
      await recognizer.close();
    }
  }
}
