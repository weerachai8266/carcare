<?php

declare(strict_types=1);

/**
 * ทดสอบ API ทั้งเส้นทางจริงผ่าน HTTP โดยไม่ต้องมีบัญชี Google
 *
 * ใช้ตรวจหลังติดตั้ง/ย้ายเครื่อง ว่าชิ้นส่วนที่ต่อกันอยู่ทำงานครบ:
 * Apache rewrite → Bearer token → Sync push/pull → คำนวณสถิติ → API สถิติ
 * ส่วนที่ทดสอบไม่ได้คือการแลก Google id_token เพราะต้องมีโทเคนจริงจาก Google
 * (จึงออกโทเคนเซสชันตรง ๆ ด้วย Auth::issueToken แทน ซึ่งเป็นโค้ดชุดเดียวกับ
 *  ที่ /auth/google เรียกหลังตรวจโทเคนผ่าน)
 *
 *   php bin/smoke_test.php [base_url]
 *
 * base_url ปริยายคือ http://127.0.0.1/carcare
 *
 * สร้างผู้ใช้ทดสอบ 3 คนกับรุ่นรถสมมุติ แล้วลบทิ้งทั้งหมดตอนจบเสมอ
 * (รวมถึงตอน assert ไม่ผ่าน) และคำนวณตารางสถิติใหม่ให้ตรงกับข้อมูลจริงก่อนออก
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit("สคริปต์นี้รันได้จากบรรทัดคำสั่งเท่านั้น\n");
}

require_once dirname(__DIR__) . '/src/bootstrap.php';

use CarCare\Auth;
use CarCare\Db;
use CarCare\IntervalStats;

$baseUrl = rtrim($argv[1] ?? 'http://127.0.0.1/carcare', '/');

// คำนำหน้าที่ใช้ทั้งตอนสร้างและตอนลบ ต้องไม่ชนกับข้อมูลจริงเด็ดขาด
const SMOKE_SUB_PREFIX = 'smoketest:';
const SMOKE_MAKE_ID    = 'zz-smoketest';
const SMOKE_MODEL_ID   = 'zz-smoketest-model';

// ฟีดแบ็คไม่ถูกลบตามผู้ใช้ (FOREIGN KEY เป็น ON DELETE SET NULL ตั้งใจ)
// จึงต้องมีคำที่ปักไว้ในข้อความให้ตามลบเองได้ ไม่ปนกับฟีดแบ็คจริง
const SMOKE_FEEDBACK_MARK = '[smoketest]';

$failures = 0;
$checks   = 0;

function check(string $label, bool $ok, string $detail = ''): void
{
    global $failures, $checks;
    $checks++;
    if ($ok) {
        echo "  [ผ่าน] {$label}\n";

        return;
    }
    $failures++;
    echo "  [ตก]  {$label}" . ($detail === '' ? '' : " — {$detail}") . "\n";
}

/**
 * ยิง HTTP จริงไปที่เว็บเซิร์ฟเวอร์ เพื่อให้ผ่าน rewrite และการอ่าน header ด้วย
 *
 * @return array{status: int, body: array<string, mixed>, raw: string}
 */
function request(string $method, string $path, ?array $payload = null, ?string $token = null): array
{
    global $baseUrl;

    $headers = ['Accept: application/json'];
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer ' . $token;
    }

    $ch = curl_init($baseUrl . $path);
    $options = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_TIMEOUT        => 30,
        CURLOPT_HTTPHEADER     => $headers,
    ];
    if ($payload !== null) {
        $options[CURLOPT_POSTFIELDS] = json_encode($payload, JSON_UNESCAPED_UNICODE);
        $headers[]                   = 'Content-Type: application/json';
        $options[CURLOPT_HTTPHEADER] = $headers;
    }
    curl_setopt_array($ch, $options);

    $raw    = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error  = curl_error($ch);
    curl_close($ch);

    if ($raw === false) {
        throw new RuntimeException("เรียก {$method} {$path} ไม่สำเร็จ: {$error}");
    }

    $decoded = json_decode((string) $raw, true);

    return ['status' => $status, 'body' => is_array($decoded) ? $decoded : [], 'raw' => (string) $raw];
}

