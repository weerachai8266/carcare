<?php

declare(strict_types=1);

/**
 * ส่งฟีดแบ็คจากหน้าเว็บ
 *
 * ฟอร์มนี้ไม่เรียก /api/feedback เพราะ API ยืนยันตัวตนด้วย Bearer token
 * ส่วนหน้าเว็บใช้คุกกี้ ซึ่งต้องมีโทเคน CSRF คุมเพิ่ม — ตรรกะการตรวจข้อมูล
 * และการบันทึกยังเป็นชุดเดียวกัน (CarCare\Feedback)
 */

require_once __DIR__ . '/lib/asset.php';
require_once dirname(__DIR__) . '/src/bootstrap.php';

use CarCare\Auth;
use CarCare\Feedback;

const CSRF_PURPOSE = 'feedback-form';

$currentUser = Auth::currentUser();
if ($currentUser === null) {
    header('Location: ' . url('/login.php'));
    exit;
}

$error = null;
$sent  = isset($_GET['sent']);

// ค่าที่ผู้ใช้กรอกไว้ ใช้เติมกลับลงฟอร์มเมื่อบันทึกไม่ผ่าน
// (พิมพ์มายาวแล้วต้องพิมพ์ใหม่เพราะเลือกชนิดผิด คือวิธีไล่คนออกจากการส่งฟีดแบ็ค)
$form = [
    'kind'    => 'bug',
    'rating'  => '',
    'message' => '',
    'contact' => '',
];

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    foreach (array_keys($form) as $field) {
        $value = $_POST[$field] ?? '';
        $form[$field] = is_string($value) ? $value : '';
    }

    try {
        if (!Auth::checkCsrf(CSRF_PURPOSE, (string) ($_POST['csrf'] ?? ''))) {
            throw new RuntimeException('การยืนยันคำขอไม่ผ่าน กรุณาโหลดหน้านี้ใหม่แล้วส่งอีกครั้ง');
        }

        Feedback::submit((int) $currentUser['id'], 'web', $form + [
            'platform' => 'web',
            // user agent ยาวได้เป็นร้อยตัวอักษร ปล่อยให้ Feedback ตัดตามความยาวคอลัมน์
            'device'   => $_SERVER['HTTP_USER_AGENT'] ?? null,
        ]);

        // redirect หลังบันทึกสำเร็จ (POST → redirect → GET) เพื่อให้การกดรีเฟรช
        // ที่หน้าผลลัพธ์ไม่ส่งฟอร์มเดิมซ้ำ และปุ่มย้อนกลับไม่เด้ง "ยืนยันการส่งซ้ำ"
        header('Location: ' . url('/feedback.php?sent=1'));
        exit;
    } catch (PDOException $e) {
        // ข้อความของ PDO มีชื่อตาราง/คอลัมน์ติดมาด้วย ไม่ควรขึ้นบนหน้าเว็บ
        error_log('[carcare] sql: ' . $e->getMessage());
        $error = 'ระบบขัดข้อง กรุณาลองใหม่อีกครั้ง';
    } catch (Throwable $e) {
        // ข้อความจาก Feedback::submit เขียนไว้ให้ผู้ใช้อ่านได้ตรง ๆ อยู่แล้ว
        $error = $e->getMessage();
    }
}

$title = 'ส่งฟีดแบ็ค';
require __DIR__ . '/partials/header.php';
?>

<h1>ส่งฟีดแบ็ค</h1>
<p class="lead">
    เจอปัญหา อยากได้อะไรเพิ่ม หรือตัวเลขที่เห็นดูไม่เข้าเค้า — เขียนมาได้เลย
    เราอ่านทุกข้อความ
</p>

<?php if ($sent): ?>
    <p class="notice success">
        ได้รับฟีดแบ็คของคุณแล้ว ขอบคุณมากครับ
        <?php if ($currentUser['email'] !== ''): ?>
            — ถ้าต้องถามรายละเอียดเพิ่ม เราจะติดต่อไปที่ <?= e($currentUser['email']) ?>
        <?php endif; ?>
    </p>
    <p><a href="<?= e(url('/feedback.php')) ?>">ส่งอีกเรื่อง</a> · <a href="<?= e(url('/')) ?>">กลับไปหน้าภาพรวม</a></p>
<?php else: ?>

    <?php if ($error !== null): ?>
        <p class="notice error"><?= e($error) ?></p>
    <?php endif; ?>

    <form class="form" method="post" action="<?= e(url('/feedback.php')) ?>">
        <input type="hidden" name="csrf" value="<?= e(Auth::csrfToken(CSRF_PURPOSE)) ?>">

        <fieldset class="field">
            <legend>เรื่องที่จะบอก</legend>
            <div class="choices">
                <?php foreach (Feedback::KIND_LABELS as $value => $label): ?>
                    <label class="choice">
                        <input type="radio" name="kind" value="<?= e($value) ?>"
                            <?= $form['kind'] === $value ? 'checked' : '' ?>>
                        <?= e($label) ?>
                    </label>
                <?php endforeach; ?>
            </div>
        </fieldset>

        <div class="field">
            <label for="message">รายละเอียด</label>
            <textarea id="message" name="message" rows="8" required
                      minlength="<?= Feedback::MESSAGE_MIN ?>"
                      maxlength="<?= Feedback::MESSAGE_MAX ?>"
                      placeholder="เกิดอะไรขึ้น ทำอะไรอยู่ตอนนั้น และคาดว่าควรเป็นอย่างไร"><?= e($form['message']) ?></textarea>
            <p class="hint">ยาวได้ถึง <?= number_format(Feedback::MESSAGE_MAX) ?> ตัวอักษร</p>
        </div>

        <div class="field">
            <label for="rating">ให้คะแนนแอพ (ไม่บังคับ)</label>
            <select id="rating" name="rating">
                <option value="">ไม่ระบุ</option>
                <?php foreach ([5, 4, 3, 2, 1] as $score): ?>
                    <option value="<?= $score ?>" <?= $form['rating'] === (string) $score ? 'selected' : '' ?>>
                        <?= $score ?> คะแนน
                    </option>
                <?php endforeach; ?>
            </select>
        </div>

        <div class="field">
            <label for="contact">ช่องทางติดต่อกลับ (ไม่บังคับ)</label>
            <input type="text" id="contact" name="contact" maxlength="255"
                   value="<?= e($form['contact']) ?>"
                   placeholder="อีเมลหรือ LINE ID ถ้าอยากให้ตอบทางอื่นนอกจากอีเมลของบัญชี">
        </div>

        <button type="submit">ส่งฟีดแบ็ค</button>

        <p class="hint">
            ส่งไปพร้อมกับบัญชีที่ล็อกอินอยู่ (<?= e($currentUser['email']) ?>)
            เพื่อให้เราถามรายละเอียดเพิ่มได้ ไม่มีข้อมูลรถหรือประวัติการซ่อมติดไปด้วย
        </p>
    </form>

<?php endif; ?>

<?php require __DIR__ . '/partials/footer.php'; ?>
