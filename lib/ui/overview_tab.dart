import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/expense_stats.dart';
import '../services/maintenance_status.dart';
import 'fuel_form_screen.dart';
import 'format.dart';
import 'service_form_screen.dart';
import 'vehicle_data.dart';

/// แท็บ "ภาพรวม" — สรุปเลขไมล์ อัตราสิ้นเปลือง ค่าใช้จ่าย และสิ่งที่ต้องทำ
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.data, required this.onChanged});

  final VehicleData data;
  final VoidCallback onChanged;

  Future<void> _open(BuildContext context, Widget screen) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (changed == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = data.summary;
    final attention = data.attentionStatuses;
    final expenses = data.expenses;
    final months = data.months;
    final recent = data.entriesNewestFirst.take(3).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _OdometerCard(data: data),
        const SizedBox(height: 16),
        if (attention.isNotEmpty) ...[
          Text('ต้องดูแลเร็ว ๆ นี้', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final status in attention.take(4)) ...[
            _AttentionTile(
              status: status,
              onTap: () => _open(
                context,
                ServiceFormScreen(data: data, presetTask: status.task),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        Text('อัตราสิ้นเปลือง', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!summary.hasConsumptionData)
          _HintCard(
            icon: Icons.info_outline,
            text: summary.entryCount == 0
                ? 'ยังไม่มีข้อมูลการเติมน้ำมัน กดปุ่มเติมน้ำมันด้านล่างเพื่อเริ่มบันทึก'
                : 'บันทึกการเติมแบบเต็มถังอีกครั้ง แอพจะเริ่มคำนวณอัตราสิ้นเปลืองให้',
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.9,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _StatCard(
                label: 'อัตราสิ้นเปลืองเฉลี่ย',
                value: Fmt.kmPerLiter(summary.avgKmPerLiter!),
                icon: Icons.speed,
              ),
              _StatCard(
                label: 'ดีที่สุด / แย่ที่สุด',
                value: '${Fmt.number(summary.bestKmPerLiter!)} / '
                    '${Fmt.number(summary.worstKmPerLiter!)}',
                icon: Icons.compare_arrows,
              ),
              if (summary.avgPricePerLiter != null && summary.avgPricePerLiter! > 0)
                _StatCard(
                  label: 'ราคาเฉลี่ยต่อลิตร',
                  value: Fmt.baht(summary.avgPricePerLiter!),
                  icon: Icons.local_offer_outlined,
                ),
              if (summary.costPerKm != null && summary.costPerKm! > 0)
                _StatCard(
                  label: 'ค่าน้ำมันต่อกิโลเมตร',
                  value: Fmt.baht(summary.costPerKm!),
                  icon: Icons.route,
                ),
              _StatCard(
                label: 'เติมทั้งหมด',
                value: '${summary.entryCount} ครั้ง',
                icon: Icons.local_gas_station_outlined,
              ),
            ],
          ),
        const SizedBox(height: 24),
        Text('ค่าใช้จ่าย', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!expenses.hasData)
          const _HintCard(
            icon: Icons.info_outline,
            text: 'ยังไม่มีค่าใช้จ่ายที่บันทึกไว้ '
                'กรอกราคาตอนเติมน้ำมันหรือค่าใช้จ่ายตอนเข้าอู่ แล้วยอดจะสรุปให้ที่นี่',
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.9,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _StatCard(
                label: 'รวมทั้งหมด',
                value: Fmt.bahtRound(expenses.total),
                icon: Icons.payments_outlined,
                emphasize: true,
              ),
              if (expenses.perMonth != null)
                _StatCard(
                  label: 'เฉลี่ยต่อเดือน',
                  value: Fmt.bahtRound(expenses.perMonth!),
                  icon: Icons.calendar_month_outlined,
                ),
              _StatCard(
                label: 'ค่าน้ำมัน',
                value: Fmt.bahtRound(expenses.fuelCost),
                icon: Icons.local_gas_station_outlined,
              ),
              _StatCard(
                label: expenses.serviceCount == 0
                    ? 'ค่าบำรุงรักษา'
                    : 'ค่าบำรุงรักษา (${expenses.serviceCount} ครั้ง)',
                value: Fmt.bahtRound(expenses.serviceCost),
                icon: Icons.build_outlined,
              ),
              if (expenses.perKm != null)
                _StatCard(
                  label: 'รวมต่อกิโลเมตร',
                  value: Fmt.baht(expenses.perKm!),
                  icon: Icons.route,
                ),
            ],
          ),
        if (months.length >= 2) ...[
          const SizedBox(height: 24),
          Text('ค่าใช้จ่ายรายเดือน', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _MonthlyExpenseChart(months: months),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('เติมน้ำมันล่าสุด', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in recent)
            Card(
              color: theme.colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onTap: () => _open(context, FuelFormScreen(data: data, entry: entry)),
                title: Text(
                  '${Fmt.liters(entry.liters)}'
                  '${entry.effectiveTotalCost == null ? '' : ' · ${Fmt.bahtRound(entry.effectiveTotalCost!)}'}',
                ),
                subtitle: Text('${Fmt.date(entry.dateTime)} · ${Fmt.km(entry.odometer)}'),
                trailing: data.segmentByEntryId[entry.id] == null
                    ? null
                    : Text(
                        Fmt.kmPerLiter(data.segmentByEntryId[entry.id]!.kmPerLiter),
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
              ),
            ),
        ],
      ],
    );
  }
}

