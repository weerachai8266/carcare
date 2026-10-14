<?php

declare(strict_types=1);

/**
 * ตัวจัดเส้นทางของ API ทั้งหมด
 *
 * ทุกเส้นทางรับ/ส่ง JSON และต้องมี `Authorization: Bearer <token>` ยกเว้น /auth/google
 */

require_once dirname(__DIR__, 2) . '/src/bootstrap.php';

use CarCare\Auth;
use CarCare\Catalog;
use CarCare\Db;
use CarCare\Feedback;
use CarCare\Http;
use CarCare\RateLimitException;
use CarCare\Sync;

$path   = Http::path();
$method = Http::method();

try {
    switch ("{$method} {$path}") {
        case 'POST /auth/google':
            $body    = Http::body();
            $idToken = (string) ($body['id_token'] ?? '');
            if ($idToken === '') {
                Http::json(['error' => 'ไม่ได้ส่ง id_token มา'], 400);
            }

            $claims = Auth::verifyGoogleIdToken($idToken);
            $user   = Auth::upsertUser($claims);
            $issued = Auth::issueToken((int) $user['id'], $body['device_name'] ?? null);

            Http::json([
                'token'      => $issued['token'],
                'expires_at' => $issued['expires_at'],
                'user'       => [
                    'id'      => (int) $user['id'],
                    'email'   => $user['email'],
                    'name'    => $user['name'],
                    'picture' => $user['picture_url'],
                ],
            ]);
            // no break — Http::json จบการทำงานไปแล้ว

        case 'POST /auth/logout':
            Auth::logout();
            Http::json(['ok' => true]);

        case 'GET /me':
            $user = Auth::requireUser();
            Http::json([
                'id'      => (int) $user['id'],
                'email'   => $user['email'],
                'name'    => $user['name'],
                'picture' => $user['picture_url'],
            ]);

        case 'POST /sync':
            $user = Auth::requireUser();
            $body = Http::body();
            $since = (int) ($body['since'] ?? 0);

            $pushed = Sync::push((int) $user['id'], $body['changes'] ?? []);

            $catalog = $body['catalog'] ?? [];
            if (is_array($catalog)) {
                Catalog::pushCustom(
                    (int) $user['id'],
                    $catalog['car_makes'] ?? [],
                    $catalog['car_models'] ?? []
                );
            }

            // อ่านเวลาหลังเขียนเสร็จ เพื่อไม่ให้แถวที่เขียนระหว่างนี้หลุดจากรอบถัดไป
            $serverTime = Db::now();

            Http::json([
                'server_time' => $serverTime,
                'pushed'      => $pushed,
                'changes'     => Sync::pull((int) $user['id'], $since),
                'catalog'     => Catalog::pull((int) $user['id'], $since),
            ]);

        case 'POST /feedback':
            $user = Auth::requireUser();
            // source เป็น 'app' เสมอเพราะเส้นทางนี้มีแต่แอพเรียก — หน้าเว็บส่งผ่าน
            // feedback.php ของตัวเอง ไม่ผ่าน API (ต้องมีโทเคน CSRF ของฟอร์ม)
            $result = Feedback::submit((int) $user['id'], 'app', Http::body());

            Http::json(['ok' => true, 'id' => $result['id'], 'duplicate' => $result['duplicate']]);

        case 'GET /catalog':
            $user  = Auth::requireUser();
            $since = (int) ($_GET['since'] ?? 0);
            Http::json(Catalog::pull((int) $user['id'], $since));

        case 'GET /stats/model':
            Auth::requireUser();
            $modelId = (string) ($_GET['model_id'] ?? '');
            if ($modelId === '') {
                Http::json(['error' => 'ต้องระบุ model_id'], 400);
            }

            $limit = (int) Db::config()['stats']['top_per_category'];
            $stmt  = Db::pdo()->prepare(
                'SELECT task_name, category, sample_count, vehicle_count,
                        median_km, p25_km, p75_km, median_days
                 FROM model_interval_stats
                 WHERE model_id = ?
                 ORDER BY category ASC, vehicle_count DESC, sample_count DESC'
            );
            $stmt->execute([$modelId]);

            // จัดกลุ่มตามหมวดแล้วตัดหมวดละ top N ใน PHP
            // (การทำใน SQL ต้องใช้ window function ซ้อนอีกชั้นโดยไม่ได้อะไรเพิ่ม)
            $byCategory = [];
            foreach ($stmt->fetchAll() as $row) {
                $category = $row['category'];
                if (count($byCategory[$category] ?? []) >= $limit) {
                    continue;
                }
                $byCategory[$category][] = [
                    'task_name'     => $row['task_name'],
                    'sample_count'  => (int) $row['sample_count'],
                    'vehicle_count' => (int) $row['vehicle_count'],
                    'median_km'     => (float) $row['median_km'],
                    'p25_km'        => (float) $row['p25_km'],
                    'p75_km'        => (float) $row['p75_km'],
                    'median_days'   => (int) $row['median_days'],
                ];
            }

            Http::json(['model_id' => $modelId, 'categories' => $byCategory]);

        default:
            Http::json(['error' => 'ไม่พบเส้นทางนี้', 'path' => $path], 404);
    }
} catch (PDOException $e) {
    // ต้องดักก่อน RuntimeException เพราะ PDOException สืบทอดมาจากมัน
    // ไม่งั้นข้อความ SQL ดิบ (ชื่อตาราง ชื่อคอลัมน์) จะหลุดออกไปหาไคลเอนต์
    error_log('[carcare] sql: ' . $e->getMessage());
    Http::json(['error' => 'เซิร์ฟเวอร์ผิดพลาด'], 500);
} catch (RateLimitException $e) {
    // ต้องดักก่อน RuntimeException เพราะสืบทอดมาจากมัน — และต้องเป็น 429 ไม่ใช่ 400
    // ไคลเอนต์จะได้รู้ว่าให้รอแล้วลองใหม่ ไม่ใช่ให้ผู้ใช้ไปแก้ข้อความของตัวเอง
    Http::json(['error' => $e->getMessage()], 429);
} catch (RuntimeException $e) {
    Http::json(['error' => $e->getMessage()], 400);
} catch (Throwable $e) {
    error_log('[carcare] ' . $e->getMessage());
    // ไม่ส่งรายละเอียดข้อผิดพลาดออกไป เพราะมักมีชื่อตาราง/พาธของเซิร์ฟเวอร์ติดไปด้วย
    Http::json(['error' => 'เซิร์ฟเวอร์ผิดพลาด'], 500);
}
