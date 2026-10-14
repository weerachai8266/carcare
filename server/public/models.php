<?php

declare(strict_types=1);

/**
 * หน้ารายชื่อรุ่นรถที่มีสถิติมากพอจะแสดงได้
 *
 * (เดิมไฟล์นี้คือ index.php — หน้าแรกย้ายไปเป็น dashboard.php แล้ว)
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

$pdo    = Db::pdo();
$search = trim((string) ($_GET['q' ] ?? ''));

// WHERE ชุดเดียวใช้ทั้งคิวรีนับและคิวรีดึงข้อมูล ไม่งั้นจำนวนหน้าจะไม่ตรงกับของจริง
$where  = '';
$params = [];
if ($search !== '') {
    $where = 'WHERE (mo.name LIKE :q OR ma.name LIKE :q OR ma.name_th LIKE :q)';
    $params['q'] = '%' . $search . '%';
}

$countSql = "SELECT COUNT(DISTINCT s.model_id)
             FROM model_interval_stats s
             JOIN car_models mo ON mo.id = s.model_id
             JOIN car_makes  ma ON ma.id = mo.make_id
             {$where}";
$countStmt = $pdo->prepare($countSql);
$countStmt->execute($params);
$total = (int) $countStmt->fetchColumn();

$page        = max(1, (int) ($_GET['page'] ?? 1));
$total_pages = max(1, (int) ceil($total / PER_PAGE));
// clamp หลังนับ เพื่อให้ลิงก์เก่าที่บุ๊กมาร์กไว้ตกมาที่หน้าสุดท้ายจริง ไม่ใช่หน้าว่าง
$page   = min($page, $total_pages);
$offset = ($page - 1) * PER_PAGE;

$sql = "SELECT mo.id,
               mo.name        AS model_name,
               mo.body_type,
               ma.name        AS make_name,
               COUNT(*)       AS task_count,
               MAX(s.vehicle_count) AS top_vehicle_count,
               MAX(s.computed_at)   AS computed_at
        FROM model_interval_stats s
        JOIN car_models mo ON mo.id = s.model_id
        JOIN car_makes  ma ON ma.id = mo.make_id
        {$where}
        GROUP BY mo.id, mo.name, mo.body_type, ma.name
        ORDER BY top_vehicle_count DESC, ma.name ASC, mo.name ASC, mo.id ASC
        LIMIT :limit OFFSET :offset";

$stmt = $pdo->prepare($sql);
foreach ($params as $key => $value) {
    $stmt->bindValue(':' . $key, $value);
}
// LIMIT/OFFSET ต้อง bind เป็น int เสมอ ไม่งั้นถูก quote เป็นสตริงแล้ว SQL พัง
$stmt->bindValue(':limit', PER_PAGE, PDO::PARAM_INT);
$stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
$stmt->execute();
$rows = $stmt->fetchAll();

$title = 'สถิติการบำรุงรักษาตามรุ่นรถ';
require __DIR__ . '/partials/header.php';
?>

<p class="breadcrumb"><a href="<?= e(url('/')) ?>">&laquo; ภาพรวม</a></p>

<h1>สถิติการบำรุงรักษาตามรุ่นรถ</h1>
<p class="lead">
    รวบรวมจากประวัติที่สมาชิกบันทึกจริงว่าแต่ละรายการถูกทำที่ระยะเท่าไร
    แสดงเฉพาะรุ่นที่มีข้อมูลมากพอจะเชื่อถือได้
</p>

<form class="search" method="get" action="">
    <input type="search" name="q" value="<?= e($search) ?>" placeholder="ค้นหายี่ห้อหรือรุ่น เช่น Yaris, โตโยต้า">
    <button type="submit">ค้นหา</button>
    <?php if ($search !== ''): ?>
        <a class="clear" href="?">ล้างคำค้น</a>
    <?php endif; ?>
</form>

<table class="data">
    <thead>
    <tr>
        <th>#</th>
        <th>ยี่ห้อ / รุ่น</th>
        <th>ประเภท</th>
        <th class="num">รายการที่มีสถิติ</th>
        <th class="num">คันที่มีข้อมูลมากสุด</th>
        <th>อัปเดตล่าสุด</th>
    </tr>
    </thead>
    <tbody>
    <?php if ($total === 0): ?>
        <tr>
            <td colspan="6" class="empty-state">
                <?php if ($search !== ''): ?>
                    ไม่พบรุ่นรถที่ตรงกับคำค้น “<?= e($search) ?>”
                    — <a href="?">ดูทั้งหมด</a>
                <?php else: ?>
                    ยังไม่มีรุ่นไหนมีข้อมูลมากพอจะสรุปได้
                    ช่วยกันบันทึกประวัติการบำรุงรักษาในแอพ แล้วสถิติจะขึ้นเอง
                <?php endif; ?>
            </td>
        </tr>
    <?php else: ?>
        <?php foreach ($rows as $i => $row): ?>
            <tr>
                <td><?= $offset + $i + 1 ?></td>
                <td>
                    <a href="<?= e(url('/model.php')) ?>?id=<?= urlencode($row['id']) ?>">
                        <?= e($row['make_name']) ?> <?= e($row['model_name']) ?>
                    </a>
                </td>
                <td><?= e($row['body_type']) ?></td>
                <td class="num"><?= number_format((int) $row['task_count']) ?></td>
                <td class="num"><?= number_format((int) $row['top_vehicle_count']) ?></td>
                <td><?= e(date('d/m/Y', (int) ((int) $row['computed_at'] / 1000))) ?></td>
            </tr>
        <?php endforeach; ?>
    <?php endif; ?>
    </tbody>
</table>

<?php require __DIR__ . '/partials/pagination.php'; ?>
<?php require __DIR__ . '/partials/footer.php'; ?>
