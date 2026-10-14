-- โครงฐานข้อมูลฝั่งเซิร์ฟเวอร์ (MySQL 8.0 ขึ้นไป — ใช้ window function ตอนคำนวณสถิติ)
--
-- หลักการ:
-- * id ของทุกตารางข้อมูลผู้ใช้เป็น UUID ที่สร้างจากเครื่องลูก จึงไม่ต้อง map id
-- * updated_at เป็น epoch millisecond ของ "เวลาที่แก้ในเครื่องลูก" ใช้ตัดสิน last-write-wins
-- * synced_at เป็นเวลาของเซิร์ฟเวอร์ตอนเขียนแถวนั้น ใช้เป็นเคอร์เซอร์ตอนดึงข้อมูลลง
--   (ห้ามใช้ updated_at เป็นเคอร์เซอร์ เพราะนาฬิกาเครื่องลูกเดินไม่ตรงกัน
--    เครื่องที่นาฬิกาช้าจะทำให้แถวใหม่ถูกข้ามไปตลอด)
-- * deleted เป็น soft delete เพื่อให้การลบกระจายไปทุกเครื่องได้

CREATE DATABASE IF NOT EXISTS carcare
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE carcare;

CREATE TABLE users (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  google_sub  VARCHAR(64)  NOT NULL,
  email       VARCHAR(255) NOT NULL,
  name        VARCHAR(255) NULL,
  picture_url VARCHAR(512) NULL,
  created_at  BIGINT       NOT NULL,
  updated_at  BIGINT       NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_sub (google_sub),
  KEY idx_users_email (email)
) ENGINE = InnoDB;

