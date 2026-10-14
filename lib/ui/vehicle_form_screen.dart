import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/maintenance_repository.dart';
import '../data/vehicle_repository.dart';
import '../models/car_catalog.dart';
import '../models/fuel_types.dart';
import '../models/vehicle.dart';
import 'catalog_picker_screen.dart';

/// ฟอร์มเพิ่ม/แก้ไขรถ
///
/// ส่ง [vehicle] มาถ้าเป็นการแก้ไข ไม่ส่งคือเพิ่มคันใหม่
/// คืนค่า true เมื่อมีการบันทึกหรือลบ เพื่อให้หน้าก่อนหน้าโหลดข้อมูลใหม่
class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({super.key, this.vehicle});

  final Vehicle? vehicle;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vehicles = VehicleRepository();
  final _maintenance = MaintenanceRepository();

  late final TextEditingController _name;
  late final TextEditingController _year;
  late final TextEditingController _plate;
  late final TextEditingController _tank;
  late final TextEditingController _odo;

  String? _fuelType;
  bool _seedTasks = true;
  bool _saving = false;

  // ยี่ห้อ/รุ่นเลือกจากแคตตาล็อก เก็บทั้ง id (ไว้รวมสถิติ) และชื่อ (ไว้แสดงผล)
  String? _makeId;
  String? _makeName;
  String? _modelId;
  String? _modelName;

  bool get _isEdit => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _name = TextEditingController(text: v?.name ?? '');
    _year = TextEditingController(text: v?.year?.toString() ?? '');
    _plate = TextEditingController(text: v?.plate ?? '');
    _tank = TextEditingController(text: v?.tankCapacity?.toString() ?? '');
    _odo = TextEditingController(
      text: v == null ? '' : v.initialOdo.round().toString(),
    );
    _fuelType = v?.fuelType;
    _makeId = v?.makeId;
    _makeName = v?.make;
    _modelId = v?.modelId;
    _modelName = v?.model;
  }

  @override
  void dispose() {
    for (final c in [_name, _year, _plate, _tank, _odo]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parseDouble(TextEditingController c) {
    final text = c.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String? _trimmed(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _pickMake() async {
    final make = await Navigator.of(context).push<CarMake>(
      MaterialPageRoute(builder: (_) => MakePickerScreen(selectedId: _makeId)),
    );
    if (make == null) return;

    setState(() {
      // เปลี่ยนยี่ห้อแล้วรุ่นเดิมย่อมใช้ไม่ได้ ต้องล้างทิ้ง
      if (make.id != _makeId) {
        _modelId = null;
        _modelName = null;
      }
      _makeId = make.id;
      _makeName = make.name;
    });
  }

  void _clearMake() {
    setState(() {
      _makeId = null;
      _makeName = null;
      _modelId = null;
      _modelName = null;
    });
  }

  Future<void> _pickModel() async {
    final model = await Navigator.of(context).push<CarModel>(
      MaterialPageRoute(
        builder: (_) => ModelPickerScreen(
          makeId: _makeId!,
          makeName: _makeName ?? '',
          selectedId: _modelId,
        ),
      ),
    );
    if (model == null) return;

    setState(() {
      _modelId = model.id;
      _modelName = model.name;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      if (_isEdit) {
        final v = widget.vehicle!;
        // สร้างอ็อบเจ็กต์ใหม่แทน copyWith เพราะ copyWith ตีความ null ว่า "ไม่เปลี่ยน"
        // ทำให้ผู้ใช้ลบค่าในช่องที่เคยกรอกไว้ไม่ได้
        await _vehicles.upsert(Vehicle(
          id: v.id,
          name: _name.text.trim(),
          make: _makeName,
          model: _modelName,
          makeId: _makeId,
          modelId: _modelId,
          year: int.tryParse(_year.text.trim()),
          plate: _trimmed(_plate),
          fuelType: _fuelType,
          tankCapacity: _parseDouble(_tank),
          initialOdo: _parseDouble(_odo) ?? 0,
          isActive: v.isActive,
          sortOrder: v.sortOrder,
          createdAt: v.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          deleted: v.deleted,
        ));
      } else {
        final created = await _vehicles.create(
          name: _name.text.trim(),
          make: _makeName,
          model: _modelName,
          makeId: _makeId,
          modelId: _modelId,
          year: int.tryParse(_year.text.trim()),
          plate: _trimmed(_plate),
          fuelType: _fuelType,
          tankCapacity: _parseDouble(_tank),
          initialOdo: _parseDouble(_odo) ?? 0,
        );
        if (_seedTasks) {
          await _maintenance.seedDefaultTasks(created.id);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบรถคันนี้?'),
        content: const Text(
          'ประวัติการเติมน้ำมันและการบำรุงรักษาของรถคันนี้จะถูกลบไปด้วย',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _vehicles.softDelete(widget.vehicle!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขข้อมูลรถ' : 'เพิ่มรถ'),
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'ลบรถ',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'ชื่อเรียกรถ *',
                hintText: 'เช่น รถบ้าน, รถคุณแม่',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อเรียกรถ' : null,
            ),
            const SizedBox(height: 16),
            _PickerField(
              label: 'ยี่ห้อ',
              value: _makeName,
              hint: 'เลือกยี่ห้อ',
              onTap: _pickMake,
              onClear: _makeName == null ? null : _clearMake,
            ),
            const SizedBox(height: 16),
            _PickerField(
              label: 'รุ่น',
              value: _modelName,
              hint: _makeId == null ? 'เลือกยี่ห้อก่อน' : 'เลือกรุ่น',
              onTap: _makeId == null ? null : _pickModel,
              onClear: _modelName == null
                  ? null
                  : () => setState(() {
                        _modelId = null;
                        _modelName = null;
                      }),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'ปี (ค.ศ.)',
                      hintText: '2019',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final year = int.tryParse(v.trim());
                      if (year == null || year < 1900 || year > 2100) {
                        return 'ปีไม่ถูกต้อง';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _plate,
                    decoration: const InputDecoration(
                      labelText: 'ทะเบียน',
                      hintText: '1กก 1234',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _fuelType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'เชื้อเพลิงที่ใช้ประจำ'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('ไม่ระบุ'),
                ),
                ...kFuelTypes.map(
                  (f) => DropdownMenuItem<String>(value: f, child: Text(f)),
                ),
              ],
              onChanged: (v) => setState(() => _fuelType = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tank,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'ความจุถัง (ลิตร)',
                      hintText: '42',
                    ),
                    validator: (v) => _positiveOrEmpty(v, 'ความจุถัง'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _odo,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'เลขไมล์ตั้งต้น',
                      hintText: '0',
                    ),
                    validator: (v) => _positiveOrEmpty(v, 'เลขไมล์'),
                  ),
                ),
              ],
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _seedTasks,
                onChanged: (v) => setState(() => _seedTasks = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('สร้างรายการบำรุงรักษามาตรฐานให้ด้วย'),
                subtitle: const Text(
                  'เปลี่ยนถ่ายน้ำมันเครื่อง ต่อภาษี พ.ร.บ. ฯลฯ แก้ไขรอบได้ภายหลัง',
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEdit ? 'บันทึกการแก้ไข' : 'เพิ่มรถ'),
            ),
          ],
        ),
      ),
    );
  }

  String? _positiveOrEmpty(String? v, String label) {
    if (v == null || v.trim().isEmpty) return null;
    final value = double.tryParse(v.trim().replaceAll(',', ''));
    if (value == null) return '$label ต้องเป็นตัวเลข';
    if (value < 0) return '$label ต้องไม่ติดลบ';
    return null;
  }
}

/// ช่องที่กดแล้วเปิดหน้าเลือก แทนการพิมพ์เอง
///
/// ใช้ [InputDecorator] เพื่อให้หน้าตาเหมือน TextFormField ช่องอื่นในฟอร์มเดียวกัน
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.hint,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String? value;
  final String hint;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: onClear == null
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: onClear,
                  tooltip: 'ล้างค่า',
                ),
        ),
        child: Text(
          value ?? hint,
          style: value == null
              ? theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor)
              : theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}
