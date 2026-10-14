import 'package:flutter/material.dart';

import '../data/fuel_repository.dart';
import '../models/fuel_entry.dart';
import '../models/fuel_types.dart';
import '../services/fuel_math.dart';
import 'format.dart';
import 'odometer_scan.dart';
import 'vehicle_data.dart';

/// ฟอร์มบันทึก/แก้ไขการเติมน้ำมัน
///
/// ส่ง [entry] มาถ้าเป็นการแก้ไข คืนค่า true เมื่อบันทึกหรือลบสำเร็จ
class FuelFormScreen extends StatefulWidget {
  const FuelFormScreen({super.key, required this.data, this.entry});

  final VehicleData data;
  final FuelEntry? entry;

  @override
  State<FuelFormScreen> createState() => _FuelFormScreenState();
}

class _FuelFormScreenState extends State<FuelFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = FuelRepository();

  late final TextEditingController _odo;
  late final TextEditingController _liters;
  late final TextEditingController _price;
  late final TextEditingController _total;
  late final TextEditingController _station;
  late final TextEditingController _note;

  late DateTime _date;
  late bool _isFullTank;
  late bool _missedEntries;
  String? _fuelType;
  bool _saving = false;

  /// ลำดับที่ผู้ใช้แตะสามช่องนี้ ตัวหน้าสุดคือช่องที่เพิ่งแก้ล่าสุด
  ///
  /// ช่องที่อยู่ท้ายสุดคือช่องที่ถูกคำนวณให้ — คนกรอกลิตรกับราคาแล้วอยากได้ยอดรวม
  /// จึงตั้งต้นให้ยอดรวมอยู่ท้าย พอผู้ใช้ไปแก้ยอดรวมเอง ช่องที่ถูกคำนวณ
  /// ก็เลื่อนไปเป็นราคาต่อลิตรโดยอัตโนมัติ
  final _editOrder = <FuelField>[
    FuelField.liters,
    FuelField.pricePerLiter,
    FuelField.total,
  ];

  /// กันไม่ให้การเขียนค่าที่คำนวณได้ลงช่อง ไปกระตุ้น listener ซ้อนตัวเอง
  bool _updating = false;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _odo = TextEditingController(text: e == null ? '' : _plain(e.odometer));
    _liters = TextEditingController(text: e == null ? '' : _plain(e.liters));
    _price = TextEditingController(
      text: e?.pricePerLiter == null ? '' : _plain(e!.pricePerLiter!),
    );
    _total = TextEditingController(
      text: e?.totalCost == null ? '' : _plain(e!.totalCost!),
    );
    _station = TextEditingController(text: e?.station ?? '');
    _note = TextEditingController(text: e?.note ?? '');

    _date = e?.dateTime ?? DateTime.now();
    _isFullTank = e?.isFullTank ?? true;
    _missedEntries = e?.missedEntries ?? false;
    // เติมครั้งใหม่มักใช้เชื้อเพลิงเดิมกับครั้งก่อน จึงตั้งค่าให้ล่วงหน้า
    _fuelType = e?.fuelType ??
        (e == null
            ? (widget.data.entries.isNotEmpty
                ? widget.data.entries.last.fuelType
                : widget.data.vehicle.fuelType)
            : null);

    // ถ้าเปิดมาแก้รายการที่มีทั้งลิตรและยอดรวมอยู่แล้ว แต่ไม่มีราคาต่อลิตร
    // ให้ราคาเป็นช่องที่คำนวณ จะได้ไม่ไปทับยอดรวมที่ผู้ใช้เคยกรอกไว้เอง
    if (e != null && e.totalCost != null && e.pricePerLiter == null) {
      _editOrder
        ..remove(FuelField.pricePerLiter)
        ..add(FuelField.pricePerLiter);
    }

    _liters.addListener(_onLitersEdited);
    _price.addListener(_onPriceEdited);
    _total.addListener(_onTotalEdited);
  }

  @override
  void dispose() {
    _liters.removeListener(_onLitersEdited);
    _price.removeListener(_onPriceEdited);
    _total.removeListener(_onTotalEdited);
    for (final c in [_odo, _liters, _price, _total, _station, _note]) {
      c.dispose();
    }
    super.dispose();
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

  void _onLitersEdited() => _handleEdit(FuelField.liters);
  void _onPriceEdited() => _handleEdit(FuelField.pricePerLiter);
  void _onTotalEdited() => _handleEdit(FuelField.total);

  /// ผู้ใช้แก้ช่องไหน ให้ช่องนั้นขึ้นหน้าสุด แล้วคำนวณช่องท้ายสุดใหม่
  void _handleEdit(FuelField field) {
    if (_updating) return;

    _editOrder
      ..remove(field)
      ..insert(0, field);

    _recompute();
  }

  void _recompute() {
    final target = _editOrder.last;
    final value = deriveFuelValue(
      target: target,
      liters: _parse(_liters),
      pricePerLiter: _parse(_price),
      total: _parse(_total),
    );

    // คำนวณไม่ได้ก็ปล่อยค่าเดิมไว้ ไม่ล้างทิ้ง — ผู้ใช้อาจแค่ลบตัวเลขออกชั่วคราว
    // ระหว่างพิมพ์แก้ ถ้าล้างให้ทุกครั้งค่าที่เขาเพิ่งกรอกจะหายไปกลางคัน
    if (value != null) {
      final controller = _controllerOf(target);
      final text = _formatDerived(value);
      if (controller.text != text) {
        _updating = true;
        controller.text = text;
        _updating = false;
      }
    }

    setState(() {});
  }

  TextEditingController _controllerOf(FuelField field) => switch (field) {
        FuelField.liters => _liters,
        FuelField.pricePerLiter => _price,
        FuelField.total => _total,
      };

  static String _labelOf(FuelField field) => switch (field) {
        FuelField.liters => 'จำนวนลิตร',
        FuelField.pricePerLiter => 'ราคา/ลิตร',
        FuelField.total => 'ยอดรวม',
      };

  /// ตัดศูนย์ท้ายทิ้ง เพื่อไม่ให้ขึ้นเป็น "1400.00" หรือ "38.50"
  static String _formatDerived(double v) {
    if (v == v.roundToDouble()) return v.round().toString();

    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _scanOdometer() async {
    final value = await scanOdometer(
      context,
      currentOdometer: widget.data.odometer,
    );
    if (value == null) return;

    _odo.text = _plain(value);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      // คงเวลาเดิมไว้ เปลี่ยนเฉพาะวัน
      _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute);
    });
  }

  /// เตือนเมื่อเลขไมล์ไม่เดินหน้าจากครั้งก่อน เพราะมักเกิดจากกรอกผิด
  /// แต่ไม่บังคับ เผื่อผู้ใช้กรอกย้อนหลังจริง ๆ
  Future<bool> _confirmOdometer(double odometer) async {
    final previous = widget.data.entries
        .where((e) => e.id != widget.entry?.id)
        .where((e) => e.date <= _date.millisecondsSinceEpoch)
        .fold<double?>(null, (max, e) => max == null || e.odometer > max ? e.odometer : max);

    if (previous == null || odometer > previous) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เลขไมล์ไม่เดินหน้า'),
        content: Text(
          'ครั้งก่อนหน้าบันทึกไว้ที่ ${Fmt.km(previous)} '
          'แต่ครั้งนี้กรอก ${Fmt.km(odometer)}\n\n'
          'ถ้ายืนยัน ช่วงนี้จะคำนวณอัตราสิ้นเปลืองไม่ได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('กลับไปแก้'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final odometer = _parse(_odo)!;
    if (!await _confirmOdometer(odometer)) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final e = widget.entry!;
        // สร้างใหม่ทั้งอ็อบเจ็กต์ เพื่อให้ล้างค่าในช่องที่เคยกรอกไว้ได้
        await _repo.upsert(FuelEntry(
          id: e.id,
          vehicleId: e.vehicleId,
          date: _date.millisecondsSinceEpoch,
          odometer: odometer,
          liters: _parse(_liters)!,
          pricePerLiter: _parse(_price),
          totalCost: _parse(_total),
          isFullTank: _isFullTank,
          missedEntries: _missedEntries,
          fuelType: _fuelType,
          station: _trimmed(_station),
          note: _trimmed(_note),
          createdAt: e.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          deleted: e.deleted,
        ));
      } else {
        await _repo.create(
          vehicleId: widget.data.vehicle.id,
          date: _date.millisecondsSinceEpoch,
          odometer: odometer,
          liters: _parse(_liters)!,
          pricePerLiter: _parse(_price),
          totalCost: _parse(_total),
          isFullTank: _isFullTank,
          missedEntries: _missedEntries,
          fuelType: _fuelType,
          station: _trimmed(_station),
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
        title: const Text('ลบรายการนี้?'),
        content: const Text('อัตราสิ้นเปลืองของช่วงที่เกี่ยวข้องจะถูกคำนวณใหม่'),
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

    await _repo.softDelete(widget.entry!.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final derived = _editOrder.last;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขการเติมน้ำมัน' : 'บันทึกการเติมน้ำมัน'),
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
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('วันที่เติม: ${Fmt.dateFull(_date)}'),
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
              key: const Key('fuel-liters'),
              controller: _liters,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'จำนวนลิตร *',
                suffixText: 'ล.',
              ),
              validator: (v) {
                final value = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                if (value == null) return 'กรุณากรอกจำนวนลิตร';
                if (value <= 0) return 'จำนวนลิตรต้องมากกว่า 0';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('fuel-price'),
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'ราคา/ลิตร',
                      suffixText: 'บ.',
                    ),
                    validator: (v) => _positiveOrEmpty(v, 'ราคา'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('fuel-total'),
                    controller: _total,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'ยอดรวม',
                      suffixText: 'บ.',
                    ),
                    validator: (v) => _positiveOrEmpty(v, 'ยอดรวม'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'กรอกสองช่อง ช่องที่เหลือคำนวณให้เอง — ตอนนี้คำนวณ “${_labelOf(derived)}” '
              'ถ้าแก้ช่องนั้นเอง แอพจะย้ายไปคำนวณช่องที่ไม่ได้แตะนานที่สุดแทน',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _fuelType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ชนิดเชื้อเพลิง'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('ไม่ระบุ')),
                ...kFuelTypes.map(
                  (f) => DropdownMenuItem<String>(value: f, child: Text(f)),
                ),
              ],
              onChanged: (v) => setState(() => _fuelType = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _station,
              decoration: const InputDecoration(
                labelText: 'ปั๊ม',
                hintText: 'ปตท. สาขาบางนา',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'หมายเหตุ'),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isFullTank,
              onChanged: (v) => setState(() => _isFullTank = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('เติมเต็มถัง'),
              subtitle: const Text('ต้องเต็มถังถึงจะคำนวณอัตราสิ้นเปลืองได้'),
            ),
            CheckboxListTile(
              value: _missedEntries,
              onChanged: (v) => setState(() => _missedEntries = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('มีการเติมครั้งก่อนที่ลืมบันทึก'),
              subtitle: const Text('ช่วงนี้จะถูกข้ามในการคำนวณอัตราสิ้นเปลือง'),
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

  String? _positiveOrEmpty(String? v, String label) {
    if (v == null || v.trim().isEmpty) return null;
    final value = double.tryParse(v.trim().replaceAll(',', ''));
    if (value == null) return '$label ต้องเป็นตัวเลข';
    if (value < 0) return '$label ต้องไม่ติดลบ';
    return null;
  }
}
