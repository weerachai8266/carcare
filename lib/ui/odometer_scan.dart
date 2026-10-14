import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/odometer_ocr.dart';
import '../services/odometer_scanner.dart';
import 'format.dart';

/// ถ่ายรูปเรือนไมล์แล้วให้ผู้ใช้เลือกตัวเลขที่อ่านได้ — คืน null ถ้ายกเลิก
///
/// ไม่กรอกให้อัตโนมัติแม้จะมีตัวเลือกที่คะแนนดีที่สุดอยู่แล้ว เพราะ OCR อ่านผิดได้
/// และเลขไมล์ที่ผิดจะทำให้อัตราสิ้นเปลืองกับกำหนดบำรุงรักษาเพี้ยนตามไปทั้งชุด
/// ให้คนยืนยันด้วยตาหนึ่งครั้งคุ้มกว่ามาก
Future<double?> scanOdometer(
  BuildContext context, {
  double? currentOdometer,
  OdometerScanner scanner = const OdometerScanner(),
}) async {
  final source = await _pickSource(context);
  if (source == null || !context.mounted) return null;

  List<String>? lines;
  Object? error;
  try {
    lines = await scanner.readLines(source);
  } catch (e) {
    error = e;
  }

  if (!context.mounted) return null;

  if (error != null) {
    _toast(context, 'อ่านรูปไม่สำเร็จ: $error');
    return null;
  }
  // ผู้ใช้กดยกเลิกตอนเลือกรูป
  if (lines == null) return null;

  final candidates = odometerCandidates(lines, currentOdometer: currentOdometer);
  if (candidates.isEmpty) {
    _toast(context, 'ไม่พบตัวเลขในรูป ลองถ่ายให้ชัดและเต็มหน้าปัดอีกครั้ง');
    return null;
  }

  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    builder: (context) => _CandidateSheet(
      candidates: candidates,
      currentOdometer: currentOdometer,
    ),
  );
}

Future<ImageSource?> _pickSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('ถ่ายรูปเรือนไมล์'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('เลือกรูปที่ถ่ายไว้'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _CandidateSheet extends StatelessWidget {
  const _CandidateSheet({required this.candidates, required this.currentOdometer});

  final List<OdometerCandidate> candidates;
  final double? currentOdometer;

  /// คงทศนิยมไว้ตามที่อ่านได้จริง — ปัด 312.5 เป็น 313 จะทำให้ผู้ใช้เทียบกับ
  /// บรรทัดดิบด้านล่างไม่ตรงกัน แล้วไม่รู้ว่าจะกดตัวไหน
  static String _label(double v) =>
      v == v.roundToDouble() ? Fmt.km(v) : '${Fmt.number(v)} กม.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('เลือกเลขไมล์ที่อ่านได้', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              currentOdometer == null || currentOdometer == 0
                  ? 'เรียงจากที่น่าจะใช่ที่สุด'
                  : 'เรียงจากที่น่าจะใช่ที่สุด โดยเทียบกับ ${Fmt.km(currentOdometer!)} ที่บันทึกไว้ล่าสุด',
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final c in candidates.take(6))
            ListTile(
              title: Text(_label(c.value), style: theme.textTheme.titleMedium),
              // โชว์บรรทัดดิบเมื่อมีตัวหนังสือประกอบ เพื่อให้ดูออกว่าเลขนี้มาจาก
              // ตรงไหนของหน้าปัด ถ้าบรรทัดมีแต่ตัวเลขก็ไม่ต้องเขียนซ้ำ
              subtitle: RegExp(r'[A-Za-zก-๙]').hasMatch(c.source)
                  ? Text(c.source)
                  : null,
              onTap: () => Navigator.of(context).pop(c.value),
            ),
        ],
      ),
    );
  }
}
