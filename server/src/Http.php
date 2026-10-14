<?php

declare(strict_types=1);

namespace CarCare;

/**
 * ตัวช่วยเล็ก ๆ สำหรับ API: อ่าน JSON เข้า ส่ง JSON ออก
 */
final class Http
{
    /** ส่ง JSON แล้วจบการทำงานทันที เพื่อไม่ให้มีอะไรถูก echo ตามหลังไปปน */
    public static function json(array $payload, int $status = 200): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }

    /** อ่าน body เป็น array — คืน array ว่างถ้า body ว่างหรือไม่ใช่ JSON object */
    public static function body(): array
    {
        $raw = file_get_contents('php://input');
        if ($raw === false || $raw === '') {
            return [];
        }

        $decoded = json_decode($raw, true);

        return is_array($decoded) ? $decoded : [];
    }

    public static function method(): string
    {
        return $_SERVER['REQUEST_METHOD'] ?? 'GET';
    }

    /**
     * เส้นทางหลัง /api เช่น "/sync" หรือ "/auth/google"
     *
     * รองรับทั้งกรณีมี rewrite (PATH_INFO) และกรณีเรียกไฟล์ตรง ๆ
     * เพื่อให้ deploy บนโฮสต์ที่เปิด .htaccess ไม่ได้ก็ยังใช้งานได้
     */
    public static function path(): string
    {
        $path = $_SERVER['PATH_INFO'] ?? '';
        if ($path === '') {
            $uri  = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
            $path = preg_replace('#^.*/api(?:/index\.php)?#', '', $uri) ?? '';
        }

        return '/' . trim($path, '/');
    }
}
