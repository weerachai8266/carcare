<?php

declare(strict_types=1);

/** @var string $title */
/** @var array|null $currentUser */
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= e($title ?? 'สถิติการบำรุงรักษารถ') ?></title>
    <link rel="stylesheet" href="<?= asset('assets/style.css') ?>">
</head>
<body>
<header class="site-header">
    <a class="brand" href="<?= e(url('/')) ?>">บันทึกรถ · สถิติชุมชน</a>
    <nav>
        <?php if (!empty($currentUser)): ?>
            <a href="<?= e(url('/models.php')) ?>">รุ่นรถ</a>
            <a href="<?= e(url('/feedback.php')) ?>">ส่งฟีดแบ็ค</a>
            <span class="user"><?= e($currentUser['name'] ?: $currentUser['email']) ?></span>
            <a href="<?= e(url('/logout.php')) ?>">ออกจากระบบ</a>
        <?php else: ?>
            <a href="<?= e(url('/login.php')) ?>">เข้าสู่ระบบ</a>
        <?php endif; ?>
    </nav>
</header>
<main class="container">
