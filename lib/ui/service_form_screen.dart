import 'package:flutter/material.dart';

import '../data/maintenance_repository.dart';
import '../models/maintenance_task.dart';
import '../models/service_record.dart';
import 'format.dart';
import 'odometer_scan.dart';
import 'vehicle_data.dart';

/// ฟอร์มบันทึก/แก้ไขประวัติการบำรุงรักษาที่ทำไปแล้ว
///
/// ถ้าผูกกับรายการบำรุงรักษา ([ServiceRecord.taskId]) รอบถัดไปจะนับต่อจากครั้งนี้
class ServiceFormScreen extends StatefulWidget {
  const ServiceFormScreen({
    super.key,
    required this.data,
    this.record,
    this.presetTask,
  });

  final VehicleData data;
  final ServiceRecord? record;

  /// รายการที่เลือกไว้ล่วงหน้า ใช้ตอนกดจากรายการที่ครบกำหนดโดยตรง
  final MaintenanceTask? presetTask;

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = MaintenanceRepository();

  late final TextEditingController _title;
  late final TextEditingController _odo;
  late final TextEditingController _cost;
  late final TextEditingController _workshop;
  late final TextEditingController _note;

  late DateTime _date;
  String? _taskId;
  bool _saving = false;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    final preset = widget.presetTask;

    _title = TextEditingController(text: r?.title ?? preset?.name ?? '');
    _odo = TextEditingController(
      text: (r?.odometer ?? widget.data.odometer).round().toString(),
    );
    _cost = TextEditingController(
      text: r?.cost == null ? '' : _plain(r!.cost!),
    );
    _workshop = TextEditingController(text: r?.workshop ?? '');
    _note = TextEditingController(text: r?.note ?? '');
    _date = r?.dateTime ?? DateTime.now();
    _taskId = r?.taskId ?? preset?.id;
  }

  @override
  void dispose() {
    for (final c in [_title, _odo, _cost, _workshop, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanOdometer() async {
    final value = await scanOdometer(
      context,
      currentOdometer: widget.data.odometer,
    );
    if (value == null) return;

    _odo.text = _plain(value);
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  double? _parse(TextEditingController c) {
    final text = c.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String? _trimmed(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  MaintenanceTask? _taskOf(String? id) {
    for (final t in widget.data.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// เลือกรายการบำรุงรักษาแล้วเติมชื่อให้อัตโนมัติ
  /// แต่ไม่ทับชื่อที่ผู้ใช้พิมพ์เองไว้แล้ว
  void _onTaskChanged(String? taskId) {
    setState(() {
      final previousName = _taskOf(_taskId)?.name;
      _taskId = taskId;

      final task = _taskOf(taskId);
      final current = _title.text.trim();
      if (task != null && (current.isEmpty || current == previousName)) {
        _title.text = task.name;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      if (_isEdit) {
        final r = widget.record!;
        // สร้างใหม่ทั้งอ็อบเจ็กต์ เพื่อให้ยกเลิกการผูกรายการหรือล้างค่าได้
        await _repo.upsertRecord(ServiceRecord(
          id: r.id,
          vehicleId: r.vehicleId,
          taskId: _taskId,
          title: _title.text.trim(),
          date: _date.millisecondsSinceEpoch,
          odometer: _parse(_odo)!,
          cost: _parse(_cost),
          workshop: _trimmed(_workshop),
          note: _trimmed(_note),
          createdAt: r.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          deleted: r.deleted,
        ));
      } else {
        await _repo.createRecord(
          vehicleId: widget.data.vehicle.id,
          taskId: _taskId,
          title: _title.text.trim(),
          date: _date.millisecondsSinceEpoch,
          odometer: _parse(_odo)!,
          cost: _parse(_cost),
          workshop: _trimmed(_workshop),
          note: _trimmed(_note),
        );
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
        title: const Text('ลบประวัตินี้?'),
        content: const Text('กำหนดครั้งถัดไปของรายการที่ผูกไว้จะถูกคำนวณใหม่'),
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

    await _repo.softDeleteRecord(widget.record!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขประวัติ' : 'บันทึกการบำรุงรักษา'),
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'ลบประวัติ',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            DropdownButtonFormField<String>(
              value: _taskId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'ผูกกับรายการบำรุงรักษา',
                helperText: 'ผูกไว้เพื่อให้แอพนับรอบครั้งถัดไปให้',
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('ไม่ผูก (บันทึกทั่วไป)'),
                ),
                ...widget.data.tasks.map(
                  (t) => DropdownMenuItem<String>(value: t.id, child: Text(t.name)),
                ),
              ],
              onChanged: _onTaskChanged,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'สิ่งที่ทำ *',
                hintText: 'เช่น เปลี่ยนถ่ายน้ำมันเครื่อง + กรอง',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรุณากรอกสิ่งที่ทำ' : null,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('วันที่ทำ: ${Fmt.dateFull(_date)}'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _odo,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'เลขไมล์ *',
                suffixText: 'กม.',
                suffixIcon: IconButton(
                  onPressed: _scanOdometer,
                  icon: const Icon(Icons.photo_camera_outlined),
                  tooltip: 'อ่านเลขไมล์จากรูป',
                ),
                helperText: 'ล่าสุดที่บันทึกไว้ ${Fmt.km(widget.data.odometer)}',
              ),
              validator: (v) {
                final value = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                if (value == null) return 'กรุณากรอกเลขไมล์';
                if (value < 0) return 'เลขไมล์ต้องไม่ติดลบ';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'ค่าใช้จ่าย', suffixText: 'บ.'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final value = double.tryParse(v.trim().replaceAll(',', ''));
                if (value == null) return 'ค่าใช้จ่ายต้องเป็นตัวเลข';
                if (value < 0) return 'ค่าใช้จ่ายต้องไม่ติดลบ';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _workshop,
              decoration: const InputDecoration(
                labelText: 'อู่/ศูนย์บริการ',
                hintText: 'ศูนย์โตโยต้า สาขา...',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'หมายเหตุ'),
            ),
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
              label: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}
