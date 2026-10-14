<?php

declare(strict_types=1);

require_once __DIR__ . '/lib/asset.php';
require_once dirname(__DIR__) . '/src/bootstrap.php';

use CarCare\Auth;

Auth::logout();

// ลบคุกกี้ด้วย path เดิมที่ตั้งไว้ตอนล็อกอิน ไม่งั้นเบราว์เซอร์จะไม่ลบให้
setcookie('carcare_session', '', [
    'expires'  => time() - 3600,
    'path'     => session_cookie_path(),
    'secure'   => is_https(),
    'httponly' => true,
    'samesite' => 'Lax',
]);

header('Location: ' . url('/login.php'));
exit;
