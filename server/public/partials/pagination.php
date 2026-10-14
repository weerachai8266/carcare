<?php

declare(strict_types=1);

/**
 * แถบแบ่งหน้า ใช้ร่วมกันทุกหน้าลิสต์
 *
 * ต้องมีตัวแปรพร้อมก่อน include: $page, $total_pages, $total, $offset
 *
 * ปุ่ม "ก่อนหน้า"/"ถัดไป" ที่ปลายทางถูกแสดงแบบกดไม่ได้ ไม่ใช่ซ่อนทิ้ง
 * เพื่อให้ความกว้างของแถบไม่ขยับตอนเปลี่ยนหน้า
 */

/** @var int $page */
/** @var int $total_pages */
/** @var int $total */
/** @var int $offset */

$window = 2;
?>
<?php if ($total_pages > 1): ?>
<nav class="pagination" aria-label="แบ่งหน้า">
    <?php if ($page > 1): ?>
        <a href="<?= page_url($page - 1) ?>" rel="prev">&laquo; ก่อนหน้า</a>
    <?php else: ?>
        <span class="disabled">&laquo; ก่อนหน้า</span>
    <?php endif; ?>

    <?php for ($n = 1; $n <= $total_pages; $n++): ?>
        <?php if ($n === 1 || $n === $total_pages || abs($n - $page) <= $window): ?>
            <?php if ($n === $page): ?>
                <span class="current" aria-current="page"><?= $n ?></span>
            <?php else: ?>
                <a href="<?= page_url($n) ?>"><?= $n ?></a>
            <?php endif; ?>
        <?php elseif (abs($n - $page) === $window + 1): ?>
            <span class="ellipsis">…</span>
        <?php endif; ?>
    <?php endfor; ?>

    <?php if ($page < $total_pages): ?>
        <a href="<?= page_url($page + 1) ?>" rel="next">ถัดไป &raquo;</a>
    <?php else: ?>
        <span class="disabled">ถัดไป &raquo;</span>
    <?php endif; ?>
</nav>

<p class="pagination-summary">
    แสดง <?= number_format($offset + 1) ?>–<?= number_format(min($offset + PER_PAGE, $total)) ?>
    จาก <?= number_format($total) ?> รายการ
</p>
<?php endif; ?>
