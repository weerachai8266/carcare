<?php
/**
 * คัดลอกไฟล์นี้เป็น config.php แล้วแก้ค่าให้ตรงกับเซิร์ฟเวอร์จริง
 * config.php ต้องไม่ถูก commit เข้า git (ดู .gitignore)
 */

return [
    'db' => [
        'host'     => '127.0.0.1',
        'port'     => 3306,
        'name'     => 'carcare',
        'user'     => 'carcare',
        'password' => '',
    ],

    // Client ID จาก Google Cloud Console
    // ต้องใส่ให้ครบทุกแพลตฟอร์มที่จะล็อกอิน เพราะ id_token ของแต่ละแพลตฟอร์ม
    // มี aud เป็น client id ของตัวเอง ถ้าไม่อยู่ในรายการนี้จะถูกปฏิเสธ
    'google_client_ids' => [
        'xxxxxxxx.apps.googleusercontent.com', // web
        'yyyyyyyy.apps.googleusercontent.com', // android
        'zzzzzzzz.apps.googleusercontent.com', // ios
    ],

    // อายุเซสชัน (วัน)
    'session_days' => 90,

    'stats' => [
        // ต้องมีอย่างน้อยกี่ช่วงที่วัดได้ ถึงจะเอารายการนั้นมาแสดง
        'min_samples' => 3,
        // ต้องมาจากอย่างน้อยกี่คัน — กันไม่ให้ข้อมูลของรถคันเดียวกลายเป็น "สถิติ"
        // และกันการเดาย้อนกลับว่าตัวเลขเป็นของใคร
        'min_vehicles' => 3,
        // แสดงกี่อันดับต่อหมวด
        'top_per_category' => 10,
    ],
];
