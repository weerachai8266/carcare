# CarCare

แอพ Flutter สำหรับบันทึกข้อมูลรถส่วนตัว เช่น การเติมน้ำมัน งานบำรุงรักษา เลขไมล์ และสถิติพื้นฐาน พร้อม backend PHP สำหรับซิงก์ข้อมูลและรวบรวมสถิติรุ่นรถแบบไม่เปิดเผยข้อมูลส่วนตัว

## ความสามารถหลัก

- จัดการรถหลายคันในเครื่อง
- บันทึกการเติมน้ำมันและคำนวณอัตราสิ้นเปลือง
- ตั้งรายการบำรุงรักษาตามระยะทางหรือวันที่
- ซิงก์ข้อมูลผ่าน backend ของตัวเองด้วย Google Sign-In
- ส่ง feedback พร้อมข้อมูลเวอร์ชันแอพ
- มีฐานข้อมูล catalog รุ่นรถและสถิติกลางฝั่งเซิร์ฟเวอร์

## โครงสร้างโปรเจกต์

- `lib/` แอพ Flutter
- `test/` unit/widget tests
- `server/` PHP backend, SQL schema, deployment notes
- `tool/` เครื่องมือช่วยสร้างข้อมูล catalog
- `android/`, `ios/` โปรเจกต์ native ของ Flutter

## เริ่มใช้งานฝั่งแอพ

ต้องมี Flutter SDK แล้วรัน:

```bash
flutter pub get
flutter test
flutter run \
  --dart-define=CARCARE_API=https://carcare.example.com \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com \
  --dart-define=APP_VERSION=1.0.1+2
```

ถ้าไม่ระบุ `CARCARE_API` แอพจะใช้ค่า placeholder `https://carcare.example.com` ซึ่งเหมาะสำหรับตัวอย่าง แต่ยังใช้งานซิงก์จริงไม่ได้

## ตั้งค่า backend

ดูรายละเอียดใน [server/README.md](server/README.md)

โดยย่อ:

```bash
cd server
cp config.example.php config.php
```

จากนั้นแก้ `config.php` ให้ตรงกับฐานข้อมูลและ Google client IDs ของระบบจริง ไฟล์นี้ถูก ignore และไม่ควร commit เพราะมีค่าลับของเซิร์ฟเวอร์

## หมายเหตุสำหรับ public repository

ไฟล์ build, cache, IDE settings, `android/local.properties`, `server/config.php`, `.env`, certificate และ private key ถูกกันออกจาก git แล้วผ่าน `.gitignore`

ก่อน push ควรตรวจอีกครั้งด้วย:

```bash
git status --short
git diff --cached --stat
```
