<?php

declare(strict_types=1);

namespace CarCare;

use RuntimeException;

/**
 * ฟีดแบ็คจากผู้ใช้ — รับได้สองทาง: จากแอพ (POST /api/feedback) และจากหน้าเว็บ (feedback.php)
 *
 * ตัวตรวจข้อมูลอยู่ที่คลาสนี้ที่เดียว ทั้งสองช่องทางจึงได้กติกาและข้อความบอกเหตุ
 * ชุดเดียวกัน ถ้าแยกไปเขียนในแต่ละหน้า สุดท้ายเงื่อนไขจะเพี้ยนกันเองทีหลัง
 *
 * ระบบนี้ไม่มีหน้าแอดมิน — อ่านฟีดแบ็คด้วย SQL ตรง ๆ (ดูตัวอย่างคิวรีใน README)
 * คอลัมน์ status จึงมีไว้ให้ไล่สถานะด้วยมือ: new → reading → done
 */
final class Feedback
{
    /** ชนิดที่รับ — ค่าอื่นถูกปฏิเสธ ไม่ใช่เงียบ ๆ แปลงเป็น other แล้วเราอ่านผิดทีหลัง */
    public const KINDS = ['bug', 'idea', 'other'];

    /** ป้ายไทยของแต่ละชนิด ใช้ในฟอร์มเว็บและตอนสรุปให้คนอ่าน */
    public const KIND_LABELS = [
        'bug'   => 'แจ้งปัญหา / บั๊ก',
        'idea'  => 'ข้อเสนอแนะ',
        'other' => 'อื่น ๆ',
    ];

    /** ช่องทางที่ฟีดแบ็คเข้ามาได้ */
    public const SOURCES = ['app', 'web'];

    /** ความยาวข้อความที่รับ — public เพราะฟอร์มบนเว็บต้องใช้ค่าเดียวกันใน maxlength */
    public const MESSAGE_MIN = 5;
    public const MESSAGE_MAX = 4000;

    /** ความยาวสูงสุดของแต่ละคอลัมน์ ตรงกับ schema.sql — ตัดให้พอดีแทนที่จะให้ MySQL ปฏิเสธ */
    private const CONTACT_MAX     = 255;
    private const APP_VERSION_MAX = 32;
    private const PLATFORM_MAX    = 32;
    private const DEVICE_MAX      = 191;

    /** ส่งได้ไม่เกินกี่ครั้งต่อชั่วโมงต่อคน — เกินกว่านี้ไม่ใช่คนที่ตั้งใจส่งฟีดแบ็คแล้ว */
    private const MAX_PER_HOUR = 10;
    private const HOUR_MS      = 3600 * 1000;

    /** ข้อความเดิมที่ถูกส่งซ้ำภายในช่วงนี้ นับเป็นการกดส่งครั้งเดียว */
    private const DEDUPE_WINDOW_MS = 10 * 60 * 1000;

