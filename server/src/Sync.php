<?php

declare(strict_types=1);

namespace CarCare;

/**
 * ซิงก์ข้อมูลสองทางแบบ last-write-wins
 *
 * ฝั่งแอพส่งเฉพาะแถวที่ `dirty = 1` ขึ้นมา และขอแถวที่เปลี่ยนหลัง `since` กลับไป
 * ตัวตัดสินว่าใครใหม่กว่าคือ `updated_at` ของเครื่องที่แก้ ส่วนเคอร์เซอร์ของการดึง
 * ใช้ `synced_at` ที่เซิร์ฟเวอร์ประทับเอง (นาฬิกาเครื่องลูกเชื่อไม่ได้)
 */
final class Sync
{
    /** คอลัมน์ที่ยอมรับจากเครื่องลูก — คอลัมน์นอกรายการนี้ถูกทิ้ง */
    private const TABLES = [
        'vehicles' => [
            'id', 'name', 'make', 'model', 'make_id', 'model_id', 'year', 'plate',
            'fuel_type', 'tank_capacity', 'initial_odo', 'is_active', 'sort_order',
            'created_at', 'updated_at', 'deleted',
        ],
        'fuel_entries' => [
            'id', 'vehicle_id', 'date', 'odometer', 'liters', 'price_per_liter',
            'total_cost', 'is_full_tank', 'missed_entries', 'fuel_type', 'station',
            'note', 'created_at', 'updated_at', 'deleted',
        ],
        'maintenance_tasks' => [
            'id', 'vehicle_id', 'name', 'category', 'interval_km', 'interval_months',
            'notify_km_before', 'notify_days_before', 'is_active', 'sort_order',
            'created_at', 'updated_at', 'deleted',
        ],
        'service_records' => [
            'id', 'vehicle_id', 'task_id', 'title', 'date', 'odometer', 'cost',
            'workshop', 'note', 'created_at', 'updated_at', 'deleted',
        ],
    ];

    /**
     * ค่าปริยายของคอลัมน์ NOT NULL ที่ schema มี DEFAULT ให้อยู่แล้ว
     *
     * เครื่องลูกที่เป็นแอพคนละเวอร์ชันอาจไม่รู้จักคอลัมน์ที่เพิ่งเพิ่ม แล้วส่งมาไม่ครบ
     * ถ้าปล่อยให้กลายเป็น NULL ทั้งชุดจะถูก MySQL โหมด strict ตีกลับหมด
     * คือซิงก์ไม่ได้ทั้งก้อนเพราะคอลัมน์เดียว — เติมค่าปริยายให้แทนตรงนี้
     */
    private const DEFAULTS = [
        'vehicles' => [
            'initial_odo' => 0, 'is_active' => 1, 'sort_order' => 0, 'deleted' => 0,
        ],
        'fuel_entries' => [
            'is_full_tank' => 1, 'missed_entries' => 0, 'deleted' => 0,
        ],
        'maintenance_tasks' => [
            'notify_km_before' => 500, 'notify_days_before' => 7,
            'is_active' => 1, 'sort_order' => 0, 'deleted' => 0,
        ],
        'service_records' => [
            'deleted' => 0,
        ],
    ];

    /**
     * คอลัมน์ที่ขาดไม่ได้จริง ๆ — เดาค่าแทนให้ไม่ได้โดยไม่ทำข้อมูลเพี้ยน
     *
     * ตอบกลับเป็นข้อความที่บอกได้ว่าแถวไหนขาดอะไร ดีกว่าปล่อยให้ MySQL ตีกลับ
     * เป็นข้อความ SQL ที่ไคลเอนต์เอาไปทำอะไรต่อไม่ได้
     */
    private const REQUIRED = [
        'vehicles'          => ['name', 'created_at', 'updated_at'],
        'fuel_entries'      => ['vehicle_id', 'date', 'odometer', 'liters', 'created_at', 'updated_at'],
        'maintenance_tasks' => ['vehicle_id', 'name', 'created_at', 'updated_at'],
        'service_records'   => ['vehicle_id', 'title', 'date', 'odometer', 'created_at', 'updated_at'],
    ];

