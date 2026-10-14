import 'package:flutter/material.dart';

import '../models/service_record.dart';
import '../services/maintenance_status.dart';
import 'format.dart';
import 'service_form_screen.dart';
import 'task_form_screen.dart';
import 'vehicle_data.dart';

/// แท็บ "บำรุงรักษา" — รายการที่ต้องทำตามรอบ พร้อมประวัติที่ทำไปแล้ว
class MaintenanceTab extends StatelessWidget {
  const MaintenanceTab({super.key, required this.data, required this.onChanged});

  final VehicleData data;
  final VoidCallback onChanged;

  Future<void> _open(BuildContext context, Widget screen) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (changed == true) onChanged();
  }

  Future<void> _tapTask(BuildContext context, TaskStatus status) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(status.task.name),
              subtitle: Text(status.task.intervalLabel),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('บันทึกว่าทำแล้ว'),
              onTap: () => Navigator.of(context).pop('record'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('แก้ไขรายการ/รอบ'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'record') {
      await _open(
        context,
        ServiceFormScreen(data: data, presetTask: status.task),
      );
    } else {
      await _open(
        context,
        TaskFormScreen(vehicleId: data.vehicle.id, task: status.task),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (data.statuses.isEmpty)
          _EmptyTasks(
            onAdd: () => _open(context, TaskFormScreen(vehicleId: data.vehicle.id)),
          )
        else ...[
          for (final status in data.statuses) ...[
            _TaskTile(status: status, onTap: () => _tapTask(context, status)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _open(context, TaskFormScreen(vehicleId: data.vehicle.id)),
            icon: const Icon(Icons.add),
            label: const Text('เพิ่มรายการบำรุงรักษา'),
          ),
        ],
        if (data.records.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('ประวัติที่ทำไปแล้ว', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final record in data.records) ...[
            _RecordTile(
              record: record,
              onTap: () => _open(context, ServiceFormScreen(data: data, record: record)),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.status, required this.onTap});

  final TaskStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _levelColor(context, status.level);
    final progress = status.progress;

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(status.task.name, style: theme.textTheme.titleSmall),
                  ),
                  Text(
                    status.summaryLabel,
                    style: theme.textTheme.labelMedium?.copyWith(color: color),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (progress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                _detailLine(status),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _detailLine(TaskStatus status) {
    final parts = <String>[status.task.intervalLabel];

    if (status.neverServiced) {
      parts.add('ยังไม่เคยบันทึกว่าทำ');
    } else {
      final last = status.lastRecord!;
      parts.add('ล่าสุด ${Fmt.date(last.dateTime)} ที่ ${Fmt.km(last.odometer)}');
    }

    if (status.dueOdometer != null) {
      parts.add('ครบที่ ${Fmt.km(status.dueOdometer!)}');
    }
    if (status.dueDate != null) {
      parts.add('ครบวันที่ ${Fmt.date(status.dueDate!)}');
    }
    return parts.join(' · ');
  }

  Color _levelColor(BuildContext context, DueLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      DueLevel.overdue => scheme.error,
      DueLevel.dueSoon => Colors.orange.shade800,
      DueLevel.ok => Colors.green.shade700,
      DueLevel.noInterval => scheme.outline,
    };
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onTap});

  final ServiceRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      Fmt.km(record.odometer),
      if (record.cost != null) Fmt.bahtRound(record.cost!),
      if (record.workshop != null) record.workshop!,
    ];

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(record.title),
        subtitle: Text('${Fmt.date(record.dateTime)} · ${details.join(' · ')}'),
        trailing: Text(
          Fmt.ago(record.dateTime),
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 48),
        Icon(Icons.build_outlined, size: 64, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text('ยังไม่มีรายการบำรุงรักษา', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'เพิ่มรายการที่ต้องทำตามรอบ เช่น เปลี่ยนถ่ายน้ำมันเครื่อง\nแล้วแอพจะบอกว่าครบกำหนดเมื่อไร',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('เพิ่มรายการ'),
        ),
      ],
    );
  }
}