    /**
     * บันทึกฟีดแบ็คหนึ่งชิ้น
     *
     * @param string $source 'app' หรือ 'web' — ฝั่งเซิร์ฟเวอร์กำหนดจากช่องทางที่คำขอเข้ามา
     *                       ไม่รับค่านี้จากไคลเอนต์ ไม่งั้นที่มาของฟีดแบ็คก็เชื่อไม่ได้
     * @param array<string, mixed> $input ข้อมูลดิบจาก JSON body หรือ $_POST
     *
     * @return array{id: int, duplicate: bool} duplicate = true เมื่อเป็นการกดส่งซ้ำของข้อความเดิม
     *
     * @throws RateLimitException ส่งถี่เกินโควตา (ตัวเรียกต้องตอบ 429)
     * @throws RuntimeException   ข้อมูลไม่ผ่านการตรวจ (ข้อความพร้อมแสดงให้ผู้ใช้ได้เลย)
     */
    public static function submit(int $userId, string $source, array $input): array
    {
        if (!in_array($source, self::SOURCES, true)) {
            throw new RuntimeException('ช่องทางที่ส่งฟีดแบ็คไม่ถูกต้อง');
        }

        $kind = self::text($input['kind'] ?? '');
        if (!in_array($kind, self::KINDS, true)) {
            throw new RuntimeException('กรุณาเลือกชนิดของฟีดแบ็ค');
        }

        $message = self::text($input['message'] ?? '');
        $length  = mb_strlen($message);
        if ($length < self::MESSAGE_MIN) {
            throw new RuntimeException('กรุณาเขียนรายละเอียดอย่างน้อย ' . self::MESSAGE_MIN . ' ตัวอักษร');
        }
        if ($length > self::MESSAGE_MAX) {
            throw new RuntimeException(
                'ข้อความยาวเกิน ' . number_format(self::MESSAGE_MAX) . ' ตัวอักษร (ที่ส่งมา '
                . number_format($length) . ')'
            );
        }

        $rating = self::rating($input['rating'] ?? null);

        // ข้อมูลเครื่องเป็นของแถม ขาดได้ — ถ้าตัดสั้นแล้วไม่เหลืออะไรก็เก็บเป็น NULL
        // ดีกว่าเก็บสตริงว่างซึ่งตอนอ่านทีหลังแยกไม่ออกว่า "ไม่ได้ส่งมา" หรือ "ส่งมาว่าง"
        $contact    = self::nullable($input['contact']     ?? null, self::CONTACT_MAX);
        $appVersion = self::nullable($input['app_version'] ?? null, self::APP_VERSION_MAX);
        $platform   = self::nullable($input['platform']    ?? null, self::PLATFORM_MAX);
        $device     = self::nullable($input['device']      ?? null, self::DEVICE_MAX);

        $pdo = Db::pdo();
        $now = Db::now();

        // หาข้อความเดิมที่เพิ่งส่งไปก่อนอื่น = ผู้ใช้กดส่งสองครั้ง หรือแอพยิงใหม่
        // หลังเน็ตหลุดตอนรอคำตอบ (แถวแรกเข้าไปแล้วแต่ไคลเอนต์ไม่รู้)
        // คืน id เดิมไปเหมือนสำเร็จ ดีกว่าขึ้น error ให้คนที่ทำถูกอยู่แล้ว
        //
        // ตรวจก่อน rate limit ตั้งใจ — ไม่งั้นคนที่เน็ตพังจนแอพยิงซ้ำหลายรอบ
        // จะโดนบล็อกทั้งที่ฟีดแบ็คของเขาเข้าไปแค่ชิ้นเดียว
        $duplicate = $pdo->prepare(
            'SELECT id FROM feedback
             WHERE user_id = ? AND created_at >= ? AND message = ?
             ORDER BY id DESC
             LIMIT 1'
        );
        $duplicate->execute([$userId, $now - self::DEDUPE_WINDOW_MS, $message]);
        $existingId = $duplicate->fetchColumn();
        if ($existingId !== false) {
            return ['id' => (int) $existingId, 'duplicate' => true];
        }

        $recent = $pdo->prepare('SELECT COUNT(*) FROM feedback WHERE user_id = ? AND created_at >= ?');
        $recent->execute([$userId, $now - self::HOUR_MS]);
        if ((int) $recent->fetchColumn() >= self::MAX_PER_HOUR) {
            throw new RateLimitException('ส่งฟีดแบ็คถี่เกินไป กรุณารอสักครู่แล้วลองใหม่');
        }

        $insert = $pdo->prepare(
            'INSERT INTO feedback
                (user_id, kind, rating, message, contact, source, app_version, platform, device, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $insert->execute([
            $userId,
            $kind,
            $rating,
            $message,
            $contact,
            $source,
            $appVersion,
            $platform,
            $device,
            $now,
        ]);

        return ['id' => (int) $pdo->lastInsertId(), 'duplicate' => false];
    }

    /** คะแนน 1–5 หรือ null ถ้าผู้ใช้ไม่ให้ — ค่านอกช่วงถือว่าผิด ไม่ใช่ปัดเข้าช่วง */
    private static function rating(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (!is_numeric($value)) {
            throw new RuntimeException('คะแนนต้องเป็นตัวเลข 1 ถึง 5');
        }

        $rating = (int) $value;
        if ($rating < 1 || $rating > 5) {
            throw new RuntimeException('คะแนนต้องอยู่ระหว่าง 1 ถึง 5');
        }

        return $rating;
    }

    /** เหมือน text() แต่คืน null เมื่อไม่เหลืออะไร และตัดความยาวตามคอลัมน์ */
    private static function nullable(mixed $value, int $max): ?string
    {
        $text = self::text($value, $max);

        return $text === '' ? null : $text;
    }

    /**
     * ทำความสะอาดข้อความจากผู้ใช้ก่อนลงฐานข้อมูล
     *
     * ต้องตรวจ UTF-8 เองก่อน เพราะไบต์ที่ไม่ใช่ UTF-8 จะทำให้ MySQL (utf8mb4)
     * ปฏิเสธคำสั่งทั้งชุด แล้วผู้ใช้จะได้ข้อความ "เซิร์ฟเวอร์ผิดพลาด" ลอย ๆ
     * ทั้งที่สาเหตุจริงคือตัวอักษรที่ส่งมา
     *
     * อักขระควบคุมถูกตัดทิ้ง (เว้น \n กับ \t) เพราะฟีดแบ็คถูกอ่านผ่าน terminal/SQL
     * client เป็นหลัก อักขระพวกนั้นทำให้ผลลัพธ์เพี้ยนตอนอ่าน
     */
    private static function text(mixed $value, ?int $max = null): string
    {
        if (!is_string($value)) {
            $value = is_scalar($value) ? (string) $value : '';
        }

        if (!mb_check_encoding($value, 'UTF-8')) {
            throw new RuntimeException('ข้อความมีอักขระที่ระบบอ่านไม่ได้');
        }

        // ฟอร์มบนเว็บส่งขึ้นบรรทัดใหม่มาเป็น CRLF ทำให้ข้อความเดิมจากแอพกับจากเว็บ
        // ไม่เท่ากันในสายตาของการเทียบข้อความซ้ำ จึงทำให้เป็น \n ให้เหมือนกันก่อน
        $value = str_replace(["\r\n", "\r"], "\n", $value);
        $value = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $value) ?? '';
        $value = trim($value);

        return $max === null ? $value : mb_substr($value, 0, $max);
    }
}
