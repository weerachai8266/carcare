import 'package:flutter/material.dart';

import '../models/fuel_entry.dart';
import 'fuel_form_screen.dart';
import 'format.dart';
import 'vehicle_data.dart';

/// แท็บ "น้ำมัน" — ประวัติการเติมทั้งหมด พร้อมอัตราสิ้นเปลืองของแต่ละช่วง
class FuelTab extends StatelessWidget {
  const FuelTab({super.key, required this.data, required this.onChanged});

  final VehicleData data;
  final VoidCallback onChanged;

  Future<void> _edit(BuildContext context, FuelEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FuelFormScreen(data: data, entry: entry)),
    );
    if (changed == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entriesNewestFirst;
    final theme = Theme.of(context);

    if (entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 64),
          Icon(Icons.local_gas_station_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('ยังไม่มีประวัติการเติมน้ำมัน',
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'บันทึกการเติมสองครั้งขึ้นไปแบบเต็มถัง\nแอพจะคำนวณอัตราสิ้นเปลืองให้เอง',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final entry = entries[i];
        return _FuelEntryTile(
          entry: entry,
          kmPerLiter: data.segmentByEntryId[entry.id]?.kmPerLiter,
          onTap: () => _edit(context, entry),
        );
      },
    );
  }
}

class _FuelEntryTile extends StatelessWidget {
  const _FuelEntryTile({
    required this.entry,
    required this.kmPerLiter,
    required this.onTap,
  });

  final FuelEntry entry;
  final double? kmPerLiter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cost = entry.effectiveTotalCost;

    final details = <String>[
      Fmt.liters(entry.liters),
      if (cost != null) Fmt.bahtRound(cost),
      if (!entry.isFullTank) 'ไม่เต็มถัง',
      if (entry.station != null) entry.station!,
    ];

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(Fmt.date(entry.dateTime),
                            style: theme.textTheme.titleSmall),
                        const SizedBox(width: 8),
                        Text(Fmt.km(entry.odometer),
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(details.join(' · '), style: theme.textTheme.bodyMedium),
                    if (entry.missedEntries)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'มีการเติมที่ลืมบันทึกก่อนหน้านี้',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
              if (kmPerLiter != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    Fmt.kmPerLiter(kmPerLiter!),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
