/// รายการบำรุงรักษาที่ต้องทำซ้ำตามรอบ เช่น "เปลี่ยนถ่ายน้ำมันเครื่อง ทุก 10,000 กม. หรือ 6 เดือน"
///
/// รอบกำหนดได้ทั้งระยะทาง ระยะเวลา หรือทั้งคู่
/// ถ้ากำหนดทั้งคู่ ให้ยึดอันที่ถึงกำหนดก่อน (ตามคู่มือรถทั่วไป)
class MaintenanceTask {
  final String id;
  final String vehicleId;
  final String name;
  final String? category;

  /// รอบตามระยะทาง (กม.) — null = ไม่ใช้เกณฑ์นี้
  final double? intervalKm;

  /// รอบตามเวลา (เดือน) — null = ไม่ใช้เกณฑ์นี้
  final int? intervalMonths;

  /// เตือนล่วงหน้ากี่กิโลเมตรก่อนถึงกำหนด
  final double notifyKmBefore;

  /// เตือนล่วงหน้ากี่วันก่อนถึงกำหนด
  final int notifyDaysBefore;

  final bool isActive;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final bool dirty;

  const MaintenanceTask({
    required this.id,
    required this.vehicleId,
    required this.name,
    this.category,
    this.intervalKm,
    this.intervalMonths,
    this.notifyKmBefore = 500,
    this.notifyDaysBefore = 7,
    this.isActive = true,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = true,
  });

  /// คำอธิบายรอบแบบอ่านง่าย เช่น "ทุก 10,000 กม. หรือ 6 เดือน"
  String get intervalLabel {
    final parts = <String>[];
    if (intervalKm != null) {
      parts.add('${_thousands(intervalKm!)} กม.');
    }
    if (intervalMonths != null) {
      parts.add(intervalMonths! % 12 == 0 && intervalMonths! >= 12
          ? '${intervalMonths! ~/ 12} ปี'
          : '$intervalMonths เดือน');
    }
    if (parts.isEmpty) return 'ไม่ได้ตั้งรอบ';
    return 'ทุก ${parts.join(' หรือ ')}';
  }

  static String _thousands(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  MaintenanceTask copyWith({
    String? name,
    String? category,
    double? intervalKm,
    int? intervalMonths,
    double? notifyKmBefore,
    int? notifyDaysBefore,
    bool? isActive,
    int? sortOrder,
    int? updatedAt,
    bool? deleted,
    bool? dirty,
    bool clearIntervalKm = false,
    bool clearIntervalMonths = false,
  }) {
    return MaintenanceTask(
      id: id,
      vehicleId: vehicleId,
      name: name ?? this.name,
      category: category ?? this.category,
      intervalKm: clearIntervalKm ? null : (intervalKm ?? this.intervalKm),
      intervalMonths: clearIntervalMonths ? null : (intervalMonths ?? this.intervalMonths),
      notifyKmBefore: notifyKmBefore ?? this.notifyKmBefore,
      notifyDaysBefore: notifyDaysBefore ?? this.notifyDaysBefore,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      deleted: deleted ?? this.deleted,
      dirty: dirty ?? true,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'vehicle_id': vehicleId,
        'name': name,
        'category': category,
        'interval_km': intervalKm,
        'interval_months': intervalMonths,
        'notify_km_before': notifyKmBefore,
        'notify_days_before': notifyDaysBefore,
        'is_active': isActive ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory MaintenanceTask.fromMap(Map<String, Object?> m) => MaintenanceTask(
        id: m['id'] as String,
        vehicleId: m['vehicle_id'] as String,
        name: m['name'] as String,
        category: m['category'] as String?,
        intervalKm: (m['interval_km'] as num?)?.toDouble(),
        intervalMonths: m['interval_months'] as int?,
        notifyKmBefore: (m['notify_km_before'] as num?)?.toDouble() ?? 500,
        notifyDaysBefore: m['notify_days_before'] as int? ?? 7,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        sortOrder: m['sort_order'] as int? ?? 0,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] as int? ?? 0) == 1,
        dirty: (m['dirty'] as int? ?? 0) == 1,
      );
}

/// เทมเพลตรายการบำรุงรักษามาตรฐาน ใช้ตอนสร้างรถคันใหม่
/// ค่ารอบอ้างอิงจากคู่มือรถยนต์ทั่วไปในไทย ผู้ใช้แก้ได้ภายหลัง
class TaskTemplate {
  final String name;
  final String category;
  final double? intervalKm;
  final int? intervalMonths;

  const TaskTemplate(this.name, this.category, this.intervalKm, this.intervalMonths);

  static const List<TaskTemplate> defaults = [
    TaskTemplate('เปลี่ยนถ่ายน้ำมันเครื่อง', 'เครื่องยนต์', 10000, 6),
    TaskTemplate('เปลี่ยนกรองน้ำมันเครื่อง', 'เครื่องยนต์', 10000, 6),
    TaskTemplate('สลับยาง', 'ยางและช่วงล่าง', 10000, 6),
    TaskTemplate('ตั้งศูนย์ถ่วงล้อ', 'ยางและช่วงล่าง', 20000, 12),
    TaskTemplate('เปลี่ยนกรองอากาศ', 'เครื่องยนต์', 20000, 12),
    TaskTemplate('เปลี่ยนกรองแอร์', 'ภายในห้องโดยสาร', 20000, 12),
    TaskTemplate('เปลี่ยนใบปัดน้ำฝน', 'ภายนอก', null, 12),
    TaskTemplate('เปลี่ยนหัวเทียน', 'เครื่องยนต์', 40000, null),
    TaskTemplate('เปลี่ยนน้ำมันเบรก', 'เบรก', 40000, 24),
    TaskTemplate('เปลี่ยนผ้าเบรกหน้า', 'เบรก', 40000, null),
    TaskTemplate('เปลี่ยนน้ำมันเกียร์', 'ระบบส่งกำลัง', 40000, 24),
    TaskTemplate('เปลี่ยนน้ำยาหล่อเย็นหม้อน้ำ', 'ระบบระบายความร้อน', 40000, 24),
    TaskTemplate('เปลี่ยนสายพานราวลิ้น', 'เครื่องยนต์', 100000, null),
    TaskTemplate('เปลี่ยนยางรถยนต์', 'ยางและช่วงล่าง', 50000, 60),
    TaskTemplate('เปลี่ยนแบตเตอรี่', 'ไฟฟ้า', 60000, 36),
    TaskTemplate('ต่อภาษีรถยนต์ (ป้ายวงกลม)', 'เอกสาร', null, 12),
    TaskTemplate('ต่อ พ.ร.บ.', 'เอกสาร', null, 12),
    TaskTemplate('ต่อประกันภัยรถยนต์', 'เอกสาร', null, 12),
    TaskTemplate('ตรวจสภาพรถ (ตรอ.)', 'เอกสาร', null, 12),
  ];
}
