<?php

declare(strict_types=1);

/**
 * โหลดคลาสทั้งหมดของโปรเจกต์โดยไม่ต้องใช้ composer
 *
 * เซิร์ฟเวอร์นี้ตั้งใจให้ deploy บนโฮสต์ทั่วไปได้เลย จึงไม่พึ่ง dependency ภายนอก
 * ทุกคลาสอยู่ใต้เนมสเปซ CarCare และหนึ่งไฟล์ต่อหนึ่งคลาส
 */

spl_autoload_register(static function (string $class): void {
    $prefix = 'CarCare\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }

    $relative = substr($class, strlen($prefix));
    $file     = __DIR__ . '/' . str_replace('\\', '/', $relative) . '.php';

    if (is_file($file)) {
        require_once $file;
    }
});

date_default_timezone_set('Asia/Bangkok');
mb_internal_encoding('UTF-8');
