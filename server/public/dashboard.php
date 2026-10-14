<?php

declare(strict_types=1);

/**
 * หน้าแรกของเว็บ — ภาพรวมของข้อมูลทั้งระบบ
 *
 * ตัวเลขทุกตัวบนหน้านี้เป็นค่ารวมของทั้งชุมชน ไม่มีอะไรที่ชี้กลับไปหาสมาชิกคนใด
 * คนหนึ่งได้ (ไม่มีทะเบียน ชื่ออู่ ค่าใช้จ่าย) เพราะหน้าเว็บทั้งเว็บเปิดให้สมาชิก
 * ที่ล็อกอินแล้วทุกคนเข้าดู ไม่ได้แยกสิทธิ์แอดมิน
 *
 * รายการบนหน้านี้เป็นสรุป top N ไม่ใช่หน้าลิสต์ — ลิสต์เต็มที่แบ่งหน้าอยู่ที่ models.php
 */

require_once __DIR__ . '/lib/asset.php';
require_once dirname(__DIR__) . '/src/bootstrap.php';

use CarCare\Auth;
use CarCare\Db;

$currentUser = Auth::currentUser();
if ($currentUser === null) {
    header('Location: ' . url('/login.php'));
    exit;
}

/** แสดงกี่อันดับในแต่ละตารางสรุป */
const DASHBOARD_TOP = 10;

$pdo = Db::pdo();

// รวมตัวนับทุกตัวไว้ในคิวรีเดียว — เป็น COUNT ทั้งตารางที่ไม่มีเงื่อนไขซับซ้อน
// InnoDB จึงไล่ดัชนีให้จบในรอบเดียว ดีกว่ายิงหกรอบแล้วรอ round trip หกครั้ง
$totals = $pdo->query(
    'SELECT
        (SELECT COUNT(*) FROM users)                                    AS members,
        (SELECT COUNT(*) FROM vehicles         WHERE deleted = 0)       AS vehicles,
        (SELECT COUNT(*) FROM fuel_entries     WHERE deleted = 0)       AS fuel_entries,
        (SELECT COUNT(*) FROM service_records  WHERE deleted = 0)       AS service_records,
        (SELECT COUNT(DISTINCT model_id) FROM model_interval_stats)     AS models_with_stats,
        (SELECT MAX(computed_at)         FROM model_interval_stats)     AS computed_at'
)->fetch();

$computedAt = $totals['computed_at'] === null ? null : (int) $totals['computed_at'];

// สถิติถูกคำนวณด้วย cron วันละครั้ง (bin/rebuild_stats.php) ถ้าค่าล่าสุดเก่ากว่า
// สองวันแปลว่า cron ไม่ได้รันมาแล้วอย่างน้อยหนึ่งรอบ — ต้องเห็นได้จากหน้าแรก
// ไม่ใช่รอให้มีคนสังเกตว่าตัวเลขไม่ขยับ
$staleAfterMs = 2 * 86400 * 1000;
$statsStale   = $computedAt === null || (Db::now() - $computedAt) > $staleAfterMs;

$topModels = $pdo->query(
    'SELECT mo.id,
            mo.name  AS model_name,
            mo.body_type,
            ma.name  AS make_name,
            COUNT(*) AS task_count,
            MAX(s.vehicle_count) AS top_vehicle_count
     FROM model_interval_stats s
     JOIN car_models mo ON mo.id = s.model_id
     JOIN car_makes  ma ON ma.id = mo.make_id
     GROUP BY mo.id, mo.name, mo.body_type, ma.name
     ORDER BY top_vehicle_count DESC, ma.name ASC, mo.name ASC, mo.id ASC
     LIMIT ' . DASHBOARD_TOP
)->fetchAll();

// จับกลุ่มด้วย task_key ไม่ใช่ task_name เพราะ task_key คือชื่อที่ normalize แล้ว
// (ชื่อเดียวกันที่เว้นวรรคต่างกันต้องนับเป็นรายการเดียว) ส่วนชื่อที่เอาไปแสดง
// หยิบด้วย MAX() เพราะ ONLY_FULL_GROUP_BY ไม่ให้ select คอลัมน์นอกกลุ่มตรง ๆ
$topTasks = $pdo->query(
    'SELECT MAX(task_name)          AS task_name,
            MAX(category)           AS category,
            COUNT(DISTINCT model_id) AS model_count,
            SUM(vehicle_count)      AS vehicles,
            SUM(sample_count)       AS samples,
            ROUND(AVG(median_km))   AS avg_median_km
     FROM model_interval_stats
     GROUP BY task_key
     -- เขียน MAX(task_name) ซ้ำใน ORDER BY แทนการอ้าง alias ที่ชื่อชนกับคอลัมน์จริง
     -- (ชื่อซ้ำแบบนั้นต้องพึ่งลำดับการ resolve ของ MySQL ซึ่งชน ONLY_FULL_GROUP_BY ได้)
     ORDER BY vehicles DESC, samples DESC, MAX(task_name) ASC
     LIMIT ' . DASHBOARD_TOP
)->fetchAll();

$title = 'ภาพรวม · บันทึกรถ';
require __DIR__ . '/partials/header.php';
?>

<h1>ภาพรวม</h1>
<p class="lead">
    สรุปข้อมูลที่สมาชิกช่วยกันบันทึกไว้ทั้งหมด
    ตัวเลขทุกตัวเป็นค่ารวม ไม่มีข้อมูลของรถคันไหนคันหนึ่งแสดงอยู่บนหน้านี้
