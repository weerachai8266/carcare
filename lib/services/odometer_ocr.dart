/// ตัวเลขหนึ่งตัวที่อ่านได้จากรูปเรือนไมล์ พร้อมคะแนนว่าน่าจะเป็นเลขไมล์แค่ไหน
class OdometerCandidate {
  /// ค่าที่แปลงเป็นตัวเลขแล้ว
  final double value;

  /// บรรทัดข้อความดิบที่ตัวเลขนี้อยู่ ใช้แสดงให้ผู้ใช้ตัดสินใจ
  final String source;

  final int score;

  const OdometerCandidate({
    required this.value,
    required this.source,
    required this.score,
  });
}

/// คำที่บอกว่าบรรทัดนั้นน่าจะเป็นเลขไมล์รวม
const _odoHints = ['odo', 'total', 'กม', 'km'];

/// คำที่บอกว่าบรรทัดนั้นเป็นมาตรวัดอื่น ไม่ใช่เลขไมล์รวม
///
/// ทริปมิเตอร์เป็นตัวหลอกที่เจอบ่อยที่สุด เพราะอยู่ติดกับเลขไมล์และหน้าตาเหมือนกัน
const _tripHints = [
  'trip',
  'avg',
  'range',
  'l/100',
  'km/l',
  'กม./ล.',
  'mpg',
  'rpm',
  'temp',
];

/// เรียงตัวเลขที่อ่านได้จากรูป โดยเดาว่าตัวไหนน่าจะเป็นเลขไมล์มากที่สุด
///
/// [lines] คือข้อความที่ OCR อ่านได้ทีละบรรทัด และ [currentOdometer] คือเลขไมล์
/// ล่าสุดที่บันทึกไว้ ซึ่งเป็นเบาะแสที่แรงที่สุด — เลขไมล์เดินหน้าอย่างเดียว
/// ตัวเลขที่น้อยกว่าของเดิมจึงแทบเป็นไปไม่ได้ และตัวที่มากกว่าเล็กน้อยน่าเชื่อที่สุด
///
/// คืนลิสต์เรียงจากน่าจะใช่ที่สุด ไม่ตัดตัวที่คะแนนต่ำทิ้ง เพราะ OCR พลาดได้เสมอ
/// และการให้ผู้ใช้เลือกเองยังดีกว่าการเดาผิดแล้วกรอกให้เงียบ ๆ
List<OdometerCandidate> odometerCandidates(
  List<String> lines, {
  double? currentOdometer,
}) {
  final found = <double, OdometerCandidate>{};

  for (final line in lines) {
    final lower = line.toLowerCase();
    final mentionsOdo = _odoHints.any(lower.contains);
    final mentionsTrip = _tripHints.any(lower.contains);
    // นาฬิกาบนหน้าปัด เช่น "10:42" ไม่ใช่ระยะทางแน่นอน
    final looksLikeClock = RegExp(r'\d\s*[:.]\s*\d{2}\b').hasMatch(line) &&
        RegExp(r'\d{1,2}\s*:\s*\d{2}').hasMatch(line);

    for (final match in RegExp(r'\d[\d.,\s]*\d|\d').allMatches(line)) {
      final raw = match.group(0)!;
      final value = _parseNumber(raw);
      if (value == null || value <= 0) continue;

      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '').length;
      // ตัวเลขสั้นกว่าสามหลักไม่ใช่เลขไมล์แน่ ๆ — เป็นนาฬิกา อุณหภูมิ หรือเกียร์
      // ตัดทิ้งตั้งแต่ตรงนี้ ไม่ให้ไปรกรายการที่ผู้ใช้ต้องเลือก
      if (digits < 3 || digits > 8) continue;

      final hasDecimal = RegExp(r'\.\d').hasMatch(raw.replaceAll(' ', ''));

      var score = 0;

      // เลขไมล์รถใช้งานจริงมักอยู่ที่ 4–7 หลัก
      if (digits >= 4 && digits <= 7) {
        score += 30;
      } else if (digits == 3) {
        score += 5;
      } else {
        score -= 20;
      }

      // ทริปมิเตอร์แสดงทศนิยมหนึ่งตำแหน่ง ส่วนเลขไมล์รวมเป็นจำนวนเต็ม
      if (hasDecimal) score -= 25;
      if (mentionsOdo) score += 15;
      if (mentionsTrip) score -= 30;
      if (looksLikeClock) score -= 30;

      if (currentOdometer != null && currentOdometer > 0) {
        final delta = value - currentOdometer;
        if (delta < 0) {
          // เลขไมล์ถอยหลังไม่ได้ แต่ยังไม่ตัดทิ้ง เผื่อผู้ใช้กรอกของเดิมผิด
          score -= 40;
        } else if (delta <= 2000) {
          score += 30;
        } else if (delta <= 20000) {
          score += 10;
        } else {
          score -= 10;
        }
      }

      // ตัวเลขเดียวกันอ่านเจอหลายที่ ให้เก็บอันที่คะแนนดีที่สุดไว้
      final existing = found[value];
      if (existing == null || score > existing.score) {
        found[value] = OdometerCandidate(
          value: value,
          source: line.trim(),
          score: score,
        );
      }
    }
  }

  final list = found.values.toList()
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      // คะแนนเท่ากันให้เลขมากขึ้นก่อน เพราะเลขไมล์รวมมักเป็นเลขที่ใหญ่ที่สุดบนหน้าปัด
      return byScore != 0 ? byScore : b.value.compareTo(a.value);
    });

  return list;
}

/// แปลงข้อความตัวเลขจาก OCR เป็น double
///
/// เรือนไมล์แบบดิจิทัลมักเว้นวรรคหลักพัน ("96 800") และ OCR ก็ใส่คอมมาเองบ้าง
/// ทั้งสองอย่างต้องตัดทิ้งก่อน เหลือจุดทศนิยมไว้อย่างเดียว
double? _parseNumber(String raw) {
  var text = raw.replaceAll(' ', '').replaceAll(',', '');

  // จุดที่ไม่ได้ตามด้วยตัวเลขคือจุดจบประโยค ไม่ใช่ทศนิยม
  text = text.replaceAll(RegExp(r'\.(?!\d)'), '');

  // จุดที่ตามด้วยเลขสามหลักพอดีคือตัวคั่นหลักพัน ไม่ใช่ทศนิยม ("96.800" = 96800)
  // ทริปมิเตอร์แสดงทศนิยมตำแหน่งเดียวเสมอ ("312.5") จึงแยกออกจากกันได้ด้วยจำนวนหลัก
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(text)) {
    text = text.replaceAll('.', '');
  } else if ('.'.allMatches(text).length > 1) {
    text = text.replaceAll('.', '');
  }

  return double.tryParse(text);
}
