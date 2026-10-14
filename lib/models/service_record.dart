/// ประวัติการเข้าศูนย์/อู่ที่ทำไปแล้วจริง
///
/// ถ้าผูกกับ [taskId] จะถือเป็น "ครั้งล่าสุดที่ทำ" ของรายการนั้น
/// และเป็นจุดตั้งต้นในการนับรอบถัดไป
class ServiceRecord {
  final String id;
  final String vehicleId;
  final String? taskId;
  final String title;
  final int date;
  final double odometer;
  final double? cost;
  final String? workshop;
  final String? note;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final bool dirty;

  const ServiceRecord({
    required this.id,
    required this.vehicleId,
    this.taskId,
    required this.title,
    required this.date,
    required this.odometer,
    this.cost,
    this.workshop,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = true,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date);

  ServiceRecord copyWith({
    String? taskId,
    String? title,
    int? date,
    double? odometer,
    double? cost,
    String? workshop,
    String? note,
    int? updatedAt,
    bool? deleted,
    bool? dirty,
    bool clearTaskId = false,
  }) {
    return ServiceRecord(
      id: id,
      vehicleId: vehicleId,
      taskId: clearTaskId ? null : (taskId ?? this.taskId),
      title: title ?? this.title,
      date: date ?? this.date,
      odometer: odometer ?? this.odometer,
      cost: cost ?? this.cost,
      workshop: workshop ?? this.workshop,
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
        'task_id': taskId,
        'title': title,
        'date': date,
        'odometer': odometer,
        'cost': cost,
        'workshop': workshop,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted': deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
      };

  factory ServiceRecord.fromMap(Map<String, Object?> m) => ServiceRecord(
        id: m['id'] as String,
        vehicleId: m['vehicle_id'] as String,
        taskId: m['task_id'] as String?,
        title: m['title'] as String,
        date: m['date'] as int,
        odometer: (m['odometer'] as num).toDouble(),
        cost: (m['cost'] as num?)?.toDouble(),
        workshop: m['workshop'] as String?,
        note: m['note'] as String?,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
        deleted: (m['deleted'] as int? ?? 0) == 1,
        dirty: (m['dirty'] as int? ?? 0) == 1,
      );
}