</p>

<div class="tiles">
    <div class="tile">
        <span class="tile-label">สมาชิก</span>
        <strong class="tile-value"><?= number_format((int) $totals['members']) ?></strong>
    </div>
    <div class="tile">
        <span class="tile-label">รถในระบบ</span>
        <strong class="tile-value"><?= number_format((int) $totals['vehicles']) ?></strong>
    </div>
    <div class="tile">
        <span class="tile-label">บันทึกการเติมน้ำมัน</span>
        <strong class="tile-value"><?= number_format((int) $totals['fuel_entries']) ?></strong>
    </div>
    <div class="tile">
        <span class="tile-label">ประวัติการบำรุงรักษา</span>
        <strong class="tile-value"><?= number_format((int) $totals['service_records']) ?></strong>
    </div>
    <div class="tile">
        <span class="tile-label">รุ่นที่มีสถิติแล้ว</span>
        <strong class="tile-value"><?= number_format((int) $totals['models_with_stats']) ?></strong>
        <a class="tile-link" href="<?= e(url('/models.php')) ?>">ดูทั้งหมด</a>
    </div>
</div>

<p class="notice <?= $statsStale ? 'warn' : '' ?>">
    <?php if ($computedAt === null): ?>
        ยังไม่เคยคำนวณสถิติ — ตัวเลขจะขึ้นหลังการคำนวณรอบแรก (ทำวันละครั้ง)
    <?php else: ?>
        คำนวณสถิติล่าสุด <?= e(date('d/m/Y H:i', (int) ($computedAt / 1000))) ?> น.
        <?php if ($statsStale): ?>
            — เก่ากว่าสองวันแล้ว ประวัติที่บันทึกใหม่อาจยังไม่ถูกรวมเข้าไป
            (ปกติคำนวณให้เองวันละครั้ง)
        <?php endif; ?>
    <?php endif; ?>
</p>

<h2>รุ่นที่มีข้อมูลมากที่สุด</h2>

<table class="data">
    <thead>
    <tr>
        <th>#</th>
        <th>ยี่ห้อ / รุ่น</th>
        <th>ประเภท</th>
        <th class="num">รายการที่มีสถิติ</th>
        <th class="num">คันที่มีข้อมูลมากสุด</th>
    </tr>
    </thead>
    <tbody>
    <?php if ($topModels === []): ?>
        <tr>
            <td colspan="5" class="empty-state">
                ยังไม่มีรุ่นไหนมีข้อมูลมากพอจะสรุปได้
                ช่วยกันบันทึกประวัติการบำรุงรักษาในแอพ แล้วสถิติจะขึ้นเอง
            </td>
        </tr>
    <?php else: ?>
        <?php foreach ($topModels as $i => $row): ?>
            <tr>
                <td><?= $i + 1 ?></td>
                <td>
                    <a href="<?= e(url('/model.php')) ?>?id=<?= urlencode($row['id']) ?>">
                        <?= e($row['make_name']) ?> <?= e($row['model_name']) ?>
                    </a>
                </td>
                <td><?= e($row['body_type']) ?></td>
                <td class="num"><?= number_format((int) $row['task_count']) ?></td>
                <td class="num"><?= number_format((int) $row['top_vehicle_count']) ?></td>
            </tr>
        <?php endforeach; ?>
    <?php endif; ?>
    </tbody>
</table>

<p class="hint"><a href="<?= e(url('/models.php')) ?>">ดูรุ่นรถทั้งหมด &raquo;</a></p>

<h2>รายการที่สมาชิกทำกันมากที่สุด</h2>

<table class="data">
    <thead>
    <tr>
        <th>#</th>
        <th>รายการ</th>
        <th>หมวด</th>
        <th class="num">ค่ากลางเฉลี่ยข้ามรุ่น</th>
        <th class="num">รุ่นที่พบ</th>
        <th class="num">จำนวนคัน</th>
    </tr>
    </thead>
    <tbody>
    <?php if ($topTasks === []): ?>
        <tr>
            <td colspan="6" class="empty-state">ยังไม่มีรายการไหนมีข้อมูลมากพอจะสรุปได้</td>
        </tr>
    <?php else: ?>
        <?php foreach ($topTasks as $i => $row): ?>
            <tr>
                <td><?= $i + 1 ?></td>
                <td><?= e($row['task_name']) ?></td>
                <td><?= e($row['category']) ?></td>
                <td class="num"><?= number_format((float) $row['avg_median_km']) ?> กม.</td>
                <td class="num"><?= number_format((int) $row['model_count']) ?></td>
                <td class="num"><?= number_format((int) $row['vehicles']) ?></td>
            </tr>
        <?php endforeach; ?>
    <?php endif; ?>
    </tbody>
</table>

<p class="hint">
    “ค่ากลางเฉลี่ยข้ามรุ่น” คือค่าเฉลี่ยของมัธยฐานของแต่ละรุ่น ใช้ดูภาพรวมคร่าว ๆ เท่านั้น
    — ตัวเลขที่เอาไปใช้ตัดสินใจจริงต้องดูของรุ่นรถตัวเอง เพราะแต่ละรุ่นต่างกันมาก
</p>

<?php require __DIR__ . '/partials/footer.php'; ?>
