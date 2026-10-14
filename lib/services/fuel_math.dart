/// สามช่องของการเติมน้ำมันที่ผูกกันด้วย ลิตร × ราคาต่อลิตร = ยอดรวม
enum FuelField { liters, pricePerLiter, total }

/// คำนวณค่าของช่อง [target] จากอีกสองช่อง — คืน null ถ้ายังคำนวณไม่ได้
///
/// คืน null แทนการคืน 0 เมื่อข้อมูลไม่พอหรือเป็นศูนย์ เพราะฟอร์มต้องแยกให้ออก
/// ระหว่าง "ยังคำนวณไม่ได้" กับ "คำนวณได้แล้วเป็นศูนย์" — ถ้ากลืนเป็น 0 เหมือนกันหมด
/// ช่องที่ผู้ใช้ยังไม่ได้กรอกจะถูกเติม 0 ทับทันทีที่พิมพ์ตัวแรก
double? deriveFuelValue({
  required FuelField target,
  double? liters,
  double? pricePerLiter,
  double? total,
}) {
  switch (target) {
    case FuelField.total:
      if (liters == null || pricePerLiter == null) return null;
      if (liters <= 0 || pricePerLiter <= 0) return null;
      return _round(liters * pricePerLiter);

    case FuelField.pricePerLiter:
      if (total == null || liters == null) return null;
      // ตัวหารต้องมากกว่าศูนย์จริง ๆ ไม่ใช่แค่ไม่ใช่ null
      if (liters <= 0 || total <= 0) return null;
      return _round(total / liters);

    case FuelField.liters:
      if (total == null || pricePerLiter == null) return null;
      if (pricePerLiter <= 0 || total <= 0) return null;
      return _round(total / pricePerLiter);
  }
}

/// ปัดสองตำแหน่ง พอสำหรับทั้งเงินบาทและจำนวนลิตร
double _round(double v) => (v * 100).roundToDouble() / 100;
