<?php

declare(strict_types=1);

namespace CarCare;

/**
 * แคตตาล็อกยี่ห้อ/รุ่นรถส่วนกลาง
 *
 * รุ่นที่สมาชิกเพิ่มเองจะเข้ามาด้วยสถานะ `approved = 0` — เจ้าตัวเห็นและใช้ได้ทันที
 * แต่จะยังไม่กระจายให้คนอื่นจนกว่าจะอนุมัติ กันชื่อสะกดต่างกันเล็กน้อย
 * แตกเป็นหลายรุ่นจนสถิติของรถรุ่นเดียวกันถูกซอยออกจากกัน
 */
final class Catalog
{
    /** @return array{makes: array, models: array} */
    public static function pull(int $userId, int $since): array
    {
        $pdo = Db::pdo();

        $makes = $pdo->prepare(
            'SELECT id, name, name_th, sort_order, is_custom, created_at, updated_at, deleted
             FROM car_makes
             WHERE synced_at > :since AND (approved = 1 OR created_by = :user_id)
             ORDER BY synced_at ASC'
        );
        $makes->execute(['since' => $since, 'user_id' => $userId]);

        $models = $pdo->prepare(
            'SELECT id, make_id, name, body_type, sort_order, is_custom, created_at, updated_at, deleted
             FROM car_models
             WHERE synced_at > :since AND (approved = 1 OR created_by = :user_id)
             ORDER BY synced_at ASC'
        );
        $models->execute(['since' => $since, 'user_id' => $userId]);

        return [
            'makes'  => $makes->fetchAll(),
            'models' => $models->fetchAll(),
        ];
    }

    /**
     * รับยี่ห้อ/รุ่นที่สมาชิกเพิ่มเองขึ้นมาเก็บไว้รออนุมัติ
     *
     * ไม่เขียนทับแถวเดิมที่อนุมัติแล้ว เพราะเครื่องลูกอาจส่งชื่อที่ผู้ใช้แก้เอง
     * ขึ้นมาแล้วไปทับชื่อมาตรฐานของทุกคน
     */
    public static function pushCustom(int $userId, array $makes, array $models): int
    {
        $pdo   = Db::pdo();
        $now   = Db::now();
        $count = 0;

        $makeStmt = $pdo->prepare(
            'INSERT INTO car_makes
                (id, name, name_th, sort_order, is_custom, approved, created_by, created_at, updated_at, synced_at, deleted)
             VALUES (?, ?, ?, ?, 1, 0, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE id = id'
        );

        foreach ($makes as $make) {
            if (!isset($make['id'], $make['name'])) {
                continue;
            }
            $makeStmt->execute([
                $make['id'],
                $make['name'],
                $make['name_th'] ?? null,
                $make['sort_order'] ?? 0,
                $userId,
                $make['created_at'] ?? $now,
                $make['updated_at'] ?? $now,
                $now,
                $make['deleted'] ?? 0,
            ]);
            $count++;
        }

        $modelStmt = $pdo->prepare(
            'INSERT INTO car_models
                (id, make_id, name, body_type, sort_order, is_custom, approved, created_by, created_at, updated_at, synced_at, deleted)
             VALUES (?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE id = id'
        );

        foreach ($models as $model) {
            if (!isset($model['id'], $model['make_id'], $model['name'])) {
                continue;
            }
            $modelStmt->execute([
                $model['id'],
                $model['make_id'],
                $model['name'],
                $model['body_type'] ?? null,
                $model['sort_order'] ?? 0,
                $userId,
                $model['created_at'] ?? $now,
                $model['updated_at'] ?? $now,
                $now,
                $model['deleted'] ?? 0,
            ]);
            $count++;
        }

        return $count;
    }
}
