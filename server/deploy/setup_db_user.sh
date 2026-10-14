#!/usr/bin/env bash
#
# สร้างบัญชีฐานข้อมูลของ carcare แบบสิทธิ์น้อยที่สุด แล้วเติมรหัสผ่านลง config.php ให้
#
# รันบนเซิร์ฟเวอร์ครั้งเดียว:
#   sudo bash /var/www/carcare/deploy/setup_db_user.sh
#
# ทำอะไรบ้าง
#   1. สุ่มรหัสผ่านใหม่ (24 ตัวอักษร ไม่มีอักขระที่ต้อง escape ในเชลล์/PHP)
#   2. สร้าง carcare@localhost และ carcare@127.0.0.1 ให้สิทธิ์เฉพาะ SELECT/INSERT/UPDATE/DELETE
#      บนฐาน carcare เท่านั้น — แอพไม่เคยต้อง CREATE/DROP/ALTER ตอนทำงานปกติ
#      (schema ลงด้วย root ไปแล้ว) และไม่ต้องแตะฐานของโปรเจกต์อื่นเลย
#   3. ลบ carcare@% ทิ้ง — host % แปลว่าต่อจากที่ไหนก็ได้ ซึ่งอันตรายเพราะพอร์ต 3306
#      ของเครื่องนี้เปิดรับจากอินเทอร์เน็ต และบัญชีเดิมมีสิทธิ์ระดับ *.* รวมถึง FILE
#      (FILE = อ่าน/เขียนไฟล์บนเครื่องผ่าน SQL ได้ ไม่ควรมีติดตัวแอพเว็บ)
#   4. เขียนรหัสผ่านลง db.password ใน config.php ให้ แล้วทดสอบต่อฐานข้อมูลจริง
#
# ไม่แตะ google_client_ids — ส่วนนั้นต้องเอา client id จาก Google Cloud Console มาใส่เอง

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${APP_DIR}/config.php"

if [ "$(id -u)" -ne 0 ]; then
    echo "ต้องรันด้วย sudo (ต้องเข้า mysql ผ่าน root socket)" >&2
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "ไม่พบ ${CONFIG} — คัดลอกจาก config.example.php ก่อน" >&2
    exit 1
fi

# ตัด / + = ออกเพื่อไม่ให้ไปชนกับ delimiter ของ sed และ quote ของ PHP ทีหลัง
PW="$(openssl rand -base64 48 | tr -d '/+=' | cut -c1-24)"

mysql <<SQL
CREATE USER IF NOT EXISTS 'carcare'@'localhost' IDENTIFIED BY '${PW}';
CREATE USER IF NOT EXISTS 'carcare'@'127.0.0.1' IDENTIFIED BY '${PW}';
ALTER USER 'carcare'@'localhost' IDENTIFIED BY '${PW}';
ALTER USER 'carcare'@'127.0.0.1' IDENTIFIED BY '${PW}';
GRANT SELECT, INSERT, UPDATE, DELETE ON carcare.* TO 'carcare'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON carcare.* TO 'carcare'@'127.0.0.1';
DROP USER IF EXISTS 'carcare'@'%';
FLUSH PRIVILEGES;
SQL

echo "สร้างบัญชีแล้ว:"
mysql -N -e "SELECT CONCAT(user,'@',host) FROM mysql.user WHERE user='carcare'"

# แทนที่เฉพาะบรรทัด password ที่ยังว่างอยู่ ถ้ามีค่าอยู่แล้วจะไม่เขียนทับ
# เพื่อไม่ให้รันซ้ำแล้วรหัสใน config เพี้ยนไปจากที่ตั้งไว้ใน MySQL
if grep -q "'password' *=> *''" "$CONFIG"; then
    sed -i "s|'password' *=> *''|'password' => '${PW}'|" "$CONFIG"
    echo "เขียนรหัสผ่านลง config.php แล้ว"
else
    echo
    echo "config.php มีรหัสผ่านอยู่แล้ว ไม่เขียนทับ — ใส่ค่านี้เองถ้าต้องการ:"
    echo "  ${PW}"
fi

# config.php มีรหัสผ่าน จึงไม่ควรให้ผู้ใช้อื่นบนเครื่องอ่านได้
# www-data ต้องอ่านได้เพราะ PHP ทำงานในสิทธิ์นั้น
chown ubuntu:www-data "$CONFIG"
chmod 640 "$CONFIG"

echo
echo "ทดสอบต่อฐานข้อมูลด้วย config จริง:"
php -r '
$c = require "'"${CONFIG}"'";
$db = $c["db"];
$pdo = new PDO(
    sprintf("mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4", $db["host"], $db["port"], $db["name"]),
    $db["user"], $db["password"],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);
$n = $pdo->query("SELECT COUNT(*) FROM car_models")->fetchColumn();
echo "  ต่อได้ — มีรุ่นรถในแคตตาล็อก {$n} รุ่น\n";
'
