import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/maintenance_repository.dart';
import '../models/maintenance_task.dart';

/// ฟอร์มเพิ่ม/แก้ไขรายการบำรุงรักษา (รอบการทำ ไม่ใช่ประวัติที่ทำแล้ว)
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, required this.vehicleId, this.task});

  final String vehicleId;
  final MaintenanceTask? task;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = MaintenanceRepository();

  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _intervalKm;
  late final TextEditingController _intervalMonths;
  late final TextEditingController _notifyKm;
  late final TextEditingController _notifyDays;

  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _name = TextEditingController(text: t?.name ?? '');
    _category = TextEditingController(text: t?.category ?? '');
    _intervalKm = TextEditingController(
      text: t?.intervalKm == null ? '' : t!.intervalKm!.round().toString(),
    );
    _intervalMonths = TextEditingController(text: t?.intervalMonths?.toString() ?? '');
    _notifyKm = TextEditingController(text: (t?.notifyKmBefore ?? 500).round().toString());
    _notifyDays = TextEditingController(text: (t?.notifyDaysBefore ?? 7).toString());
    _isActive = t?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _category,
      _intervalKm,
      _intervalMonths,
      _notifyKm,
      _notifyDays,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parseDouble(TextEditingController c) {
    final text = c.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  int? _parseInt(TextEditingController c) {
    final text = c.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final intervalKm = _parseDouble(_intervalKm);
    final intervalMonths = _parseInt(_intervalMonths);
    if (intervalKm == null && intervalMonths == null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ไม่ได้ตั้งรอบ'),
          content: const Text(
            'ถ้าไม่กรอกทั้งรอบระยะทางและรอบเวลา แอพจะเตือนเมื่อครบกำหนดให้ไม่ได้',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('กลับไปกรอก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('บันทึกแบบนี้'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final t = widget.task!;
        // สร้างใหม่ทั้งอ็อบเจ็กต์ เพื่อให้ล้างรอบที่เคยตั้งไว้ได้
        await _repo.upsertTask(MaintenanceTask(
          id: t.id,
          vehicleId: t.vehicleId,
          name: _name.text.trim(),
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          intervalKm: intervalKm,
          intervalMonths: intervalMonths,
          notifyKmBefore: _parseDouble(_notifyKm) ?? 500,
          notifyDaysBefore: _parseInt(_notifyDays) ?? 7,
          isActive: _isActive,
          sortOrder: t.sortOrder,
          createdAt: t.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          deleted: t.deleted,
        ));
      } else {
        await _repo.createTask(
          vehicleId: widget.vehicleId,
          name: _name.text.trim(),
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          intervalKm: intervalKm,
          intervalMonths: intervalMonths,
          notifyKmBefore: _parseDouble(_notifyKm) ?? 500,
          notifyDaysBefore: _parseInt(_notifyDays) ?? 7,
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
        title: const Text('ลบรายการนี้?'),
        content: const Text('ประวัติที่เคยบันทึกไว้จะยังอยู่ แต่จะไม่ผูกกับรายการนี้แล้ว'),
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

    await _repo.softDeleteTask(widget.task!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขรายการบำรุงรักษา' : 'เพิ่มรายการบำรุงรักษา'),
        actions: [
          if (_isEdit)
            IconButton(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'ลบรายการ',
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
              decoration: const InputDecoration(
                labelText: 'ชื่อรายการ *',
                hintText: 'เช่น เปลี่ยนถ่ายน้ำมันเครื่อง',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อรายการ' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _category,
              decoration: const InputDecoration(
                labelText: 'หมวด',
                hintText: 'เครื่องยนต์, เบรก, เอกสาร',
              ),
            ),
            const SizedBox(height: 24),
            Text('รอบการทำ', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'กรอกอย่างน้อยหนึ่งช่อง ถ้ากรอกทั้งคู่จะยึดอันที่ถึงกำหนดก่อน',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _intervalKm,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'ทุก ๆ ระยะทาง',
                      suffixText: 'กม.',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _intervalMonths,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'ทุก ๆ เวลา',
                      suffixText: 'เดือน',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('เตือนล่วงหน้า', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _notifyKm,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'ก่อนถึงอีก',
                      suffixText: 'กม.',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _notifyDays,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'ก่อนถึงอีก',
                      suffixText: 'วัน',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('ใช้งานรายการนี้'),
              subtitle: const Text('ปิดไว้ถ้ายังไม่อยากให้แสดงและเตือน'),
            ),
            const SizedBox(height: 16),
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