-- โทเคนเซสชันของแอพเอง ออกให้หลังตรวจ Google ID token ผ่านแล้ว
-- เก็บเป็น hash ไม่ใช่ตัวโทเคนตรง ๆ เพื่อให้ฐานข้อมูลรั่วแล้วสวมสิทธิ์ไม่ได้ทันที
CREATE TABLE sessions (
  token_hash   CHAR(64)        NOT NULL,
  user_id      BIGINT UNSIGNED NOT NULL,
  device_name  VARCHAR(128)    NULL,
  created_at   BIGINT          NOT NULL,
  expires_at   BIGINT          NOT NULL,
  last_seen_at BIGINT          NOT NULL,
  PRIMARY KEY (token_hash),
  KEY idx_sessions_user (user_id),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------- แคตตาล็อกยี่ห้อ/รุ่นรถ (ใช้ร่วมกันทุกคน) ----------

CREATE TABLE car_makes (
  id         VARCHAR(64)  NOT NULL,
  name       VARCHAR(128) NOT NULL,
  name_th    VARCHAR(128) NULL,
  sort_order INT          NOT NULL DEFAULT 0,
  is_custom  TINYINT(1)   NOT NULL DEFAULT 0,
  -- แถวที่ผู้ใช้เพิ่มเองต้องผ่านการอนุมัติก่อนถึงจะกระจายให้คนอื่น
  -- ป้องกันชื่อมั่ว/ชื่อซ้ำสะกดต่างกันไปปนแคตตาล็อกกลาง
  approved   TINYINT(1)   NOT NULL DEFAULT 0,
  created_by BIGINT UNSIGNED NULL,
  created_at BIGINT       NOT NULL,
  updated_at BIGINT       NOT NULL,
  synced_at  BIGINT       NOT NULL,
  deleted    TINYINT(1)   NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_makes_sync (synced_at),
  KEY idx_makes_name (name)
) ENGINE = InnoDB;

CREATE TABLE car_models (
  id         VARCHAR(64)  NOT NULL,
  make_id    VARCHAR(64)  NOT NULL,
  name       VARCHAR(128) NOT NULL,
  body_type  VARCHAR(32)  NULL,
  sort_order INT          NOT NULL DEFAULT 0,
  is_custom  TINYINT(1)   NOT NULL DEFAULT 0,
  approved   TINYINT(1)   NOT NULL DEFAULT 0,
  created_by BIGINT UNSIGNED NULL,
  created_at BIGINT       NOT NULL,
  updated_at BIGINT       NOT NULL,
  synced_at  BIGINT       NOT NULL,
  deleted    TINYINT(1)   NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_models_make (make_id, sort_order),
  KEY idx_models_sync (synced_at),
  CONSTRAINT fk_models_make FOREIGN KEY (make_id) REFERENCES car_makes (id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------- ข้อมูลของผู้ใช้ ----------

CREATE TABLE vehicles (
  id            CHAR(36)        NOT NULL,
  user_id       BIGINT UNSIGNED NOT NULL,
  name          VARCHAR(128)    NOT NULL,
  make          VARCHAR(128)    NULL,
  model         VARCHAR(128)    NULL,
  make_id       VARCHAR(64)     NULL,
  model_id      VARCHAR(64)     NULL,
  year          INT             NULL,
  plate         VARCHAR(32)     NULL,
  fuel_type     VARCHAR(64)     NULL,
  tank_capacity DECIMAL(6, 2)   NULL,
  initial_odo   DECIMAL(10, 1)  NOT NULL DEFAULT 0,
  is_active     TINYINT(1)      NOT NULL DEFAULT 1,
  sort_order    INT             NOT NULL DEFAULT 0,
  created_at    BIGINT          NOT NULL,
  updated_at    BIGINT          NOT NULL,
  synced_at     BIGINT          NOT NULL,
  deleted       TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_vehicles_user_sync (user_id, synced_at),
  KEY idx_vehicles_model (model_id),
  CONSTRAINT fk_vehicles_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE fuel_entries (
  id              CHAR(36)        NOT NULL,
  user_id         BIGINT UNSIGNED NOT NULL,
  vehicle_id      CHAR(36)        NOT NULL,
  date            BIGINT          NOT NULL,
  odometer        DECIMAL(10, 1)  NOT NULL,
  liters          DECIMAL(7, 2)   NOT NULL,
  price_per_liter DECIMAL(7, 2)   NULL,
  total_cost      DECIMAL(10, 2)  NULL,
  is_full_tank    TINYINT(1)      NOT NULL DEFAULT 1,
  missed_entries  TINYINT(1)      NOT NULL DEFAULT 0,
  fuel_type       VARCHAR(64)     NULL,
  station         VARCHAR(128)    NULL,
  note            TEXT            NULL,
  created_at      BIGINT          NOT NULL,
  updated_at      BIGINT          NOT NULL,
  synced_at       BIGINT          NOT NULL,
  deleted         TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_fuel_user_sync (user_id, synced_at),
  KEY idx_fuel_vehicle (vehicle_id, odometer),
  CONSTRAINT fk_fuel_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE maintenance_tasks (
  id                 CHAR(36)        NOT NULL,
  user_id            BIGINT UNSIGNED NOT NULL,
  vehicle_id         CHAR(36)        NOT NULL,
  name               VARCHAR(191)    NOT NULL,
  category           VARCHAR(64)     NULL,
  interval_km        DECIMAL(10, 1)  NULL,
  interval_months    INT             NULL,
  notify_km_before   DECIMAL(10, 1)  NOT NULL DEFAULT 500,
  notify_days_before INT             NOT NULL DEFAULT 7,
  is_active          TINYINT(1)      NOT NULL DEFAULT 1,
  sort_order         INT             NOT NULL DEFAULT 0,
  created_at         BIGINT          NOT NULL,
  updated_at         BIGINT          NOT NULL,
  synced_at          BIGINT          NOT NULL,
  deleted            TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_tasks_user_sync (user_id, synced_at),
  KEY idx_tasks_vehicle (vehicle_id),
  CONSTRAINT fk_tasks_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB;

CREATE TABLE service_records (
  id         CHAR(36)        NOT NULL,
  user_id    BIGINT UNSIGNED NOT NULL,
  vehicle_id CHAR(36)        NOT NULL,
  task_id    CHAR(36)        NULL,
  title      VARCHAR(191)    NOT NULL,
  date       BIGINT          NOT NULL,
  odometer   DECIMAL(10, 1)  NOT NULL,
  cost       DECIMAL(10, 2)  NULL,
  workshop   VARCHAR(191)    NULL,
  note       TEXT            NULL,
  created_at BIGINT          NOT NULL,
  updated_at BIGINT          NOT NULL,
  synced_at  BIGINT          NOT NULL,
  deleted    TINYINT(1)      NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_service_user_sync (user_id, synced_at),
  -- คิวรีสถิติไล่ตามคู่ (vehicle_id, task_id) เรียงตามเลขไมล์ ดัชนีนี้จึงตรงรูปงาน
  KEY idx_service_stats (vehicle_id, task_id, odometer),
  CONSTRAINT fk_service_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE = InnoDB;

-- ---------- ตารางแคชสถิติ ----------
--
-- คำนวณสถิติสดทุกครั้งจะช้าเมื่อข้อมูลโต จึงให้ cron สรุปไว้ล่วงหน้า
-- (ดู bin/rebuild_stats.php) แล้วหน้าเว็บ/API อ่านจากตารางนี้อย่างเดียว
CREATE TABLE model_interval_stats (
  model_id      VARCHAR(64)  NOT NULL,
  task_key      VARCHAR(191) NOT NULL,
  task_name     VARCHAR(191) NOT NULL,
  category      VARCHAR(64)  NOT NULL,
  sample_count  INT          NOT NULL,
  vehicle_count INT          NOT NULL,
  median_km     DECIMAL(10, 1) NOT NULL,
  p25_km        DECIMAL(10, 1) NOT NULL,
  p75_km        DECIMAL(10, 1) NOT NULL,
  median_days   INT          NOT NULL,
  computed_at   BIGINT       NOT NULL,
  PRIMARY KEY (model_id, task_key),
  KEY idx_stats_category (model_id, category, vehicle_count DESC)
) ENGINE = InnoDB;

-- ---------- ฟีดแบ็คจากผู้ใช้ ----------
--
-- ไม่ได้อยู่ในระบบซิงก์ — เป็นข้อความที่ส่งขึ้นครั้งเดียวแล้วจบ ไม่ต้องกระจาย
-- กลับลงเครื่องลูก จึงไม่มี synced_at/deleted และใช้ id เป็น AUTO_INCREMENT
-- ของเซิร์ฟเวอร์ ไม่ใช่ UUID ที่สร้างจากเครื่องลูกเหมือนตารางข้อมูลผู้ใช้
CREATE TABLE feedback (
  id          BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  -- ON DELETE SET NULL ไม่ใช่ CASCADE เหมือนตารางอื่น เพราะฟีดแบ็คไม่ใช่ข้อมูล
  -- "ของ" ผู้ใช้ แต่เป็นข้อความที่ส่งมาถึงเรา ผู้ใช้ลบบัญชีแล้วบั๊กที่เขารายงานไว้
  -- ต้องยังอยู่ให้แก้ได้ ส่วนที่หายไปคือความเชื่อมโยงกับตัวคน
  user_id     BIGINT UNSIGNED  NULL,
  kind        VARCHAR(16)      NOT NULL,           -- bug | idea | other
  rating      TINYINT UNSIGNED NULL,               -- 1–5 เฉพาะเมื่อผู้ใช้ให้มา
  message     TEXT             NOT NULL,
  contact     VARCHAR(255)     NULL,               -- ช่องทางติดต่อกลับ ถ้าผู้ใช้อยากให้ตอบ
  source      VARCHAR(16)      NOT NULL,           -- app | web (เซิร์ฟเวอร์ตัดสิน ไม่ใช่ไคลเอนต์ส่งมา)
  app_version VARCHAR(32)      NULL,
  platform    VARCHAR(32)      NULL,               -- android | ios | web
  device      VARCHAR(191)     NULL,               -- รุ่น OS หรือ user agent แบบตัดสั้น
  -- ไล่สถานะด้วยมือใน SQL (ระบบนี้ไม่มีหน้าแอดมิน): new → reading → done
  status      VARCHAR(16)      NOT NULL DEFAULT 'new',
  created_at  BIGINT           NOT NULL,
  PRIMARY KEY (id),
  KEY idx_feedback_status (status, created_at),
  -- ใช้ทั้งตอนนับจำนวนที่คนหนึ่งส่งในชั่วโมงล่าสุด (กันสแปม)
  -- และตอนหาข้อความเดิมที่เพิ่งส่งไป (กันกดส่งซ้ำตอนเน็ตช้า)
  KEY idx_feedback_user (user_id, created_at),
  CONSTRAINT fk_feedback_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE = InnoDB;
