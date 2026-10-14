# เซิร์ฟเวอร์ carcare

API ซิงก์ข้อมูล + เว็บสรุปสถิติการบำรุงรักษาตามรุ่นรถ

- PHP 8.1 ขึ้นไป (ใช้ `never` return type, `str_starts_with`, enum ไม่ได้ใช้)
- MySQL 8.0 ขึ้นไป — จำเป็นจริง ๆ เพราะสถิติใช้ window function (`LAG`, `ROW_NUMBER`)
- ไม่ต้องใช้ composer — autoloader เขียนเองใน `src/bootstrap.php`

## โครงไฟล์

```
server/
  public/          document root ชี้มาที่นี่
    api/index.php  ตัวจัดเส้นทาง API ทั้งหมด
    index.php      require dashboard.php — มีไว้ให้ URL ราก "/" ไปถึงหน้าแรก
    dashboard.php  หน้าแรก: ภาพรวมทั้งระบบ + สถานะการคำนวณสถิติ
    models.php     รายการรุ่นรถที่มีสถิติ (ค้นหา + แบ่งหน้า)
    model.php      สถิติของรุ่นเดียว แยกตามหมวด
    login.php      เข้าสู่ระบบด้วย Google
    feedback.php   ฟอร์มส่งฟีดแบ็คจากหน้าเว็บ
  src/             คลาสทั้งหมด (เนมสเปซ CarCare)
  sql/             schema + seed แคตตาล็อกรถ
    migrations/    ไฟล์ ALTER/CREATE สำหรับฐานที่ติดตั้งไปแล้ว
  bin/             สคริปต์สำหรับ cron
  config.php       ตั้งค่า (ไม่ commit — คัดลอกจาก config.example.php)
```

## ติดตั้ง

```bash
mysql -u root -p < sql/schema.sql
mysql -u root -p < sql/catalog_seed.sql

cp config.example.php config.php

# สร้างบัญชีฐานข้อมูลแบบสิทธิ์น้อยที่สุด แล้วเติมรหัสผ่านลง config.php ให้
sudo bash deploy/setup_db_user.sh

# เหลือแก้ google_client_ids ใน config.php เอง
```

ฐานข้อมูลที่ติดตั้งไปก่อนหน้านี้แล้วต้องรันไฟล์ใน `sql/migrations/` เพิ่มเอง
(`schema.sql` เป็น CREATE ล้วน ใช้ได้แค่กับเครื่องที่ลงใหม่):

```bash
mysql -u root -p < sql/migrations/2026_08_17_feedback.sql
```

บัญชีฐานข้อมูลของแอพควรมีแค่ `SELECT/INSERT/UPDATE/DELETE` บนฐาน `carcare`
และผูกกับ `localhost` เท่านั้น ตอนทำงานปกติแอพไม่เคย `CREATE`/`ALTER`/`DROP`
(schema ลงด้วย root ไปแล้ว) การให้สิทธิ์ระดับ `*.*` — โดยเฉพาะ `FILE` ซึ่งอ่าน/เขียน
ไฟล์บนเครื่องผ่าน SQL ได้ — เท่ากับเปลี่ยน SQL injection หนึ่งจุดให้กลายเป็นการยึดเครื่อง
และถ้า host เป็น `%` ขณะที่พอร์ต 3306 เปิดออกอินเทอร์เน็ต ก็เท่ากับเดารหัสผ่านจากที่ไหนก็ได้

ชี้ document root ของเว็บเซิร์ฟเวอร์มาที่ `server/public` — **อย่าชี้มาที่ `server/`**
เพราะจะทำให้ `config.php` ที่มีรหัสผ่านฐานข้อมูลเปิดผ่านเว็บได้

ถ้าเครื่องมีเว็บอื่นอยู่แล้วและต้องติดตั้งใต้ path ย่อย ใช้ `deploy/apache-carcare.conf`
ซึ่งตั้ง `Alias /carcare` ให้ชี้เฉพาะ `public/` และส่ง `CARCARE_BASE` ให้แอพรู้ว่าตัวเอง
อยู่ใต้ path ไหน (ใช้ประกอบลิงก์และ path ของคุกกี้)

