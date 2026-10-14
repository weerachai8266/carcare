<?php

declare(strict_types=1);

/**
 * เข้าสู่ระบบด้วยบัญชี Google
 *
 * ใช้ Google Identity Services แบบ POST กลับมาที่หน้านี้เอง
 * (ปุ่มของ Google จะส่ง credential + g_csrf_token มาให้)
 */

require_once __DIR__ . '/lib/asset.php';
require_once dirname(__DIR__) . '/src/bootstrap.php';

use CarCare\Auth;
use CarCare\Db;

$error = null;

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    try {
        // Google ส่ง g_csrf_token มาทั้งในคุกกี้และในฟอร์ม ถ้าไม่ตรงกันแปลว่า
        // คำขอนี้ไม่ได้มาจากหน้าเว็บของเรา (double-submit cookie)
        $cookieToken = $_COOKIE['g_csrf_token'] ?? '';
        $bodyToken   = $_POST['g_csrf_token'] ?? '';
        if ($cookieToken === '' || !hash_equals($cookieToken, $bodyToken)) {
            throw new RuntimeException('การยืนยันคำขอไม่ผ่าน กรุณาลองใหม่');
        }

        $claims = Auth::verifyGoogleIdToken((string) ($_POST['credential'] ?? ''));
        $user   = Auth::upsertUser($claims);
        $issued = Auth::issueToken((int) $user['id'], 'web');

        setcookie('carcare_session', $issued['token'], [
            'expires'  => (int) ($issued['expires_at'] / 1000),
            'path'     => session_cookie_path(),
            'secure'   => is_https(),
            'httponly' => true,
            'samesite' => 'Lax',
        ]);

        header('Location: ' . url('/'));
        exit;
    } catch (PDOException $e) {
        // ข้อความของ PDO มีชื่อตาราง/คอลัมน์ติดมาด้วย ไม่ควรขึ้นบนหน้าเว็บ
        error_log('[carcare] sql: ' . $e->getMessage());
        $error = 'ระบบขัดข้อง กรุณาลองใหม่อีกครั้ง';
    } catch (Throwable $e) {
        $error = $e->getMessage();
    }
}

$clientId = Db::config()['google_client_ids'][0] ?? '';
$title = 'เข้าสู่ระบบ';
$currentUser = null;
require __DIR__ . '/partials/header.php';
?>

<div class="login-box">
    <h1>เข้าสู่ระบบ</h1>
    <p>ใช้บัญชี Google เดียวกับที่ล็อกอินในแอพ เพื่อดูสถิติของสมาชิก</p>

    <?php if ($error !== null): ?>
        <p class="error"><?= e($error) ?></p>
    <?php endif; ?>

    <!-- สคริปต์ของ Google เป็น CDN ภายนอก จึงไม่ใส่ ?v= ต่อท้าย -->
    <script src="https://accounts.google.com/gsi/client" async defer></script>
    <div id="g_id_onload"
         data-client_id="<?= e($clientId) ?>"
         data-login_uri="<?= e(absolute_url('/login.php')) ?>"
         data-auto_prompt="false"></div>
    <div class="g_id_signin"
         data-type="standard"
         data-size="large"
         data-theme="outline"
         data-text="signin_with"
         data-locale="th"
         data-shape="rectangular"></div>
</div>

<?php require __DIR__ . '/partials/footer.php'; ?>
