<?php

declare(strict_types=1);

namespace CarCare;

use PDO;
use RuntimeException;

/**
 * จุดเดียวที่สร้าง PDO และอ่าน config เพื่อไม่ให้แต่ละไฟล์ต่อฐานข้อมูลเอง
 */
final class Db
{
    private static ?PDO $pdo = null;
    private static ?array $config = null;

    public static function config(): array
    {
        if (self::$config === null) {
            $path = dirname(__DIR__) . '/config.php';
            if (!is_file($path)) {
                throw new RuntimeException('ยังไม่มีไฟล์ config.php — คัดลอกจาก config.example.php ก่อน');
            }
            self::$config = require $path;
        }

        return self::$config;
    }

    public static function pdo(): PDO
    {
        if (self::$pdo !== null) {
            return self::$pdo;
        }

        $db = self::config()['db'];
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            $db['host'],
            $db['port'],
            $db['name']
        );

        self::$pdo = new PDO($dsn, $db['user'], $db['password'], [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            // ปิด emulated prepares เพื่อให้ bind แบบ PARAM_INT ส่งเป็นตัวเลขจริง
            // ไม่งั้น LIMIT ที่ถูก quote เป็นสตริงจะทำให้ SQL พัง
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);

        return self::$pdo;
    }

    /** เวลาปัจจุบันเป็น epoch millisecond ให้ตรงหน่วยกับฝั่งแอพ */
    public static function now(): int
    {
        return (int) round(microtime(true) * 1000);
    }
}
