import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/sync_service.dart';
import 'feedback_screen.dart';
import 'format.dart';

/// หน้าบัญชีผู้ใช้ — ล็อกอิน Google, ซิงก์ข้อมูล, ออกจากระบบ
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _services = AppServices.instance;

  bool _busy = false;
  String? _message;
  DateTime? _lastSynced;

  @override
  void initState() {
    super.initState();
    _loadLastSynced();
  }

  Future<void> _loadLastSynced() async {
    final at = await _services.sync.lastSyncedAt();
    if (mounted) setState(() => _lastSynced = at);
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // เซสชันหมดอายุแล้ว ต้องล้างของเก่าทิ้งไม่งั้นจะค้างอยู่สถานะกึ่งล็อกอิน
        await _services.auth.handleUnauthorized();
      }
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) setState(() => _message = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadLastSynced();
    }
  }

  Future<void> _signIn() => _run(() async {
        final account = await _services.auth.signIn(deviceName: 'มือถือ');
        if (account == null) return null; // ผู้ใช้กดยกเลิกเอง
        final result = await _services.sync.sync();
        return 'เข้าสู่ระบบเป็น ${account.email}\n${result.summary}';
      });

  Future<void> _syncNow() => _run(() async {
        final SyncResult result = await _services.sync.sync();
        return result.summary;
      });

  Future<void> _resyncAll() => _run(() async {
        final result = await _services.sync.resyncEverything();
        return 'ส่งขึ้นใหม่ทั้งหมดแล้ว\n${result.summary}';
      });

  Future<void> _openFeedback() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FeedbackScreen()),
      );

  Future<void> _signOut() => _run(() async {
        await _services.auth.signOut();
        // ล้างเคอร์เซอร์ด้วย ไม่งั้นบัญชีถัดไปจะดึงข้อมูลไม่ครบเพราะคิดว่าซิงก์ไปแล้ว
        await _services.sync.resetCursor();
        return 'ออกจากระบบแล้ว';
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = _services.auth.account;
    final signedIn = _services.auth.isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('บัญชีและการซิงก์')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: account?.pictureUrl == null
                        ? null
                        : NetworkImage(account!.pictureUrl!),
                    child: account?.pictureUrl == null
                        ? const Icon(Icons.person_outline)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account?.name ?? account?.email ?? 'ยังไม่ได้เข้าสู่ระบบ',
                          style: theme.textTheme.titleMedium,
                        ),
                        if (account != null && account.name != null)
                          Text(account.email, style: theme.textTheme.bodySmall),
                        if (!signedIn)
                          Text(
                            'ข้อมูลถูกเก็บไว้ในเครื่องนี้เท่านั้น',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_lastSynced != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_done_outlined),
              title: const Text('ซิงก์ล่าสุด'),
              subtitle: Text(
                '${Fmt.dateFull(_lastSynced!)} ${_lastSynced!.hour.toString().padLeft(2, '0')}:'
                '${_lastSynced!.minute.toString().padLeft(2, '0')} น.',
              ),
            ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_message!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!signedIn)
            FilledButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: const Icon(Icons.login),
              label: const Text('เข้าสู่ระบบด้วย Google'),
            )
          else ...[
            FilledButton.icon(
              onPressed: _busy ? null : _syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('ซิงก์ตอนนี้'),
            ),
            const SizedBox(height: 4),
            Text(
              'ปกติแอพซิงก์ให้เองอยู่แล้ว — หลังบันทึกข้อมูล และตอนเปิดแอพขึ้นมาใหม่ '
              'ปุ่มนี้ไว้ใช้เวลาที่อยากให้ส่งเดี๋ยวนี้',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _resyncAll,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('ส่งข้อมูลขึ้นใหม่ทั้งหมด'),
            ),
            const SizedBox(height: 4),
            Text(
              'ใช้เมื่อข้อมูลบนเซิร์ฟเวอร์หายไป — การซิงก์ปกติจะส่งเฉพาะสิ่งที่แก้ใหม่ '
              'ถ้าของบนเซิร์ฟเวอร์หายทั้งชุดจะไม่มีอะไรถูกส่งขึ้นไปเลย',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('ออกจากระบบ'),
            ),
          ],
          const SizedBox(height: 12),
          // อยู่นอก if/else ตั้งใจ — คนที่ยังไม่ล็อกอินก็ควรเห็นช่องทางบอกปัญหา
          // (หน้าฟีดแบ็คจะบอกเองว่าต้องล็อกอินก่อนส่ง)
          OutlinedButton.icon(
            onPressed: _busy ? null : _openFeedback,
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('ส่งฟีดแบ็ค'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 32),
          Text(
            'การซิงก์จะส่งประวัติการเติมน้ำมันและการบำรุงรักษาขึ้นเซิร์ฟเวอร์ '
            'เพื่อสำรองข้อมูลและใช้รวมเป็นสถิติของรถแต่ละรุ่น '
            'สถิติที่เผยแพร่เป็นค่าที่รวมแล้วเท่านั้น ไม่มีทะเบียนรถหรือชื่ออู่',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'เวอร์ชัน ${AppServices.appVersion}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