## ตรวจว่าติดตั้งถูกไหม

```bash
php bin/smoke_test.php http://127.0.0.1/carcare
```

ยิง HTTP จริงเข้าเว็บเซิร์ฟเวอร์ ตรวจตั้งแต่ rewrite ของ `/api` ไปจนถึงสถิติที่คำนวณออกมา
รวมถึงกรณีที่พลาดแล้วเจ็บ: โทเคนผิดต้องไม่ผ่าน ผู้ใช้คนหนึ่งต้องไม่เห็นข้อมูลของอีกคน
แถวที่นาฬิกาเก่ากว่าต้องไม่ทับของใหม่ และการส่ง `id` ของคนอื่นขึ้นมาต้องแย่งข้อมูลไม่ได้

สร้างผู้ใช้ทดสอบกับรุ่นรถสมมุติขึ้นมาเอง แล้วลบทิ้งพร้อมคำนวณตารางสถิติใหม่ทุกครั้งที่จบ
(รวมถึงตอนที่ตรวจไม่ผ่าน) จึงรันซ้ำบนเครื่องจริงได้ ส่วนที่ทดสอบไม่ได้คือการแลก
Google `id_token` เพราะต้องมีโทเคนจริงจาก Google — จุดนั้นต้องลองล็อกอินจากแอพเอง

ตั้ง cron ให้คำนวณสถิติใหม่วันละครั้ง:

```cron
0 3 * * * /usr/bin/php /path/to/server/bin/rebuild_stats.php >> /var/log/carcare-stats.log 2>&1
```

## Google Sign-In

สร้าง OAuth client ใน Google Cloud Console ให้ครบทุกแพลตฟอร์มที่จะล็อกอิน
(web / android / ios) แล้วใส่ client id ทั้งหมดลง `google_client_ids`

แต่ละแพลตฟอร์มออก `id_token` ที่มี `aud` เป็น client id ของตัวเอง
ถ้าใส่ไม่ครบ เครื่องที่ขาดจะล็อกอินไม่ผ่านโดยขึ้นว่า "โทเคนนี้ไม่ได้ออกให้แอพนี้"

สำหรับ Android ต้องลงทะเบียน SHA-1 ของ keystore ที่ใช้เซ็นแอพด้วย
(debug keystore กับ release keystore คนละค่า ต้องใส่ทั้งคู่ถ้าจะทดสอบทั้งสองแบบ)

ฝั่งแอพต้องส่ง **web client id** เข้าไปตอน build ด้วย ไม่ใช่ android client id:

```bash
flutter run \
  --dart-define=CARCARE_API=https://carcare.example.com \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxxxxxx.apps.googleusercontent.com \
  --dart-define=APP_VERSION=1.1.0+5
```

(`APP_VERSION` ไม่บังคับ — ใช้แนบไปกับฟีดแบ็คเพื่อให้รู้ว่าบั๊กมาจากบิลด์ไหน
ตั้งให้ตรงกับ `version` ใน `pubspec.yaml` ตอน build ของจริง)

ถ้าไม่ส่งค่านี้ `GoogleSignIn` บน Android จะคืน `id_token` เป็น null
แล้วล็อกอินจะไม่ผ่านโดยไม่มีข้อความบอกสาเหตุที่ชัดเจน

## หน้าเว็บ

| URL | หน้า |
|---|---|
| `/` (= `/dashboard.php`) | ภาพรวม: ตัวนับรวมทั้งระบบ, รุ่นที่มีข้อมูลมากสุด, รายการที่ทำกันบ่อยสุด, เวลาที่คำนวณสถิติล่าสุด |
| `/models.php` | รายการรุ่นรถที่มีสถิติ — ค้นหาได้ แบ่งหน้าละ 50 |
| `/model.php?id=` | สถิติของรุ่นเดียว แยกตามหมวด |
| `/feedback.php` | ฟอร์มส่งฟีดแบ็ค |
| `/login.php` | เข้าสู่ระบบด้วย Google |

