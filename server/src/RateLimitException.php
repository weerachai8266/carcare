<?php

declare(strict_types=1);

namespace CarCare;

use RuntimeException;

/**
 * คำขอถี่เกินโควตา — ต้องตอบ 429 ไม่ใช่ 400
 *
 * แยกชนิดออกมาเพราะตัวจัดเส้นทางแปลง RuntimeException เป็น 400 ทั้งหมด
 * แต่ 400 บอกไคลเอนต์ว่า "ข้อมูลที่ส่งมาผิด" ซึ่งไม่จริงในกรณีนี้ — ข้อมูลถูกแล้ว
 * แค่ต้องรอ ถ้าตอบ 400 ผู้ใช้จะไปแก้ข้อความของตัวเองซึ่งไม่ช่วยอะไร
 */
final class RateLimitException extends RuntimeException
{
}
