-- เพิ่มตาราง feedback ให้ฐานข้อมูลที่ติดตั้งไปแล้ว
--
-- schema.sql เป็น CREATE ล้วน ใช้ได้แค่กับเครื่องที่ลงใหม่ ฐานที่รันอยู่จริง
-- จึงต้องมีไฟล์นี้แยก รันครั้งเดียว:
--
--   mysql -u root -p < sql/migrations/2026_08_17_feedback.sql
--
-- เนื้อหาต้องตรงกับหัวข้อ "ฟีดแบ็คจากผู้ใช้" ใน sql/schema.sql เป๊ะ ๆ
-- (คำอธิบายว่าทำไมแต่ละคอลัมน์เป็นแบบนี้อยู่ในไฟล์นั้น)

USE carcare;

CREATE TABLE IF NOT EXISTS feedback (
  id          BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  user_id     BIGINT UNSIGNED  NULL,
  kind        VARCHAR(16)      NOT NULL,
  rating      TINYINT UNSIGNED NULL,
  message     TEXT             NOT NULL,
  contact     VARCHAR(255)     NULL,
  source      VARCHAR(16)      NOT NULL,
  app_version VARCHAR(32)      NULL,
  platform    VARCHAR(32)      NULL,
  device      VARCHAR(191)     NULL,
  status      VARCHAR(16)      NOT NULL DEFAULT 'new',
  created_at  BIGINT           NOT NULL,
  PRIMARY KEY (id),
  KEY idx_feedback_status (status, created_at),
  KEY idx_feedback_user (user_id, created_at),
  CONSTRAINT fk_feedback_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
) ENGINE = InnoDB;

-- บัญชีของแอพมีแค่ SELECT/INSERT/UPDATE/DELETE บนฐาน carcare อยู่แล้ว
-- (ดู deploy/setup_db_user.sh) ตารางใหม่จึงใช้ได้เลยโดยไม่ต้อง GRANT เพิ่ม
