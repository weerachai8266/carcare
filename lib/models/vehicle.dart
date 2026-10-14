class Vehicle {
  final String id;
  final String name;
  final String? make;
  final String? model;

  /// อ้างถึงแคตตาล็อกยี่ห้อ/รุ่น — null ถ้าผู้ใช้พิมพ์ชื่อเองโดยไม่ได้เลือกจากรายการ
  /// ใช้จับกลุ่มสถิติของรถรุ่นเดียวกัน จึงต้องเป็น id เดียวกันทุกเครื่อง
  final String? makeId;
  final String? modelId;

  final int? year;
  final String? plate;
  final String? fuelType;
  final double? tankCapacity;
  final double initialOdo;
  final bool isActive;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final bool dirty;

  const Vehicle({
    required this.id,
    required this.name,
    this.make,
    this.model,
    this.makeId,
    this.modelId,
    this.year,
    this.plate,
    this.fuelType,
    this.tankCapacity,
    this.initialOdo = 0,
    this.isActive = true,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = true,
  });

  /// บรรทัดรอง เช่น "Toyota Yaris · 2019 · 1กก 1234"
  String get subtitle {
    final parts = <String>[];
    final mm = [make, model].where((s) => s != null && s.isNotEmpty).join(' ');
    if (mm.isNotEmpty) parts.add(mm);
    if (year != null) parts.add('$year');
    if (plate != null && plate!.isNotEmpty) parts.add(plate!);
    return parts.join(' · ');
  }

  Vehicle copyWith({
    String? name,
    String? make,
    String? model,
    String? makeId,
    String? modelId,
    int? year,
    String? plate,
    String? fuelType,
    double? tankCapacity,
    double? initialOdo,
    bool? isActive,
    int? sortOrder,
    int? updatedAt,
    bool? deleted,
    bool? dirty,
  }) {
    return Vehicle(
      id: id,
      name: name ?? this.name,
      make: make ?? this.make,
      model: model ?? this.model,
      makeId: makeId ?? this.makeId,
      modelId: modelId ?? this.modelId,
      year: year ?? this.year,
      plate: plate ?? this.plate,
      fuelType: fuelType ?? this.fuelType,
      tankCapacity: tankCapacity ?? this.tankCapacity,
      initialOdo: initialOdo ?? this.initialOdo,
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
        'name': name,
        'make': make,
        'model': model,
        'make_id': makeId,
        'model_id': modelId,
        'year': year,
        'plate': plate,
        'fuel_type': fuelType,
        'tank_capacity': tankCapacity,
        'initial_odo': initialOdo,
        'is_active': isActive ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory Vehicle.fromMap(Map<String, Object?> m) => Vehicle(
        id: m['id'] as String,
        name: m['name'] as String,
        make: m['make'] as String?,
        model: m['model'] as String?,
        makeId: m['make_id'] as String?,
        modelId: m['model_id'] as String?,
        year: m['year'] as int?,
        plate: m['plate'] as String?,
        fuelType: m['fuel_type'] as String?,
        tankCapacity: (m['tank_capacity'] as num?)?.toDouble(),
        initialOdo: (m['initial_odo'] as num?)?.toDouble() ?? 0,
        isActive: (m['is_active'] as int? ?? 1) == 1,
        sortOrder: m['sort_order'] as int? ?? 0,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] as int? ?? 0) == 1,
        dirty: (m['dirty'] as int? ?? 0) == 1,
      );
}