ทุกหน้ายกเว้น `login.php` ต้องล็อกอินก่อน และ**ไม่มีการแยกสิทธิ์แอดมิน** — สมาชิกที่
ล็อกอินแล้วเห็นทุกหน้าเหมือนกันหมด ตัวเลขบนแดชบอร์ดจึงเป็นค่ารวมของทั้งชุมชนเท่านั้น
ห้ามเอาอะไรที่ชี้กลับไปหาสมาชิกคนใดคนหนึ่ง (รวมถึงฟีดแบ็คที่ส่งเข้ามา) ขึ้นหน้าเว็บ
จนกว่าจะมีระบบสิทธิ์จริง

แดชบอร์ดเตือนเองเมื่อ `MAX(computed_at)` ของตารางสถิติเก่ากว่าสองวัน ซึ่งหมายถึง
cron ของ `bin/rebuild_stats.php` ไม่ได้รันมาอย่างน้อยหนึ่งรอบ

## API

ทุกเส้นทางรับ/ส่ง JSON และต้องมี `Authorization: Bearer <token>` ยกเว้น `/auth/google`

| Method | Path | ใช้ทำอะไร |
|---|---|---|
| POST | `/api/auth/google` | แลก Google `id_token` เป็นโทเคนเซสชันของแอพ |
| POST | `/api/auth/logout` | เพิกถอนโทเคนของเครื่องนี้ |
| GET | `/api/me` | ข้อมูลผู้ใช้ที่ล็อกอินอยู่ |
| POST | `/api/sync` | ส่งแถวที่แก้ในเครื่องขึ้น และรับแถวที่เปลี่ยนบนเซิร์ฟเวอร์ลง |
| GET | `/api/catalog?since=` | แคตตาล็อกยี่ห้อ/รุ่นที่เปลี่ยนหลัง `since` |
| GET | `/api/stats/model?model_id=` | สถิติของรุ่นนั้น แยกตามหมวด หมวดละ 10 อันดับ |
| POST | `/api/feedback` | ส่งฟีดแบ็คจากในแอพ |

### `/api/sync`

```jsonc
// request
{
  "since": 1754500000000,          // synced_at ล่าสุดที่เครื่องนี้ได้รับไป
  "changes": {
    "vehicles":          [ /* แถวที่ dirty = 1 */ ],
    "fuel_entries":      [],
    "maintenance_tasks": [],
    "service_records":   []
  },
  "catalog": {                      // ยี่ห้อ/รุ่นที่ผู้ใช้เพิ่มเอง
    "car_makes":  [],
    "car_models": []
  }
}

// response
{
  "server_time": 1754600000000,    // เก็บไว้ใช้เป็น since รอบหน้า
  "pushed": 12,
  "changes": { "vehicles": [ /* ... */ ] },
  "catalog": { "makes": [], "models": [] }
}
```

การชนกันของข้อมูลตัดสินด้วย last-write-wins จาก `updated_at` ของเครื่องที่แก้
ส่วนเคอร์เซอร์ของการดึงลงใช้ `synced_at` ที่เซิร์ฟเวอร์ประทับเอง —
ห้ามใช้ `updated_at` เป็นเคอร์เซอร์ เพราะนาฬิกาของเครื่องลูกเดินไม่ตรงกัน
เครื่องที่นาฬิกาช้าจะทำให้แถวใหม่ถูกข้ามไปถาวร

## ฟีดแบ็คจากผู้ใช้

รับสองทาง ตรรกะการตรวจข้อมูลใช้ `src/Feedback.php` ร่วมกัน:

- **ในแอพ** → `POST /api/feedback` (Bearer token)
- **บนเว็บ** → `feedback.php` ฟอร์มของตัวเอง (คุกกี้ + โทเคน CSRF ที่ผูกกับเซสชัน)

กติกาที่บังคับฝั่งเซิร์ฟเวอร์:

| เรื่อง | ค่า |
|---|---|
| ต้องล็อกอิน | ใช่ ทั้งสองช่องทาง — ฟีดแบ็คไม่มีเจ้าของแล้วถามรายละเอียดต่อไม่ได้ |
| `kind` | `bug` / `idea` / `other` — ค่าอื่นตอบ 400 ไม่ใช่เงียบ ๆ แปลงเป็น `other` |
| `message` | 5–4,000 ตัวอักษร |
| `rating` | 1–5 หรือไม่ส่งมาเลย |
| ส่งถี่ | เกิน 10 ครั้ง/ชั่วโมง/คน → **429** (ไม่ใช่ 400 เพราะข้อมูลไม่ได้ผิด) |
| กดส่งซ้ำ | ข้อความเดิมภายใน 10 นาที คืน `id` เดิมและไม่เกิดแถวใหม่ |

`source` เซิร์ฟเวอร์กำหนดเองจากช่องทางที่คำขอเข้ามา (`app`/`web`) ไม่รับจากไคลเอนต์
ส่วน `app_version` มาจาก `--dart-define=APP_VERSION` ของแอพ ถ้าไม่ได้ตั้งจะได้ค่า `dev`

### อ่านฟีดแบ็ค

ระบบนี้**ไม่มีหน้าแอดมิน** — อ่านจากฐานข้อมูลตรง ๆ

```sql
-- ที่ยังไม่ได้อ่าน ใหม่สุดขึ้นก่อน
SELECT f.id, FROM_UNIXTIME(f.created_at / 1000) AS at, f.kind, f.rating,
       f.source, f.platform, f.app_version,
       COALESCE(u.email, '(ลบบัญชีแล้ว)') AS who, f.contact, f.message
FROM feedback f
LEFT JOIN users u ON u.id = f.user_id
WHERE f.status = 'new'
ORDER BY f.created_at DESC;

-- ไล่สถานะด้วยมือ: new → reading → done
UPDATE feedback SET status = 'done' WHERE id = 123;

-- นับตามชนิด/สัปดาห์ ดูว่าเรื่องไหนถูกบ่นบ่อย
SELECT kind, COUNT(*) AS n, ROUND(AVG(rating), 2) AS avg_rating
FROM feedback
WHERE created_at >= (UNIX_TIMESTAMP() - 7 * 86400) * 1000
GROUP BY kind;
```

`feedback.user_id` เป็น `ON DELETE SET NULL` ไม่ใช่ `CASCADE` เหมือนตารางอื่น —
ผู้ใช้ลบบัญชีแล้วบั๊กที่เขารายงานไว้ยังต้องอยู่ให้แก้ได้ ที่หายไปคือความเชื่อมโยงกับตัวคน

## สถิติทำงานอย่างไร

1. จับคู่ประวัติการบำรุงรักษาสองครั้งที่ติดกัน **ของรถคันเดียวกันและรายการเดียวกัน**
   ด้วย `LAG(...) OVER (PARTITION BY vehicle_id, task_id ORDER BY odometer)`
2. ระยะห่างที่ได้คือ "ระยะที่คนนั้นทำจริง" — ไม่ใช่รอบที่เขาตั้งไว้ในแอพ
3. รวมข้ามสมาชิกด้วยชื่อรายการที่ normalize แล้ว (`task_id` เป็น UUID คนละค่าในแต่ละเครื่อง)
4. สรุปเป็นมัธยฐาน + ช่วง p25–p75 ต่อหนึ่ง (รุ่นรถ, รายการ) เก็บลง `model_interval_stats`

เกณฑ์ขั้นต่ำใน `config.php` (`min_samples`, `min_vehicles`) ทำสองหน้าที่พร้อมกัน:
กันตัวเลขมั่วจากข้อมูลน้อย และกันการเดาย้อนกลับว่าสถิตินี้เป็นของสมาชิกคนไหน

## ข้อมูลส่วนบุคคล

หน้าเว็บและ API สถิติแสดงเฉพาะค่าที่รวมแล้ว ไม่มีทะเบียนรถ ชื่ออู่ ค่าใช้จ่าย
หรือตัวระบุผู้ใช้หลุดออกไป — คิวรีสถิติไม่ได้ `SELECT` คอลัมน์เหล่านั้นเลย
