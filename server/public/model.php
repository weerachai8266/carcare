<?php

declare(strict_types=1);

/**
 * สถิติของรุ่นรถหนึ่ง แยกตามหมวด หมวดละไม่เกิน 10 อันดับ
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

$modelId = (string) ($_GET['id'] ?? '');
$pdo     = Db::pdo();

$modelStmt = $pdo->prepare(
    'SELECT mo.id, mo.name AS model_name, mo.body_type, ma.name AS make_name
     FROM car_models mo
     JOIN car_makes ma ON ma.id = mo.make_id
     WHERE mo.id = ?'
);
$modelStmt->execute([$modelId]);
$model = $modelStmt->fetch();

if (!$model) {
    http_response_code(404);
    $title = 'ไม่พบรุ่นรถ';
    require __DIR__ . '/partials/header.php';
    echo '<h1>ไม่พบรุ่นรถนี้</h1><p><a href="' . e(url('/models.php')) . '">กลับไปหน้ารายการ</a></p>';
    require __DIR__ . '/partials/footer.php';
    exit;
}

$topPerCategory = (int) Db::config()['stats']['top_per_category'];

// นับด้วยเงื่อนไขเดียวกับคิวรีข้อมูล รวมถึงการตัดที่หมวดละ N อันดับ
// ไม่งั้นจำนวนหน้าจะนับรายการที่ไม่มีวันถูกแสดงเข้าไปด้วย
$rankedSql = "SELECT task_name, category, sample_count, vehicle_count,
                     median_km, p25_km, p75_km, median_days,
                     ROW_NUMBER() OVER (
                         PARTITION BY category
                         ORDER BY vehicle_count DESC, sample_count DESC, task_key ASC
                     ) AS rank_in_category
              FROM model_interval_stats
              WHERE model_id = :model_id";

$countStmt = $pdo->prepare(
    "SELECT COUNT(*) FROM ({$rankedSql}) ranked WHERE rank_in_category <= :top"
);
$countStmt->execute(['model_id' => $modelId, 'top' => $topPerCategory]);
$total = (int) $countStmt->fetchColumn();

$page        = max(1, (int) ($_GET['page'] ?? 1));
$total_pages = max(1, (int) ceil($total / PER_PAGE));
$page        = min($page, $total_pages);
$offset      = ($page - 1) * PER_PAGE;

$stmt = $pdo->prepare(
    "SELECT * FROM ({$rankedSql}) ranked
     WHERE rank_in_category <= :top
     ORDER BY category ASC, rank_in_category ASC
     LIMIT :limit OFFSET :offset"
);
$stmt->bindValue(':model_id', $modelId);
$stmt->bindValue(':top', $topPerCategory, PDO::PARAM_INT);
$stmt->bindValue(':limit', PER_PAGE, PDO::PARAM_INT);
$stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
$stmt->execute();
$rows = $stmt->fetchAll();

$title = $model['make_name'] . ' ' . $model['model_name'] . ' — สถิติการบำรุงรักษา';
require __DIR__ . '/partials/header.php';
?>

<p class="breadcrumb"><a href="<?= e(url('/models.php')) ?>">&laquo; รายการรุ่นรถทั้งหมด</a></p>

<h1><?= e($model['make_name']) ?> <?= e($model['model_name']) ?></h1>
<p class="lead">
    ระยะที่สมาชิกทำจริง แยกตามหมวด หมวดละไม่เกิน <?= $topPerCategory ?> อันดับ
    เรียงตามจำนวนคันที่มีข้อมูล
</p>

<table class="data">
    <thead>
    <tr>
        <th>#</th>
        <th>หมวด</th>
        <th>รายการ</th>
        <th class="num">ระยะที่ทำกัน (มัธยฐาน)</th>
        <th class="num">ช่วงที่คนส่วนใหญ่ทำ</th>
        <th class="num">ระยะเวลา</th>
        <th class="num">จำนวนคัน</th>
    </tr>
    </thead>
    <tbody>
    <?php if ($total === 0): ?>
        <tr>
            <td colspan="7" class="empty-state">
                รุ่นนี้ยังมีข้อมูลไม่มากพอจะสรุปได้
                — ต้องมีประวัติการทำซ้ำอย่างน้อย 2 ครั้งของรายการเดียวกัน จากหลายคัน
            </td>
        </tr>
    <?php else: ?>
        <?php foreach ($rows as $i => $row): ?>
            <tr>
                <td><?= $offset + $i + 1 ?></td>
                <td><?= e($row['category']) ?></td>
                <td><?= e($row['task_name']) ?></td>
                <td class="num"><?= number_format((float) $row['median_km']) ?> กม.</td>
                <td class="num range">
                    <?= number_format((float) $row['p25_km']) ?>–<?= number_format((float) $row['p75_km']) ?>
                </td>
                <td class="num"><?= number_format((int) $row['median_days']) ?> วัน</td>
                <td class="num"><?= number_format((int) $row['vehicle_count']) ?></td>
            </tr>
        <?php endforeach; ?>
    <?php endif; ?>
    </tbody>
</table>

<?php require __DIR__ . '/partials/pagination.php'; ?>
<?php require __DIR__ . '/partials/footer.php'; ?>
