<?php

declare(strict_types=1);

namespace CarCare;

use PDO;

/**
 * รวมสถิติ "คนอื่นเขาเปลี่ยนกันที่ระยะเท่าไร" ของรถแต่ละรุ่น
 *
 * ตรรกะเดียวกับ lib/services/interval_stats.dart ฝั่งแอพ ต่างกันแค่แหล่งข้อมูล:
 * ฝั่งแอพอ่านของตัวเองเครื่องเดียว ฝั่งนี้อ่านของสมาชิกทุกคน
 */
final class IntervalStats
{
    /**
     * ดึงระยะห่างระหว่างการทำสองครั้งติดกันของทุกคน
     *
     * จับคู่ด้วย window function ที่ระดับฐานข้อมูล เพราะการดึงประวัติทั้งหมด
     * มาไล่ใน PHP จะกินหน่วยความจำตามจำนวนสมาชิก
     *
     * การจับคู่ใช้ (vehicle_id, task_id) — ห้ามจับข้ามคัน และห้ามจับข้ามงาน
     * ส่วนการ "รวมข้ามสมาชิก" ใช้ชื่อรายการที่ normalize แล้วเป็นคีย์
     * เพราะ task_id เป็น UUID ที่ต่างกันไปในแต่ละเครื่อง
     *
     * @return array<int, array{model_id: string, task_key: string, task_name: string,
     *                          category: string, vehicle_id: string, km: float, days: int}>
     */
    public static function fetchIntervals(PDO $pdo): array
    {
        $sql = <<<SQL
            SELECT model_id, task_key, task_name, category, vehicle_id, km, days
            FROM (
                SELECT
                    v.model_id AS model_id,
                    REGEXP_REPLACE(LOWER(TRIM(COALESCE(t.name, sr.title))), '[[:space:]]+', ' ') AS task_key,
                    COALESCE(t.name, sr.title) AS task_name,
                    COALESCE(NULLIF(t.category, ''), 'อื่น ๆ') AS category,
                    sr.vehicle_id AS vehicle_id,
                    sr.odometer - LAG(sr.odometer) OVER w AS km,
                    FLOOR((sr.date - LAG(sr.date) OVER w) / 86400000) AS days
                FROM service_records sr
                JOIN vehicles v
                    ON v.id = sr.vehicle_id AND v.deleted = 0
                LEFT JOIN maintenance_tasks t
                    ON t.id = sr.task_id AND t.deleted = 0
                WHERE sr.deleted = 0
                  AND v.model_id IS NOT NULL
                WINDOW w AS (
                    PARTITION BY sr.vehicle_id, COALESCE(sr.task_id, sr.title)
                    ORDER BY sr.odometer, sr.date
                )
            ) paired
            WHERE km > 0
            SQL;

        return $pdo->query($sql)->fetchAll();
    }

    /**
     * สรุปเป็นหนึ่งแถวต่อ (รุ่นรถ, งานบำรุงรักษา)
     *
     * ตัดรายการที่ตัวอย่างน้อยหรือมาจากรถน้อยคันเกินไปทิ้ง — นอกจากตัวเลขจะมั่ว
     * แล้วยังเสี่ยงให้เดาย้อนกลับได้ว่าเป็นข้อมูลของใคร
     *
     * @param array<int, array<string, mixed>> $intervals ผลจาก fetchIntervals()
     * @return array<int, array<string, mixed>>
     */
    public static function summarize(array $intervals, int $minSamples, int $minVehicles): array
    {
        $groups = [];
        foreach ($intervals as $row) {
            $key = $row['model_id'] . "\x00" . $row['task_key'];
            if (!isset($groups[$key])) {
                $groups[$key] = [
                    'model_id'  => $row['model_id'],
                    'task_key'  => $row['task_key'],
                    'task_name' => $row['task_name'],
                    'category'  => $row['category'],
                    'kms'       => [],
                    'days'      => [],
                    'vehicles'  => [],
                ];
            }

            $groups[$key]['kms'][]  = (float) $row['km'];
            $groups[$key]['days'][] = (float) $row['days'];
            $groups[$key]['vehicles'][$row['vehicle_id']] = true;
        }

        $summaries = [];
        foreach ($groups as $group) {
            $vehicleCount = count($group['vehicles']);
            $sampleCount  = count($group['kms']);
            if ($sampleCount < $minSamples || $vehicleCount < $minVehicles) {
                continue;
            }

            sort($group['kms']);
            sort($group['days']);

            $summaries[] = [
                'model_id'      => $group['model_id'],
                'task_key'      => $group['task_key'],
                'task_name'     => $group['task_name'],
                'category'      => $group['category'],
                'sample_count'  => $sampleCount,
                'vehicle_count' => $vehicleCount,
                'median_km'     => self::percentile($group['kms'], 0.5),
                'p25_km'        => self::percentile($group['kms'], 0.25),
                'p75_km'        => self::percentile($group['kms'], 0.75),
                'median_days'   => (int) round(self::percentile($group['days'], 0.5)),
            ];
        }

        return $summaries;
    }

    /**
     * เปอร์เซ็นไทล์แบบเทียบสัดส่วน จากลิสต์ที่เรียงจากน้อยไปมากแล้ว
     *
     * ใช้มัธยฐานแทนค่าเฉลี่ยทุกที่ เพราะข้อมูลจริงมีทั้งคนที่ปล่อยยาวผิดปกติ
     * และคนที่กรอกเลขไมล์ผิด ซึ่งดึงค่าเฉลี่ยเพี้ยนได้ทั้งคู่
     *
     * @param array<int, float> $sorted
     */
    public static function percentile(array $sorted, float $fraction): float
    {
        $count = count($sorted);
        if ($count === 0) {
            return 0.0;
        }
        if ($count === 1) {
            return $sorted[0];
        }

        $position = ($count - 1) * $fraction;
        $lower    = (int) floor($position);
        $upper    = (int) ceil($position);
        if ($lower === $upper) {
            return $sorted[$lower];
        }

        $weight = $position - $lower;

        return $sorted[$lower] * (1 - $weight) + $sorted[$upper] * $weight;
    }

    /** เขียนผลสรุปทับตารางแคชทั้งชุดในทรานแซกชันเดียว */
    public static function store(PDO $pdo, array $summaries): void
    {
        $now = Db::now();

        $pdo->beginTransaction();
        try {
            $pdo->exec('DELETE FROM model_interval_stats');

            $stmt = $pdo->prepare(
                'INSERT INTO model_interval_stats
                    (model_id, task_key, task_name, category, sample_count, vehicle_count,
                     median_km, p25_km, p75_km, median_days, computed_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
            );

            foreach ($summaries as $s) {
                $stmt->execute([
                    $s['model_id'],
                    $s['task_key'],
                    $s['task_name'],
                    $s['category'],
                    $s['sample_count'],
                    $s['vehicle_count'],
                    $s['median_km'],
                    $s['p25_km'],
                    $s['p75_km'],
                    $s['median_days'],
                    $now,
                ]);
            }

            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }
}
