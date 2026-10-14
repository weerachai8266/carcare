<?php

declare(strict_types=1);

/**
 * พาธนำหน้าที่แอพถูกติดตั้งไว้ เช่น `/carcare` หรือสตริงว่างถ้าอยู่ที่รากโดเมน
 *
 * อ่านจากตัวแปรที่ตั้งไว้ใน Apache (`SetEnv CARCARE_BASE /carcare`) แทนการเดาจาก
 * SCRIPT_NAME เพราะเมื่อใช้ Alias ร่วมกับ rewrite ค่า SCRIPT_NAME จะเปลี่ยนไปตาม
 * เส้นทางที่เข้ามา ทำให้ลิงก์เพี้ยนเป็นบางหน้า ซึ่งเป็นบั๊กที่ตามยาก
 */
function base_path(): string
{
    $base = $_SERVER['CARCARE_BASE'] ?? getenv('CARCARE_BASE') ?: '';

    return rtrim((string) $base, '/');
}

/** URL ภายในแอพ ใช้แทนการเขียน "/login.php" ตรง ๆ ซึ่งจะพังเมื่อติดตั้งใต้ path ย่อย */
function url(string $path): string
{
    return base_path() . '/' . ltrim($path, '/');
}

/**
 * URL เต็มรูปแบบพร้อม scheme และโฮสต์
 *
 * ใช้กับที่ที่พาธสัมพัทธ์ไม่พอ — โดยเฉพาะ `login_uri` ของปุ่ม Google ซึ่งถูกนำไป
 * เทียบกับ Authorized redirect URI ใน Google Cloud Console แบบตรงตัวอักษร
 * ใส่เป็น "/carcare/login.php" แล้วจะไม่ตรงกับ "https://โดเมน/carcare/login.php"
 * ที่ลงทะเบียนไว้ ทำให้ล็อกอินไม่ผ่าน
 */
function absolute_url(string $path): string
{
    $scheme = is_https() ? 'https' : 'http';
    $host   = $_SERVER['HTTP_HOST'] ?? 'localhost';

    return $scheme . '://' . $host . url($path);
}

/**
 * คืน URL ของไฟล์ static พร้อมเลขเวอร์ชันจากเวลาแก้ไขไฟล์
 *
 * ใช้กับไฟล์ในเครื่องเท่านั้น (CSS/JS ของเรา) ห้ามใช้กับ CDN เพราะ filemtime()
 * หา path ในดิสก์ไม่เจอ
 *
 * หาไฟล์จากโฟลเดอร์ public ของแอพเอง ไม่ใช่จาก DOCUMENT_ROOT เพราะเมื่อติดตั้ง
 * ด้วย Alias ค่า DOCUMENT_ROOT ยังชี้ไปที่เว็บรูทของโฮสต์ ซึ่งคนละที่กับแอพนี้
 */
function asset(string $path): string
{
    $path = '/' . ltrim($path, '/');
    $file = dirname(__DIR__) . $path;
    // ไฟล์หายหรือถูกเปลี่ยนชื่อ ให้ตกไปใช้เวลาปัจจุบัน (ได้ของใหม่เสมอ)
    // ดีกว่าปล่อยให้ warning ของ filemtime() ไปโผล่กลาง <head>
    $version = is_file($file) ? filemtime($file) : time();

    return htmlspecialchars(base_path() . $path . '?v=' . $version, ENT_QUOTES);
}

/** ตัวย่อของ htmlspecialchars ให้เทมเพลตอ่านง่ายขึ้น */
function e(?string $value): string
{
    return htmlspecialchars($value ?? '', ENT_QUOTES, 'UTF-8');
}

/** สร้าง URL ของหน้า $n โดยรักษา query param เดิม (ค้นหา/ตัวกรอง) ไว้ครบ */
function page_url(int $n): string
{
    $params = array_merge($_GET, ['page' => $n]);

    return htmlspecialchars('?' . http_build_query($params), ENT_QUOTES);
}

/**
 * พาธของคุกกี้เซสชัน
 *
 * ต้องผูกกับ base path ไม่ใช่ "/" เพราะเซิร์ฟเวอร์นี้มีเว็บอื่นอยู่ด้วย
 * ถ้าตั้งเป็น "/" เบราว์เซอร์จะแนบโทเคนของเราไปกับทุกคำขอของเว็บอื่นบนโดเมนเดียวกัน
 */
function session_cookie_path(): string
{
    return base_path() === '' ? '/' : base_path() . '/';
}

/**
 * ผู้ใช้เข้ามาด้วย https หรือไม่ ใช้ตัดสินว่าจะติดธง Secure ให้คุกกี้เซสชัน
 *
 * เมื่ออยู่หลัง reverse proxy อย่าง Cloudflare ตัว TLS จบที่ proxy แล้วต่อมาที่เรา
 * ด้วย http ธรรมดา `$_SERVER['HTTPS']` จึงว่างทั้งที่เบราว์เซอร์ใช้ https อยู่
 * ถ้าเชื่อค่านั้นตรง ๆ คุกกี้จะไม่ได้ธง Secure ทั้งที่ควรได้
 *
 * เชื่อ X-Forwarded-Proto ได้เฉพาะเมื่อคำขอมาจาก proxy จริง — ในที่นี้คือเมื่อ
 * ตั้ง CARCARE_TRUST_PROXY ไว้ ไม่งั้นใครก็ปลอม header นี้มาเองได้
 */
function is_https(): bool
{
    if (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') {
        return true;
    }

    $trustProxy = $_SERVER['CARCARE_TRUST_PROXY'] ?? getenv('CARCARE_TRUST_PROXY') ?: '';
    if ($trustProxy === '') {
        return false;
    }

    return strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
}

/** จำนวนแถวต่อหน้าของทุกหน้าลิสต์ในระบบ */
const PER_PAGE = 50;
