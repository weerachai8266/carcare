/// การเติมน้ำมันหนึ่งครั้ง — เป็นแหล่งข้อมูลหลักที่ทำให้แอพรู้เลขกิโลเมตรของรถ
class FuelEntry {
  final String id;
  final String vehicleId;

  /// เวลาที่เติม (epoch millisecond)
  final int date;

  /// เลขไมล์บนหน้าปัด ณ ตอนเติม
  final double odometer;

  final double liters;
  final double? pricePerLiter;
  final double? totalCost;

  /// เติมเต็มถังหรือไม่ — จำเป็นต่อการคำนวณอัตราสิ้นเปลืองให้ถูกต้อง
  final bool isFullTank;

  /// ผู้ใช้ยอมรับว่ามีการเติมครั้งก่อนหน้าที่ไม่ได้บันทึกไว้
  /// ทำให้ช่วงนี้คำนวณอัตราสิ้นเปลืองไม่ได้ ต้องข้ามไป
  final bool missedEntries;

  final String? fuelType;
  final String? station;
  final String? note;

  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final bool dirty;

  const FuelEntry({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.odometer,
    required this.liters,
    this.pricePerLiter,
    this.totalCost,
    this.isFullTank = true,
    this.missedEntries = false,
    this.fuelType,
    this.station,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = true,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date);

  /// ราคาต่อลิตร ถ้าไม่ได้กรอกไว้ก็คำนวณย้อนจากยอดรวม
  double? get effectivePricePerLiter {
    if (pricePerLiter != null) return pricePerLiter;
    if (totalCost != null && liters > 0) return totalCost! / liters;
    return null;
  }

  /// ยอดรวม ถ้าไม่ได้กรอกไว้ก็คำนวณจากราคาต่อลิตร
  double? get effectiveTotalCost {
    if (totalCost != null) return totalCost;
    if (pricePerLiter != null) return pricePerLiter! * liters;
    return null;
  }

  FuelEntry copyWith({
    int? date,
    double? odometer,
    double? liters,
    double? pricePerLiter,
    double? totalCost,
    bool? isFullTank,
    bool? missedEntries,
    String? fuelType,
    String? station,
    String? note,
    int? updatedAt,
    bool? deleted,
    bool? dirty,
  }) {
    return FuelEntry(
      id: id,
      vehicleId: vehicleId,
      date: date ?? this.date,
      odometer: odometer ?? this.odometer,
      liters: liters ?? this.liters,
      pricePerLiter: pricePerLiter ?? this.pricePerLiter,
      totalCost: totalCost ?? this.totalCost,
      isFullTank: isFullTank ?? this.isFullTank,
      missedEntries: missedEntries ?? this.missedEntries,
      fuelType: fuelType ?? this.fuelType,
      station: station ?? this.station,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      deleted: deleted ?? this.deleted,
      dirty: dirty ?? true,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'vehicle_id': vehicleId,
        'date': date,
        'odometer': odometer,
        'liters': liters,
        'price_per_liter': pricePerLiter,
        'total_cost': totalCost,
        'is_full_tank': isFullTank ? 1 : 0,
        'missed_entries': missedEntries ? 1 : 0,
        'fuel_type': fuelType,
        'station': station,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory FuelEntry.fromMap(Map<String, Object?> m) => FuelEntry(
        id: m['id'] as String,
        vehicleId: m['vehicle_id'] as String,
        date: m['date'] as int,
        odometer: (m['odometer'] as num).toDouble(),
        liters: (m['liters'] as num).toDouble(),
        pricePerLiter: (m['price_per_liter'] as num?)?.toDouble(),
        totalCost: (m['total_cost'] as num?)?.toDouble(),
        isFullTank: (m['is_full_tank'] as int? ?? 1) == 1,
        missedEntries: (m['missed_entries'] as int? ?? 0) == 1,
        fuelType: m['fuel_type'] as String?,
        station: m['station'] as String?,
        note: m['note'] as String?,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] as int? ?? 0) == 1,
        dirty: (m['dirty'] as int? ?? 0) == 1,
      );
}
