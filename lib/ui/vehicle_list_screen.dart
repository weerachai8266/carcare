import 'package:flutter/material.dart';

import '../data/fuel_repository.dart';
import '../data/maintenance_repository.dart';
import '../data/vehicle_repository.dart';
import '../models/vehicle.dart';
import '../services/fuel_stats.dart';
import '../services/maintenance_status.dart';
import 'account_screen.dart';
import 'feedback_screen.dart';
import 'format.dart';
import 'vehicle_form_screen.dart';
import 'vehicle_home_screen.dart';

/// ข้อมูลย่อของรถหนึ่งคันสำหรับแสดงในหน้ารายการ
class VehicleCardData {
  final Vehicle vehicle;
  final double odometer;
  final int overdueCount;
  final int dueSoonCount;
  final double? avgKmPerLiter;

  const VehicleCardData({
    required this.vehicle,
    required this.odometer,
    required this.overdueCount,
    required this.dueSoonCount,
    this.avgKmPerLiter,
  });
}

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  final _vehicles = VehicleRepository();
  final _fuel = FuelRepository();
  final _maintenance = MaintenanceRepository();

  late Future<List<VehicleCardData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // ต้องใช้ body แบบวงเล็บปีกกา ไม่ใช่ arrow เพราะ arrow จะคืนค่า Future
  // ที่ได้จากการกำหนดค่าออกไป แล้ว setState จะ throw ทันที
  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<List<VehicleCardData>> _load() async {
    final vehicles = await _vehicles.all();
    final cards = <VehicleCardData>[];

    for (final vehicle in vehicles) {
      final odometer = await _vehicles.currentOdometer(vehicle.id);
      final tasks = await _maintenance.tasksForVehicle(vehicle.id);
      final records = await _maintenance.latestRecordPerTask(vehicle.id);
      final entries = await _fuel.forVehicleByOdometer(vehicle.id);

      final statuses = computeStatuses(
        vehicle: vehicle,
        tasks: tasks,
        latestRecords: records,
        currentOdometer: odometer,
        avgKmPerDay: avgKmPerDay(entries),
      );

      cards.add(VehicleCardData(
        vehicle: vehicle,
        odometer: odometer,
        overdueCount: statuses.where((s) => s.level == DueLevel.overdue).length,
        dueSoonCount: statuses.where((s) => s.level == DueLevel.dueSoon).length,
        avgKmPerLiter: summarize(entries).avgKmPerLiter,
      ));
    }
    return cards;
  }

  Future<void> _addVehicle() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const VehicleFormScreen()),
    );
    if (created == true && mounted) _reload();
  }

  Future<void> _openVehicle(Vehicle vehicle) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VehicleHomeScreen(vehicleId: vehicle.id)),
    );
    // กลับมาแล้วข้อมูลอาจเปลี่ยน (เติมน้ำมัน/บันทึกการเข้าอู่) จึงโหลดใหม่เสมอ
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('รถของฉัน'),
        actions: [
          IconButton(
            tooltip: 'ส่งฟีดแบ็ค',
            icon: const Icon(Icons.rate_review_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FeedbackScreen()),
            ),
          ),
          IconButton(
            tooltip: 'บัญชีและการซิงก์',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountScreen()),
              );
              // ซิงก์อาจดึงรถของเครื่องอื่นลงมา จึงต้องโหลดรายการใหม่
              if (mounted) _reload();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<VehicleCardData>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _reload);
          }

          final cards = snapshot.data ?? const [];
          if (cards.isEmpty) return _EmptyView(onAdd: _addVehicle);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _VehicleCard(
                data: cards[i],
                onTap: () => _openVehicle(cards[i].vehicle),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVehicle,
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มรถ'),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.data, required this.onTap});

  final VehicleCardData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = data.vehicle.subtitle;

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_car, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data.vehicle.name, style: theme.textTheme.titleMedium),
                        if (subtitle.isNotEmpty)
                          Text(subtitle, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    icon: Icons.speed,
                    label: Fmt.km(data.odometer),
                  ),
                  if (data.avgKmPerLiter != null)
                    _Chip(
                      icon: Icons.local_gas_station,
                      label: Fmt.kmPerLiter(data.avgKmPerLiter!),
                    ),
                  if (data.overdueCount > 0)
                    _Chip(
                      icon: Icons.error_outline,
                      label: 'เลยกำหนด ${data.overdueCount}',
                      color: theme.colorScheme.error,
                    ),
                  if (data.dueSoonCount > 0)
                    _Chip(
                      icon: Icons.schedule,
                      label: 'ใกล้ครบ ${data.dueSoonCount}',
                      color: Colors.orange.shade800,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car_outlined,
                size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('ยังไม่มีรถในระบบ', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'เพิ่มรถคันแรกเพื่อเริ่มบันทึกการเติมน้ำมัน\nและตั้งเตือนบำรุงรักษา',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มรถ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, size: 56),
            const SizedBox(height: 12),
            const Text('โหลดข้อมูลไม่สำเร็จ'),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('ลองใหม่')),
          ],
        ),
      ),
    );
  }
}