class _OdometerCard extends StatelessWidget {
  const _OdometerCard({required this.data});

  final VehicleData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perDay = data.avgKmPerDay;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'เลขไมล์ล่าสุด',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  Fmt.kmNumber(data.odometer),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'กม.',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                ),
              ],
            ),
            if (perDay != null) ...[
              const SizedBox(height: 8),
              Text(
                'ขับเฉลี่ย ${Fmt.number(perDay)} กม./วัน '
                '(ราว ${Fmt.kmNumber(perDay * 30)} กม./เดือน)',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.status, required this.onTap});

  final TaskStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = status.level == DueLevel.overdue;
    final color = overdue ? theme.colorScheme.error : Colors.orange.shade800;

    return Card(
      color: color.withValues(alpha: 0.10),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(
          overdue ? Icons.error_outline : Icons.schedule,
          color: color,
        ),
        title: Text(status.task.name),
        subtitle: Text(status.summaryLabel),
        trailing: const Icon(Icons.add_task),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;

  /// เน้นใบที่เป็นยอดรวม ให้สายตาจับได้ก่อนใบที่เป็นรายละเอียดย่อย
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = emphasize
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      color: emphasize
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: labelColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: labelColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: emphasize ? theme.colorScheme.onPrimaryContainer : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// กราฟแท่งค่าใช้จ่ายรายเดือน 6 เดือนหลังสุด แยกสีน้ำมันกับบำรุงรักษา
///
/// ใช้แท่งซ้อนแทนแท่งคู่ เพราะสิ่งที่อยากรู้ก่อนคือเดือนนั้นจ่ายรวมเท่าไร
/// แล้วค่อยดูว่าแบ่งเป็นอะไรบ้าง — แท่งคู่ต้องบวกเลขในหัวเองถึงจะได้ยอดรวม
class _MonthlyExpenseChart extends StatelessWidget {
  const _MonthlyExpenseChart({required this.months});

  final List<MonthlyExpense> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fuelColor = theme.colorScheme.primary;
    final serviceColor = theme.colorScheme.tertiary;
    final shown = months.length <= 6 ? months : months.sublist(months.length - 6);
    final maxCost = shown.fold<double>(0, (m, e) => e.total > m ? e.total : m);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _LegendDot(color: fuelColor, label: 'น้ำมัน'),
                const SizedBox(width: 12),
                _LegendDot(color: serviceColor, label: 'บำรุงรักษา'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  // เผื่อหัวแท่งไว้ 20% ไม่ให้แท่งสูงสุดชนขอบบนพอดีจนดูอึดอัด
                  maxY: maxCost <= 0 ? 1 : maxCost * 1.2,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) {
                          if (value == 0 || value >= meta.max) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            Fmt.kmNumber(value),
                            style: theme.textTheme.labelSmall,
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        // สูงพอสำหรับสองบรรทัด เผื่อป้ายที่ต้องแสดงปีด้วย
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= shown.length) {
                            return const SizedBox.shrink();
                          }
                          final m = shown[i];
                          // ใส่ปีเฉพาะป้ายแรกกับตอนที่ข้ามปี พอที่เหลือรู้ได้เอง
                          // ถ้าใส่ทุกป้าย ตัวหนังสือจะทับกันเมื่อมีครบ 6 เดือน
                          final showYear = i == 0 || shown[i - 1].year != m.year;

                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  Fmt.monthShort(m.monthStart),
                                  style: theme.textTheme.labelSmall,
                                ),
                                if (showYear)
                                  Text(
                                    '${m.year}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final m = shown[group.x];
                        // แจกแจงเฉพาะบรรทัดที่มีเงินจริง เดือนที่ไม่ได้เข้าอู่
                        // ไม่ต้องมีบรรทัด "บำรุงรักษา 0 บ." มารกทูลทิป
                        final lines = <String>[
                          Fmt.month(m.monthStart),
                          'รวม ${Fmt.bahtRound(m.total)}',
                          if (m.fuelCost > 0)
                            'น้ำมัน ${Fmt.bahtRound(m.fuelCost)}'
                                ' · ${Fmt.liters(m.liters)}',
                          if (m.serviceCost > 0)
                            'บำรุงรักษา ${Fmt.bahtRound(m.serviceCost)}',
                        ];
                        return BarTooltipItem(
                          lines.join('\n'),
                          theme.textTheme.bodySmall ?? const TextStyle(),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < shown.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: shown[i].total,
                            width: 18,
                            // ระบายสีด้วย stack items ทั้งแท่ง แล้วให้สีหลักโปร่งใส
                            // ไม่งั้น fl_chart จะทับสีพื้นลงบนส่วนที่ซ้อนไว้
                            color: Colors.transparent,
                            rodStackItems: [
                              BarChartRodStackItem(0, shown[i].fuelCost, fuelColor),
                              BarChartRodStackItem(
                                shown[i].fuelCost,
                                shown[i].total,
                                serviceColor,
                              ),
                            ],
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// จุดสีพร้อมคำอธิบาย ใช้บอกว่าสีไหนในกราฟคืออะไร
class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