/**
 * อ่านค่า Location ของการ redirect โดยไม่ตามไปต่อ
 *
 * request() ดูได้แค่ status ซึ่งแยกไม่ออกว่า 302 นั้นเด้งไปล็อกอินหรือเด้งไปหน้าอื่น
 */
function redirectTarget(string $path): string
{
    global $baseUrl;

    $ch = curl_init($baseUrl . $path);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 30,
        // ขอแค่ header พอ (HEAD) — PHP ยังทำงานทั้งไฟล์และส่ง Location ให้เหมือน GET
        CURLOPT_NOBODY         => true,
    ]);
    curl_exec($ch);
    $target = (string) curl_getinfo($ch, CURLINFO_REDIRECT_URL);
    curl_close($ch);

    return $target;
}

/** UUID v4 แบบเดียวกับที่ฝั่งแอพสร้าง (id ของทุกตารางมาจากเครื่องลูก) */
function uuid(): string
{
    $bytes    = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);

    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4));
}

/** ลบทุกอย่างที่สคริปต์นี้สร้าง แล้วคำนวณสถิติใหม่จากข้อมูลจริงที่เหลือ */
function cleanup(PDO $pdo): void
{
    // ตารางข้อมูลผู้ใช้ทุกตารางมี FOREIGN KEY ... ON DELETE CASCADE มาที่ users
    // ลบผู้ใช้จึงลบรถ/การเติมน้ำมัน/ประวัติ/เซสชันตามไปครบโดยไม่ต้องไล่ลบทีละตาราง
    $stmt = $pdo->prepare('DELETE FROM users WHERE google_sub LIKE ?');
    $stmt->execute([SMOKE_SUB_PREFIX . '%']);
    $deletedUsers = $stmt->rowCount();

    // ต้องลบด้วยคำที่ปักไว้ในข้อความ ไม่ใช่ตาม user_id เพราะการลบผู้ใช้ข้างบน
    // แค่ตั้ง feedback.user_id เป็น NULL ไม่ได้ลบแถวตามไปด้วย
    $pdo->prepare('DELETE FROM feedback WHERE message LIKE ?')
        ->execute(['%' . SMOKE_FEEDBACK_MARK . '%']);

    $pdo->prepare('DELETE FROM car_models WHERE id = ?')->execute([SMOKE_MODEL_ID]);
    $pdo->prepare('DELETE FROM car_makes WHERE id = ?')->execute([SMOKE_MAKE_ID]);

    // ตารางสถิติถูกเขียนทับทั้งชุดตอนทดสอบ ต้องคำนวณใหม่จากข้อมูลจริง
    // ไม่งั้นหน้าเว็บจะค้างอยู่กับผลที่มีรุ่นสมมุติปนอยู่จนกว่า cron รอบถัดไปจะรัน
    $config = Db::config()['stats'];
    IntervalStats::store(
        $pdo,
        IntervalStats::summarize(
            IntervalStats::fetchIntervals($pdo),
            (int) $config['min_samples'],
            (int) $config['min_vehicles']
        )
    );

    echo "ล้างข้อมูลทดสอบแล้ว (ผู้ใช้ {$deletedUsers} คน) และคำนวณสถิติใหม่จากข้อมูลจริง\n";
}

$pdo = Db::pdo();
$now = Db::now();
$day = 86400000;

// เผื่อรอบก่อนหน้าตายกลางคัน ให้ล้างของค้างก่อนเริ่ม
cleanup($pdo);

