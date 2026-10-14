<?php

declare(strict_types=1);

/**
 * คำนวณสถิติระยะบำรุงรักษาของทุกรุ่นใหม่ทั้งชุด แล้วเขียนลงตารางแคช
 *
 * ตั้งเป็น cron วันละครั้งก็พอ เพราะสถิติรวมของสมาชิกทั้งหมดไม่ได้ขยับรายนาที
 *   0 3 * * * /usr/bin/php /path/to/server/bin/rebuild_stats.php >> /var/log/carcare-stats.log 2>&1
 *
 * รันจากบรรทัดคำสั่งเท่านั้น — เปิดผ่านเว็บไม่ได้ เพราะงานนี้กินเวลานาน
 * และไม่ควรให้ใครก็ได้สั่งให้เซิร์ฟเวอร์คำนวณใหม่
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("สคริปต์นี้รันได้จากบรรทัดคำสั่งเท่านั้น\n");
}

require_once dirname(__DIR__) . '/src/bootstrap.php';

use CarCare\Db;
use CarCare\IntervalStats;

$startedAt = microtime(true);
$config    = Db::config()['stats'];
$pdo       = Db::pdo();

$intervals = IntervalStats::fetchIntervals($pdo);
printf("อ่านช่วงที่วัดได้ %d ช่วง\n", count($intervals));

$summaries = IntervalStats::summarize(
    $intervals,
    (int) $config['min_samples'],
    (int) $config['min_vehicles']
);
printf("สรุปได้ %d รายการ (ตัดรายการที่ตัวอย่างน้อยกว่า %d ช่วง หรือมาจากน้อยกว่า %d คันออก)\n",
    count($summaries),
    $config['min_samples'],
    $config['min_vehicles']
);

IntervalStats::store($pdo, $summaries);

printf("เขียนลงตารางแคชเรียบร้อย ใช้เวลา %.1f วินาที\n", microtime(true) - $startedAt);
