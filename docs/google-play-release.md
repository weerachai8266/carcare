# Google Play release

เอกสารนี้เก็บขั้นตอนเตรียม Android App Bundle (`.aab`) สำหรับส่งขึ้น Google Play Store

## 1. สร้าง upload key

รันจาก root ของโปรเจกต์ บน PowerShell:

```powershell
keytool -genkeypair -v `
  -keystore android/app/upload-keystore.jks `
  -storetype JKS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias upload
```

หรือบน bash:

```bash
keytool -genkeypair -v \
  -keystore android/app/upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload
```

ไฟล์ `android/app/upload-keystore.jks` เป็น private key ห้าม commit และควร backup ไว้ในที่ปลอดภัย

## 2. ตั้งค่า signing

คัดลอกไฟล์ตัวอย่าง:

```powershell
Copy-Item android/key.properties.example android/key.properties
```

หรือบน bash:

```bash
cp android/key.properties.example android/key.properties
```

แล้วแก้ค่าใน `android/key.properties` ให้ตรงกับรหัสผ่านที่ใช้สร้าง key

ไฟล์จริงที่ต้องเก็บเป็นความลับ:

- `android/key.properties`
- `android/app/upload-keystore.jks`

สองไฟล์นี้ถูก ignore ไว้แล้ว

## 3. Build App Bundle

```bash
flutter clean
flutter pub get
flutter test
flutter build appbundle --release \
  --dart-define=CARCARE_API=https://your-api-domain.example \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com \
  --dart-define=APP_VERSION=1.1.0+5
```

ไฟล์ที่ใช้ upload จะอยู่ที่:

```text
build/app/outputs/bundle/release/app-release.aab
```

## 4. Checklist ก่อนส่ง Play Console

- `pubspec.yaml` ใช้ `version: 1.1.0+5` หรือเลขใหม่กว่า และ `versionCode` ต้องมากกว่ารอบที่เคยอัปโหลด
- `android/app/build.gradle.kts` target SDK เป็น API 36
- ใช้ release keystore จริง ไม่ใช่ debug key
- ตั้งค่า Google OAuth client ID สำหรับ package `com.carcare.carcare` และ SHA-1 ของ upload/release key
- สร้าง one-time products สำหรับ Donate ใน Play Console ให้ครบ: `carcare_support_small`, `carcare_support_medium`, `carcare_support_large`
- ตั้งค่า `CARCARE_API` เป็นโดเมน backend production
- สร้าง Privacy Policy และกรอก Data safety ให้ตรงกับข้อมูลที่แอพส่งขึ้นเซิร์ฟเวอร์
- เตรียม app icon 512x512, feature graphic 1024x500, screenshots, short description และ full description

## 5. ตั้งค่า Donate ใน Play Console

สร้าง one-time products แบบ consumable ใน Play Console:

| Product ID | ตัวอย่างชื่อสินค้า |
|---|---|
| `carcare_support_small` | สนับสนุน CarCare เล็ก |
| `carcare_support_medium` | สนับสนุน CarCare กลาง |
| `carcare_support_large` | สนับสนุน CarCare ใหญ่ |

ข้อความในแอพบอกชัดว่าการสนับสนุนเป็นทางเลือกและไม่ปลดล็อกฟีเจอร์พิเศษ เพื่อให้ไม่กลายเป็นการขายความสามารถแยกต่างหาก

## 6. ตรวจ signing ของ bundle

```bash
keytool -list -v -keystore android/app/upload-keystore.jks -alias upload
```

นำ SHA-1 จากคำสั่งนี้ไปเพิ่มใน Google Cloud Console สำหรับ Android OAuth client ของแอพ