    public static function tables(): array
    {
        return array_keys(self::TABLES);
    }

    /**
     * รับแถวจากเครื่องลูกมาเขียนลงฐานข้อมูล
     *
     * @param array<string, array<int, array<string, mixed>>> $changes
     * @return int จำนวนแถวที่รับเข้ามา
     */
    public static function push(int $userId, array $changes): int
    {
        $pdo   = Db::pdo();
        $now   = Db::now();
        $count = 0;

        $pdo->beginTransaction();
        try {
            foreach (self::TABLES as $table => $columns) {
                $rows = $changes[$table] ?? [];
                if (!is_array($rows) || $rows === []) {
                    continue;
                }

                $statement = $pdo->prepare(self::upsertSql($table, $columns));

                foreach ($rows as $row) {
                    if (!is_array($row) || !isset($row['id'])) {
                        continue;
                    }

                    foreach (self::REQUIRED[$table] as $required) {
                        if (($row[$required] ?? null) === null) {
                            throw new \RuntimeException(
                                "แถวใน {$table} (id {$row['id']}) ไม่มีค่าของ {$required}"
                            );
                        }
                    }

                    $values = [];
                    foreach ($columns as $column) {
                        $values[] = $row[$column] ?? self::DEFAULTS[$table][$column] ?? null;
                    }
                    $values[] = $userId;
                    $values[] = $now;

                    $statement->execute($values);
                    $count++;
                }
            }

            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }

        return $count;
    }

    /**
     * ดึงแถวที่เปลี่ยนหลัง [$since] ของผู้ใช้คนนี้
     *
     * @return array<string, array<int, array<string, mixed>>>
     */
    public static function pull(int $userId, int $since): array
    {
        $pdo    = Db::pdo();
        $result = [];

        foreach (self::TABLES as $table => $columns) {
            $select = implode(', ', $columns);
            $stmt   = $pdo->prepare(
                "SELECT {$select} FROM {$table}
                 WHERE user_id = :user_id AND synced_at > :since
                 ORDER BY synced_at ASC"
            );
            $stmt->execute(['user_id' => $userId, 'since' => $since]);
            $result[$table] = $stmt->fetchAll();
        }

        return $result;
    }

    /**
     * INSERT ... ON DUPLICATE KEY UPDATE ที่เขียนทับเฉพาะเมื่อของที่ส่งมาใหม่กว่า
     *
     * เงื่อนไข `user_id` ในทุกคอลัมน์กันไม่ให้ใครส่ง id ของคนอื่นขึ้นมาทับข้อมูล
     * (id เป็น UUID ที่เครื่องลูกสร้าง จึงต้องกันที่ชั้นนี้ ไม่ใช่เชื่อว่าเดาไม่ได้)
     */
    private static function upsertSql(string $table, array $columns): string
    {
        $insertColumns = array_merge($columns, ['user_id', 'synced_at']);
        $placeholders  = implode(', ', array_fill(0, count($insertColumns), '?'));
        $columnList    = implode(', ', $insertColumns);

        $updates = [];
        foreach (array_merge($columns, ['synced_at']) as $column) {
            if ($column === 'id') {
                continue;
            }
            $updates[] = sprintf(
                '%1$s = IF(incoming.updated_at > %2$s.updated_at AND %2$s.user_id = incoming.user_id,'
                . ' incoming.%1$s, %2$s.%1$s)',
                $column,
                $table
            );
        }

        return sprintf(
            'INSERT INTO %s (%s) VALUES (%s) AS incoming ON DUPLICATE KEY UPDATE %s',
            $table,
            $columnList,
            $placeholders,
            implode(', ', $updates)
        );
    }
}
