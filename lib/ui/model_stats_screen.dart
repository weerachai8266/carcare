import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import 'format.dart';

/// สถิติของรถรุ่นเดียวกันจากสมาชิกคนอื่น แยกตามหมวด หมวดละ 10 อันดับ
class ModelStatsScreen extends StatefulWidget {
  const ModelStatsScreen({
    super.key,
    required this.modelId,
    required this.modelName,
  });

  final String modelId;
  final String modelName;

  @override
  State<ModelStatsScreen> createState() => _ModelStatsScreenState();
}

class _ModelStatsScreenState extends State<ModelStatsScreen> {
  late Future<Map<String, List<_StatRow>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, List<_StatRow>>> _load() async {
    final response = await AppServices.instance.api.get(
      '/stats/model',
      {'model_id': widget.modelId},
    );

    final categories = (response['categories'] as Map?)?.cast<String, dynamic>() ?? {};
    return {
      for (final entry in categories.entries)
        entry.key: (entry.value as List)
            .whereType<Map>()
            .map((row) => _StatRow.fromJson(row.cast<String, Object?>()))
            .toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('คนอื่นเปลี่ยนกันที่ระยะเท่าไร'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(widget.modelName, style: theme.textTheme.bodyMedium),
          ),
        ),
      ),
      body: FutureBuilder<Map<String, List<_StatRow>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            return _Info(
              icon: Icons.cloud_off,
              text: error is ApiException && error.isUnauthorized
                  ? 'ต้องเข้าสู่ระบบก่อนถึงจะดูสถิติของสมาชิกได้'
                  : 'ดึงสถิติไม่สำเร็จ: $error',
            );
          }

          final categories = snapshot.data ?? const {};
          if (categories.isEmpty) {
            return const _Info(
              icon: Icons.insights_outlined,
              text: 'รุ่นนี้ยังมีข้อมูลไม่มากพอจะสรุปได้\n'
                  'ยิ่งสมาชิกบันทึกประวัติมากขึ้น สถิติก็จะแม่นขึ้น',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'ตัวเลขเป็นค่ามัธยฐานจากประวัติที่สมาชิกบันทึกจริง '
                'ไม่ใช่รอบที่ผู้ผลิตกำหนด',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final entry in categories.entries) ...[
                Text(entry.key, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final row in entry.value) ...[
                  _StatTile(row: row),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatRow {
  final String taskName;
  final double medianKm;
  final double p25Km;
  final double p75Km;
  final int medianDays;
  final int vehicleCount;

  const _StatRow({
    required this.taskName,
    required this.medianKm,
    required this.p25Km,
    required this.p75Km,
    required this.medianDays,
    required this.vehicleCount,
  });

  factory _StatRow.fromJson(Map<String, Object?> json) => _StatRow(
        taskName: json['task_name'] as String? ?? '',
        medianKm: (json['median_km'] as num?)?.toDouble() ?? 0,
        p25Km: (json['p25_km'] as num?)?.toDouble() ?? 0,
        p75Km: (json['p75_km'] as num?)?.toDouble() ?? 0,
        medianDays: (json['median_days'] as num?)?.toInt() ?? 0,
        vehicleCount: (json['vehicle_count'] as num?)?.toInt() ?? 0,
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.row});

  final _StatRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(row.taskName, style: theme.textTheme.titleSmall),
                ),
                Text(
                  Fmt.km(row.medianKm),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ส่วนใหญ่ ${Fmt.kmNumber(row.p25Km)}–${Fmt.km(row.p75Km)} '
              '· ราว ${row.medianDays} วัน · จาก ${row.vehicleCount} คัน',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
