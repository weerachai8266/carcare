<?php

declare(strict_types=1);

namespace CarCare;

use PDO;
use RuntimeException;

/**
 * ล็อกอินด้วย Google แล้วออกโทเคนเซสชันของแอพเอง
 *
 * ไม่ใช้ Google ID token เป็นโทเคนประจำตัวโดยตรง เพราะมันหมดอายุใน 1 ชั่วโมง
 * และเพิกถอนทีละเครื่องไม่ได้ เราจึงแลกเป็นโทเคนของเราเองที่คุมอายุและลบได้
 */
final class Auth
{
    /**
     * ตรวจ Google ID token แล้วคืนข้อมูลผู้ใช้จาก Google
     *
     * ใช้ปลายทาง tokeninfo ของ Google ตรวจลายเซ็นให้ แทนการ verify JWT เอง
     * แลกความเร็วเล็กน้อยกับการไม่ต้องดูแล JWKS/การหมุนกุญแจเอง
     * ซึ่งเป็นจุดที่พลาดแล้วกลายเป็นช่องโหว่ได้ง่ายที่สุด
     *
     * @throws RuntimeException ถ้าโทเคนไม่ผ่าน
     */
    public static function verifyGoogleIdToken(string $idToken): array
    {
        $url = 'https://oauth2.googleapis.com/tokeninfo?id_token=' . urlencode($idToken);

        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 10,
            CURLOPT_SSL_VERIFYPEER => true,
        ]);
        $body   = curl_exec($ch);
        $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error  = curl_error($ch);
        curl_close($ch);

        if ($body === false) {
            throw new RuntimeException('ติดต่อ Google ไม่ได้: ' . $error);
        }
        if ($status !== 200) {
            throw new RuntimeException('Google ปฏิเสธโทเคนนี้');
        }

        $claims = json_decode((string) $body, true);
        if (!is_array($claims) || !isset($claims['sub'], $claims['aud'])) {
            throw new RuntimeException('ข้อมูลจาก Google ไม่ครบ');
        }

        // aud ต้องเป็น client id ของแอพเรา ไม่งั้นใครก็เอา token ของแอพอื่นมาสวมได้
        $allowed = Db::config()['google_client_ids'];
        if (!in_array($claims['aud'], $allowed, true)) {
            throw new RuntimeException('โทเคนนี้ไม่ได้ออกให้แอพนี้');
        }

        if (isset($claims['exp']) && (int) $claims['exp'] < time()) {
            throw new RuntimeException('โทเคนหมดอายุแล้ว');
        }

        if (($claims['email_verified'] ?? 'false') !== 'true' && ($claims['email_verified'] ?? false) !== true) {
            throw new RuntimeException('อีเมลนี้ยังไม่ได้ยืนยันกับ Google');
        }

        return $claims;
    }

    /** หาผู้ใช้จาก google sub ถ้ายังไม่มีก็สร้างใหม่ */
    public static function upsertUser(array $claims): array
    {
        $pdo = Db::pdo();
        $now = Db::now();

        $stmt = $pdo->prepare('SELECT * FROM users WHERE google_sub = ?');
        $stmt->execute([$claims['sub']]);
        $user = $stmt->fetch();

        if ($user) {
            $update = $pdo->prepare(
                'UPDATE users SET email = ?, name = ?, picture_url = ?, updated_at = ? WHERE id = ?'
            );
            $update->execute([
                $claims['email'] ?? '',
                $claims['name'] ?? null,
                $claims['picture'] ?? null,
                $now,
                $user['id'],
            ]);

            return array_merge($user, [
                'email'       => $claims['email'] ?? '',
                'name'        => $claims['name'] ?? null,
                'picture_url' => $claims['picture'] ?? null,
            ]);
        }

        $insert = $pdo->prepare(
            'INSERT INTO users (google_sub, email, name, picture_url, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $insert->execute([
            $claims['sub'],
            $claims['email'] ?? '',
            $claims['name'] ?? null,
            $claims['picture'] ?? null,
            $now,
            $now,
        ]);

        $stmt->execute([$claims['sub']]);

        return $stmt->fetch();
    }

    /** ออกโทเคนเซสชันใหม่ คืนค่าตัวโทเคนแบบเต็ม (เก็บในฐานข้อมูลเป็น hash) */
    public static function issueToken(int $userId, ?string $deviceName): array
    {
        $token = bin2hex(random_bytes(32));
        $days  = (int) Db::config()['session_days'];
        $now   = Db::now();
        $expires = $now + $days * 86400 * 1000;

        $stmt = Db::pdo()->prepare(
            'INSERT INTO sessions (token_hash, user_id, device_name, created_at, expires_at, last_seen_at)
             VALUES (?, ?, ?, ?, ?, ?)'
        );
        $stmt->execute([hash('sha256', $token), $userId, $deviceName, $now, $expires, $now]);

        return ['token' => $token, 'expires_at' => $expires];
    }

    /**
     * อ่านผู้ใช้จากโทเคนใน header `Authorization: Bearer ...` หรือจากคุกกี้ของหน้าเว็บ
     *
     * คืน null ถ้าไม่มีโทเคน/โทเคนผิด/หมดอายุ
     */
    public static function currentUser(): ?array
    {
        $token = self::tokenFromRequest();
        if ($token === null) {
            return null;
        }

        $stmt = Db::pdo()->prepare(
            'SELECT u.*, s.token_hash, s.expires_at
             FROM sessions s
             JOIN users u ON u.id = s.user_id
             WHERE s.token_hash = ?'
        );
        $stmt->execute([hash('sha256', $token)]);
        $row = $stmt->fetch();

        if (!$row || (int) $row['expires_at'] < Db::now()) {
            return null;
        }

        $touch = Db::pdo()->prepare('UPDATE sessions SET last_seen_at = ? WHERE token_hash = ?');
        $touch->execute([Db::now(), $row['token_hash']]);

        return $row;
    }

    public static function requireUser(): array
    {
        $user = self::currentUser();
        if ($user === null) {
            Http::json(['error' => 'ต้องล็อกอินก่อน'], 401);
        }

        return $user;
    }

    /**
     * โทเคนกันคำขอข้ามเว็บ (CSRF) สำหรับฟอร์มบนหน้าเว็บ
     *
     * หน้าเว็บยืนยันตัวตนด้วยคุกกี้ เบราว์เซอร์จึงแนบคุกกี้ให้กับฟอร์มที่เว็บอื่น
     * สร้างขึ้นมาด้วย — คำขอนั้นจะถือว่าล็อกอินแล้วเหมือนกัน จึงต้องมีค่าที่เว็บอื่น
     * อ่านไม่ได้แนบไปในฟอร์ม แล้วเทียบตอนรับ POST
     *
     * ค่านี้ได้มาจากโทเคนเซสชันในคุกกี้ จึงไม่ต้องเก็บสถานะเพิ่มและไม่ต้องเปิด
     * session ของ PHP ผูกกับ $purpose ด้วยเพื่อให้โทเคนของฟอร์มหนึ่งใช้กับอีกฟอร์มไม่ได้
     *
     * (คุกกี้ตั้ง SameSite=Lax ไว้แล้วซึ่งกัน POST ข้ามเว็บได้เกือบหมด ชั้นนี้เผื่อ
     *  เบราว์เซอร์ที่ไม่รู้จัก SameSite ซึ่งจะส่งคุกกี้ไปเหมือนไม่มีธงนั้นเลย)
     */
    public static function csrfToken(string $purpose): string
    {
        $token = self::tokenFromRequest();
        if ($token === null) {
            return '';
        }

        return hash_hmac('sha256', $purpose, $token);
    }

    /** เทียบโทเคน CSRF แบบคงเวลา — คืน false เมื่อไม่มีเซสชันหรือค่าไม่ตรง */
    public static function checkCsrf(string $purpose, string $given): bool
    {
        $expected = self::csrfToken($purpose);

        return $expected !== '' && hash_equals($expected, $given);
    }

    public static function logout(): void
    {
        $token = self::tokenFromRequest();
        if ($token === null) {
            return;
        }

        $stmt = Db::pdo()->prepare('DELETE FROM sessions WHERE token_hash = ?');
        $stmt->execute([hash('sha256', $token)]);
    }

    private static function tokenFromRequest(): ?string
    {
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
        if (preg_match('/^Bearer\s+(\S+)$/i', $header, $m) === 1) {
            return $m[1];
        }

        // หน้าเว็บใช้คุกกี้แทน เพราะเบราว์เซอร์ส่ง header เองไม่ได้ตอนโหลดหน้า
        return $_COOKIE['carcare_session'] ?? null;
    }
}