try {
    echo "\n=== เตรียมรุ่นรถสมมุติ ===\n";
    $pdo->prepare(
        'INSERT INTO car_makes (id, name, name_th, sort_order, is_custom, approved,
                                created_at, updated_at, synced_at)
         VALUES (?, ?, ?, 9999, 1, 1, ?, ?, ?)'
    )->execute([SMOKE_MAKE_ID, 'ZZ SmokeTest', 'ทดสอบระบบ', $now, $now, $now]);

    $pdo->prepare(
        'INSERT INTO car_models (id, make_id, name, body_type, sort_order, is_custom, approved,
                                 created_at, updated_at, synced_at)
         VALUES (?, ?, ?, ?, 9999, 1, 1, ?, ?, ?)'
    )->execute([SMOKE_MODEL_ID, SMOKE_MAKE_ID, 'Smoke', 'sedan', $now, $now, $now]);
    echo "  สร้าง " . SMOKE_MODEL_ID . " แล้ว\n";

    echo "\n=== ตรวจการยืนยันตัวตน ===\n";
    $anon = request('GET', '/api/me');
    check('ไม่มีโทเคน ต้องได้ 401', $anon['status'] === 401, "ได้ {$anon['status']}: {$anon['raw']}");

    $bad = request('GET', '/api/me', null, str_repeat('a', 64));
    check('โทเคนมั่ว ต้องได้ 401', $bad['status'] === 401, "ได้ {$bad['status']}");

    $missing = request('GET', '/api/no-such-route');
    check('เส้นทางที่ไม่มี ต้องได้ 404', $missing['status'] === 404, "ได้ {$missing['status']}");

    echo "\n=== สร้างผู้ใช้ทดสอบ 3 คน แล้วส่งข้อมูลขึ้นผ่าน /api/sync ===\n";

    // ระยะที่แต่ละคน "ทำจริง" ต่างกันเล็กน้อย เพื่อให้มัธยฐานกับ p25/p75 ไม่เท่ากันหมด
    // และเห็นได้ว่าการรวมข้ามสมาชิกทำงานจริง (เป็นคนละ user_id คนละ task_id)
    $odometerSets = [
        [10000, 20000, 30000, 40000],   // ช่วงละ 10,000
        [12000, 21000, 30000, 39000],   // ช่วงละ 9,000
        [11000, 23000, 35000, 47000],   // ช่วงละ 12,000
    ];

    $sessions = [];
    foreach ($odometerSets as $index => $odometers) {
        $person = $index + 1;
        $user   = Auth::upsertUser([
            'sub'   => SMOKE_SUB_PREFIX . $person,
            'email' => "smoketest{$person}@example.invalid",
            'name'  => "ผู้ใช้ทดสอบ {$person}",
        ]);
        $token = Auth::issueToken((int) $user['id'], 'smoke-test')['token'];

        $vehicleId = uuid();
        $taskId    = uuid();

        $records = [];
        foreach ($odometers as $i => $odo) {
            $records[] = [
                'id'         => uuid(),
                'vehicle_id' => $vehicleId,
                'task_id'    => $taskId,
                'title'      => 'เปลี่ยนน้ำมันเครื่อง',
                'date'       => $now - (400 - $i * 100) * $day,
                'odometer'   => $odo,
                'cost'       => 1200 + $i * 50,
                'workshop'   => 'อู่ทดสอบ',
                'created_at' => $now,
                'updated_at' => $now,
                'deleted'    => 0,
            ];
        }

        $payload = [
            'since'   => 0,
            'changes' => [
                'vehicles' => [[
                    'id'          => $vehicleId,
                    'name'        => "รถทดสอบ {$person}",
                    'make'        => 'ZZ SmokeTest',
                    'model'       => 'Smoke',
                    'make_id'     => SMOKE_MAKE_ID,
                    'model_id'    => SMOKE_MODEL_ID,
                    'year'        => 2022,
                    'fuel_type'   => 'gasoline95',
                    'initial_odo' => 0,
                    'is_active'   => 1,
                    'sort_order'  => 0,
                    'created_at'  => $now,
                    'updated_at'  => $now,
                    'deleted'     => 0,
                ]],
                'maintenance_tasks' => [[
                    'id'          => $taskId,
                    'vehicle_id'  => $vehicleId,
                    // คนที่ 3 พิมพ์ชื่อโดยมีช่องว่างเกิน — ต้องถูกรวมเป็นรายการเดียวกับคนอื่น
                    // (นี่คือเหตุผลที่ task_key ต้อง TRIM + ยุบช่องว่างก่อนจับกลุ่ม)
                    'name'        => $person === 3 ? '  เปลี่ยนน้ำมันเครื่อง ' : 'เปลี่ยนน้ำมันเครื่อง',
                    'category'    => 'เครื่องยนต์',
                    'interval_km' => 10000,
                    'is_active'   => 1,
                    'sort_order'  => 0,
                    'created_at'  => $now,
                    'updated_at'  => $now,
                    'deleted'     => 0,
                ]],
                'service_records' => $records,
                'fuel_entries'    => [[
                    'id'              => uuid(),
                    'vehicle_id'      => $vehicleId,
                    'date'            => $now - 10 * $day,
                    'odometer'        => end($odometers) + 500,
                    'liters'          => 40.5,
                    'price_per_liter' => 38.5,
                    'total_cost'      => 1559.25,
                    'is_full_tank'    => 1,
                    'created_at'      => $now,
                    'updated_at'      => $now,
                    'deleted'         => 0,
                ]],
            ],
        ];

        $response = request('POST', '/api/sync', $payload, $token);
        // 7 แถว = รถ 1 + รายการบำรุงรักษา 1 + ประวัติ 4 + การเติมน้ำมัน 1
        check(
            "คนที่ {$person} ส่งข้อมูลขึ้นได้",
            $response['status'] === 200 && ($response['body']['pushed'] ?? 0) === 7,
            "status {$response['status']} pushed=" . ($response['body']['pushed'] ?? '-') . " {$response['raw']}"
        );

        $sessions[] = [
            'token'   => $token,
            'user_id' => (int) $user['id'],
            'vehicle' => $vehicleId,
        ];
    }

    echo "\n=== ตรวจว่าดึงกลับลงมาได้ และไม่ปนกับของคนอื่น ===\n";
    $first = $sessions[0];
    $pull  = request('POST', '/api/sync', ['since' => 0, 'changes' => []], $first['token']);
    $vehicles = $pull['body']['changes']['vehicles'] ?? [];
    check('ดึงข้อมูลลงมาได้', $pull['status'] === 200 && count($vehicles) === 1, "ได้รถ " . count($vehicles) . " คัน");
    check(
        'เห็นเฉพาะรถของตัวเอง',
        ($vehicles[0]['id'] ?? '') === $first['vehicle'],
        'id ที่ได้: ' . ($vehicles[0]['id'] ?? '-')
    );
    check(
        'ประวัติของตัวเองครบ 4 รายการ',
        count($pull['body']['changes']['service_records'] ?? []) === 4,
        'ได้ ' . count($pull['body']['changes']['service_records'] ?? [])
    );
    check(
        'เคอร์เซอร์ server_time ถูกส่งกลับมา',
        ($pull['body']['server_time'] ?? 0) > 0
    );

    $afterAll = request('POST', '/api/sync', ['since' => $pull['body']['server_time'], 'changes' => []], $first['token']);
    check(
        'ขอด้วยเคอร์เซอร์ล่าสุด ต้องไม่ได้อะไรซ้ำ',
        ($afterAll['body']['changes']['vehicles'] ?? []) === [],
        'ยังได้ ' . count($afterAll['body']['changes']['vehicles'] ?? []) . ' แถว'
    );

    echo "\n=== ตรวจกติกา last-write-wins ===\n";

    // ต้องส่งคอลัมน์ NOT NULL มาให้ครบทุกครั้ง เพราะ Sync::push เติม NULL ให้คอลัมน์ที่ขาด
    // แล้ว MySQL โหมด strict จะปฏิเสธตั้งแต่ชั้น INSERT ก่อนถึง ON DUPLICATE KEY UPDATE
    $editVehicle = static function (string $name, int $updatedAt) use ($first, $now): array {
        return [
            'id'          => $first['vehicle'],
            'name'        => $name,
            'model_id'    => SMOKE_MODEL_ID,
            'initial_odo' => 0,
            'is_active'   => 1,
            'sort_order'  => 0,
            'created_at'  => $now,
            'updated_at'  => $updatedAt,
            'deleted'     => 0,
        ];
    };

    $stale = request('POST', '/api/sync', [
        'since'   => 0,
        'changes' => ['vehicles' => [$editVehicle('ชื่อจากเครื่องที่นาฬิกาช้า', $now - 60000)]],
    ], $first['token']);
    check('เซิร์ฟเวอร์รับแถวที่เก่ากว่าโดยไม่ error', $stale['status'] === 200, "status {$stale['status']} {$stale['raw']}");
    $name = $pdo->query('SELECT name FROM vehicles WHERE id = ' . $pdo->quote($first['vehicle']))->fetchColumn();
    check('แถวที่เก่ากว่าต้องไม่ทับของเดิม', $name === 'รถทดสอบ 1', "ชื่อตอนนี้: {$name}");

    request('POST', '/api/sync', [
        'since'   => 0,
        'changes' => ['vehicles' => [$editVehicle('ชื่อใหม่กว่า', $now + 60000)]],
    ], $first['token']);
    $name = $pdo->query('SELECT name FROM vehicles WHERE id = ' . $pdo->quote($first['vehicle']))->fetchColumn();
    check('แถวที่ใหม่กว่าต้องทับได้', $name === 'ชื่อใหม่กว่า', "ชื่อตอนนี้: {$name}");

    // id ของคนอื่น + updated_at ที่ใหม่กว่าทุกแถว = กรณีแย่งข้อมูลที่เลวร้ายที่สุด
    $second = $sessions[1];
    request('POST', '/api/sync', [
        'since'   => 0,
        'changes' => ['vehicles' => [$editVehicle('โดนแย่งไปแล้ว', $now + 999999)]],
    ], $second['token']);
    $row = $pdo->query(
        'SELECT name, user_id FROM vehicles WHERE id = ' . $pdo->quote($first['vehicle'])
    )->fetch();
    check(
        'ส่ง id ของคนอื่นขึ้นมา ต้องทับข้อมูลเขาไม่ได้',
        $row['name'] === 'ชื่อใหม่กว่า' && (int) $row['user_id'] === $first['user_id'],
        "ชื่อ {$row['name']} เจ้าของ {$row['user_id']}"
    );

    echo "\n=== ทนกับแถวที่ส่งมาไม่ครบ ===\n";

    // แอพคนละเวอร์ชันกับเซิร์ฟเวอร์จะรู้จักคอลัมน์ไม่เท่ากัน คอลัมน์ที่ schema
    // มีค่าปริยายอยู่แล้วจึงต้องขาดได้ ไม่ใช่ทำให้ซิงก์ทั้งก้อนพัง
    $sparseId = uuid();
    $sparse   = request('POST', '/api/sync', [
        'since'   => 0,
        'changes' => ['vehicles' => [[
            'id'         => $sparseId,
            'name'       => 'รถที่ส่งมาไม่ครบ',
            'model_id'   => SMOKE_MODEL_ID,
            'created_at' => $now,
            'updated_at' => $now,
        ]]],
    ], $first['token']);
    check('ขาดคอลัมน์ที่มีค่าปริยาย ต้องยังรับได้', $sparse['status'] === 200, "status {$sparse['status']} {$sparse['raw']}");

    $filled = $pdo->query(
        'SELECT sort_order, is_active, initial_odo, deleted FROM vehicles WHERE id = ' . $pdo->quote($sparseId)
    )->fetch();
    check(
        'เซิร์ฟเวอร์เติมค่าปริยายให้เอง',
        $filled !== false && (int) $filled['sort_order'] === 0 && (int) $filled['is_active'] === 1
            && (float) $filled['initial_odo'] === 0.0 && (int) $filled['deleted'] === 0,
        $filled === false ? 'ไม่มีแถว' : json_encode($filled, JSON_UNESCAPED_UNICODE)
    );

    // ส่วนคอลัมน์ที่เดาแทนไม่ได้ ต้องตอบเป็นข้อความของเราเอง ไม่ใช่ข้อความ SQL ดิบ
    $incomplete = request('POST', '/api/sync', [
        'since'   => 0,
        'changes' => ['fuel_entries' => [[
            'id'         => uuid(),
            'vehicle_id' => $first['vehicle'],
            'date'       => $now,
            'odometer'   => 50000,
            // ไม่ส่ง liters มา
            'created_at' => $now,
            'updated_at' => $now,
        ]]],
    ], $first['token']);
    check('ขาดคอลัมน์ที่ขาดไม่ได้ ต้องได้ 400', $incomplete['status'] === 400, "ได้ {$incomplete['status']}");
    check(
        'ข้อความผิดพลาดต้องไม่มีรายละเอียด SQL หลุดออกมา',
        stripos($incomplete['raw'], 'SQLSTATE') === false && stripos($incomplete['raw'], 'liters') !== false,
        $incomplete['raw']
    );

    echo "\n=== คำนวณสถิติ ===\n";
    $config    = Db::config()['stats'];
    $intervals = IntervalStats::fetchIntervals($pdo);
    $summaries = IntervalStats::summarize(
        $intervals,
        (int) $config['min_samples'],
        (int) $config['min_vehicles']
    );
    IntervalStats::store($pdo, $summaries);

    $stat = $pdo->query(
        'SELECT * FROM model_interval_stats WHERE model_id = ' . $pdo->quote(SMOKE_MODEL_ID)
    )->fetch();

    check('มีสถิติของรุ่นทดสอบออกมา', $stat !== false, 'ไม่มีแถวเลย');
    if ($stat !== false) {
        check(
            'นับช่วงได้ 9 ช่วง จาก 3 คัน',
            (int) $stat['sample_count'] === 9 && (int) $stat['vehicle_count'] === 3,
            "sample={$stat['sample_count']} vehicle={$stat['vehicle_count']}"
        );
        check(
            'รวมชื่อรายการที่เว้นวรรคต่างกันเป็นกลุ่มเดียว',
            (int) $pdo->query(
                'SELECT COUNT(*) FROM model_interval_stats WHERE model_id = ' . $pdo->quote(SMOKE_MODEL_ID)
            )->fetchColumn() === 1
        );
        check(
            'มัธยฐานอยู่ที่ 10,000 กม.',
            abs((float) $stat['median_km'] - 10000) < 1,
            "ได้ {$stat['median_km']}"
        );
        check(
            'ช่วง p25–p75 คือ 9,000–12,000',
            abs((float) $stat['p25_km'] - 9000) < 1 && abs((float) $stat['p75_km'] - 12000) < 1,
            "ได้ {$stat['p25_km']}–{$stat['p75_km']}"
        );
        check('หมวดมาจากรายการบำรุงรักษา', $stat['category'] === 'เครื่องยนต์', "ได้ {$stat['category']}");
    }

    echo "\n=== API สถิติ ===\n";
    $stats = request('GET', '/api/stats/model?model_id=' . SMOKE_MODEL_ID, null, $first['token']);
    $engine = $stats['body']['categories']['เครื่องยนต์'][0] ?? null;
    check(
        'ดึงสถิติผ่าน API ได้',
        $stats['status'] === 200 && $engine !== null,
        "status {$stats['status']} {$stats['raw']}"
    );
    if ($engine !== null) {
        check('ค่าที่ API ส่งออกตรงกับในตาราง', abs($engine['median_km'] - 10000) < 1, "ได้ {$engine['median_km']}");
        check(
            'API สถิติไม่มีข้อมูลส่วนตัวติดออกไป',
            !array_intersect(array_keys($engine), ['user_id', 'vehicle_id', 'plate', 'cost', 'workshop']),
            'คีย์ที่ได้: ' . implode(', ', array_keys($engine))
        );
    }

    $noAuth = request('GET', '/api/stats/model?model_id=' . SMOKE_MODEL_ID);
    check('API สถิติต้องล็อกอินก่อน', $noAuth['status'] === 401, "ได้ {$noAuth['status']}");

    echo "\n=== แคตตาล็อก ===\n";
    $catalog = request('GET', '/api/catalog?since=0', null, $first['token']);
    $makeCount = count($catalog['body']['makes'] ?? []);
    check('ดึงแคตตาล็อกได้', $catalog['status'] === 200 && $makeCount > 30, "ได้ {$makeCount} ยี่ห้อ");

    echo "\n=== ฟีดแบ็ค ===\n";
    $mark = ' ' . SMOKE_FEEDBACK_MARK;

    $anonFeedback = request('POST', '/api/feedback', ['kind' => 'bug', 'message' => 'ไม่มีโทเคน' . $mark]);
    check('ส่งฟีดแบ็คต้องล็อกอินก่อน', $anonFeedback['status'] === 401, "ได้ {$anonFeedback['status']}");

    // สามกรณีนี้ต้องไม่เกิดแถวในฐานข้อมูล จึงไม่ถูกนับเข้าโควตาต่อชั่วโมงข้างล่าง
    $tooShort = request('POST', '/api/feedback', ['kind' => 'bug', 'message' => 'สั้น'], $first['token']);
    check('ข้อความสั้นเกินไป ต้องได้ 400', $tooShort['status'] === 400, "ได้ {$tooShort['status']} {$tooShort['raw']}");

    $badKind = request('POST', '/api/feedback', [
        'kind'    => 'ชนิดที่ไม่มีอยู่',
        'message' => 'ชนิดมั่ว' . $mark,
    ], $first['token']);
    check('ชนิดที่ไม่รู้จัก ต้องได้ 400', $badKind['status'] === 400, "ได้ {$badKind['status']} {$badKind['raw']}");

    $badRating = request('POST', '/api/feedback', [
        'kind'    => 'bug',
        'message' => 'คะแนนเกินช่วง' . $mark,
        'rating'  => 9,
    ], $first['token']);
    check('คะแนนนอกช่วง 1–5 ต้องได้ 400', $badRating['status'] === 400, "ได้ {$badRating['status']} {$badRating['raw']}");

    $feedbackBody = [
        'kind'        => 'bug',
        'message'     => 'กราฟค่าน้ำมันหายหลังลบรายการ' . $mark,
        'rating'      => 4,
        'contact'     => 'smoketest@example.invalid',
        'app_version' => '1.1.0+5',
        'platform'    => 'android',
        'device'      => 'Android 14',
        // ไคลเอนต์แอบส่ง source มาเองต้องไม่มีผล เซิร์ฟเวอร์กำหนดเป็น app เสมอ
        'source'      => 'web',
    ];
    $sent = request('POST', '/api/feedback', $feedbackBody, $first['token']);
    $feedbackId = (int) ($sent['body']['id'] ?? 0);
    check(
        'ส่งฟีดแบ็คจากแอพได้',
        $sent['status'] === 200 && $feedbackId > 0,
        "status {$sent['status']} {$sent['raw']}"
    );

    $row = $pdo->query('SELECT * FROM feedback WHERE id = ' . $feedbackId)->fetch();
    check(
        'เก็บครบทุกช่องและผูกกับผู้ใช้ที่ส่ง',
        $row !== false
            && (int) $row['user_id'] === $first['user_id']
            && $row['kind'] === 'bug'
            && (int) $row['rating'] === 4
            && $row['app_version'] === '1.1.0+5'
            && $row['status'] === 'new',
        $row === false ? 'ไม่มีแถว' : json_encode($row, JSON_UNESCAPED_UNICODE)
    );
    check(
        "source ต้องเป็น 'app' ตามช่องทางจริง ไม่ใช่ค่าที่ไคลเอนต์ส่งมา",
        ($row['source'] ?? '') === 'app',
        'ได้ ' . ($row['source'] ?? '-')
    );

    $again = request('POST', '/api/feedback', $feedbackBody, $first['token']);
    check(
        'กดส่งซ้ำข้อความเดิม ต้องได้แถวเดิม ไม่ใช่แถวใหม่',
        (int) ($again['body']['id'] ?? 0) === $feedbackId && ($again['body']['duplicate'] ?? false) === true,
        $again['raw']
    );
    $sameMessage = (int) $pdo->query(
        'SELECT COUNT(*) FROM feedback WHERE message = ' . $pdo->quote($feedbackBody['message'])
    )->fetchColumn();
    check('ข้อความเดิมต้องมีแถวเดียวในฐานข้อมูล', $sameMessage === 1, "มี {$sameMessage} แถว");

    // ส่งต่อจนครบโควตาต่อชั่วโมง (10 ครั้ง) โดยใช้ข้อความต่างกันทุกครั้ง
    // ไม่งั้นจะไปโดนกติกากันส่งซ้ำก่อนถึงเพดาน
    for ($i = 2; $i <= 10; $i++) {
        request('POST', '/api/feedback', [
            'kind'    => 'idea',
            'message' => "ข้อเสนอแนะข้อที่ {$i}{$mark}",
        ], $first['token']);
    }
    $limited = request('POST', '/api/feedback', [
        'kind'    => 'idea',
        'message' => 'ข้อเสนอแนะข้อที่เกินโควตา' . $mark,
    ], $first['token']);
    check(
        'เกินโควตาต่อชั่วโมง ต้องได้ 429 ไม่ใช่ 400',
        $limited['status'] === 429,
        "ได้ {$limited['status']} {$limited['raw']}"
    );
    check(
        'ข้อความตอนโดนจำกัด ต้องบอกให้รอแล้วลองใหม่',
        mb_strpos((string) ($limited['body']['error'] ?? ''), 'ถี่เกินไป') !== false,
        $limited['raw']
    );

    // คนอื่นต้องไม่ติดโควตาไปด้วย — เพดานนับต่อคน ไม่ใช่ต่อเซิร์ฟเวอร์
    $otherPerson = request('POST', '/api/feedback', [
        'kind'    => 'other',
        'message' => 'คนที่สองส่งได้ปกติ' . $mark,
    ], $sessions[1]['token']);
    check('โควตาแยกตามผู้ใช้', $otherPerson['status'] === 200, "ได้ {$otherPerson['status']} {$otherPerson['raw']}");

    echo "\n=== หน้าเว็บ ===\n";
    $page = request('GET', '/model.php?id=' . SMOKE_MODEL_ID);
    check('ยังไม่ล็อกอิน ต้องถูกพาไปหน้าเข้าสู่ระบบ', in_array($page['status'], [302, 303], true), "ได้ {$page['status']}");

    // "/" ต้องไปถึงแดชบอร์ดโดยไม่ต้องพึ่ง DirectoryIndex ที่ตั้งเพิ่ม (index.php require มันไว้)
    // ถ้าข้อนี้ตกแต่ /dashboard.php ผ่าน แปลว่าเว็บเซิร์ฟเวอร์ไม่ได้หา index.php ให้
    $home = request('GET', '/');
    check(
        'หน้าแรก "/" ต้องถึงแดชบอร์ดแล้วเด้งไปล็อกอิน',
        in_array($home['status'], [302, 303], true),
        "ได้ {$home['status']}"
    );

    foreach (['/dashboard.php', '/models.php'] as $path) {
        $guarded = request('GET', $path);
        check(
            "{$path} ยังไม่ล็อกอิน ต้องถูกพาไปหน้าเข้าสู่ระบบ",
            in_array($guarded['status'], [302, 303], true),
            "ได้ {$guarded['status']}"
        );
    }

    // ตอนที่ "/" ยังเป็นหน้ารายการรุ่นรถ ลิงก์ที่ถูกแชร์ไว้มีคำค้น/เลขหน้าติดมาด้วย
    $legacy = redirectTarget('/?q=Smoke&page=2');
    check(
        'ลิงก์เก่า "/?q=" ต้องถูกส่งต่อไป models.php พร้อมคำค้นและเลขหน้า',
        str_contains($legacy, '/models.php')
            && str_contains($legacy, 'q=Smoke')
            && str_contains($legacy, 'page=2'),
        "Location: {$legacy}"
    );

    $feedbackPage = request('GET', '/feedback.php');
    check(
        'หน้าฟีดแบ็คยังไม่ล็อกอิน ต้องถูกพาไปหน้าเข้าสู่ระบบ',
        in_array($feedbackPage['status'], [302, 303], true),
        "ได้ {$feedbackPage['status']}"
    );

    // ฟอร์มบนเว็บใช้คุกกี้ยืนยันตัวตน จึงต้องมีโทเคน CSRF คุม — ยิง POST เปล่า ๆ
    // เข้ามาแล้วต้องไม่เกิดแถวใหม่ (ที่นี่ยังไม่ได้ล็อกอินด้วย จึงต้องเด้งไปล็อกอินก่อน)
    $csrfless = request('POST', '/feedback.php', ['message' => 'ยิงตรงเข้าฟอร์ม' . $mark]);
    check(
        'POST เข้าฟอร์มเว็บโดยไม่มีเซสชัน ต้องไม่ถูกบันทึก',
        in_array($csrfless['status'], [302, 303], true)
            && (int) $pdo->query(
                'SELECT COUNT(*) FROM feedback WHERE message LIKE ' . $pdo->quote('%ยิงตรงเข้าฟอร์ม%')
            )->fetchColumn() === 0,
        "ได้ {$csrfless['status']}"
    );

    $configLeak = request('GET', '/config.php');
    check('config.php ต้องเปิดผ่านเว็บไม่ได้', $configLeak['status'] === 404, "ได้ {$configLeak['status']}");
} finally {
    echo "\n";
    cleanup($pdo);
}

echo "\nตรวจทั้งหมด {$checks} ข้อ ตก {$failures} ข้อ\n";
exit($failures === 0 ? 0 : 1);
