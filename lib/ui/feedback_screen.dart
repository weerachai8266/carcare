import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../services/feedback_service.dart';
import 'account_screen.dart';

/// ฟอร์มส่งฟีดแบ็คจากในแอพ
///
/// ต้องล็อกอินก่อนถึงส่งได้ (เส้นทาง API ต้องมีโทเคน) — ถ้ายังไม่ได้ล็อกอิน
/// หน้านี้จะบอกเหตุผลและพาไปหน้าบัญชีให้ ไม่ใช่โชว์ฟอร์มที่กดส่งแล้วเด้ง 401
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _services = AppServices.instance;
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _contact = TextEditingController();

  FeedbackKind _kind = FeedbackKind.bug;
  int? _rating;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // จับ messenger กับ navigator ไว้ก่อน await — หลังส่งเสร็จเราปิดหน้านี้ทิ้ง
    // การอ่าน context หลัง widget ถูกถอดออกไปแล้วจะพัง
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _services.feedback.send(
        kind: _kind,
        message: _message.text,
        rating: _rating,
        contact: _contact.text,
      );

      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('ส่งฟีดแบ็คแล้ว ขอบคุณครับ')),
      );
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // เซสชันหมดอายุระหว่างพิมพ์ ต้องล้างของเก่าทิ้งไม่งั้นจะค้างสถานะกึ่งล็อกอิน
        await _services.auth.handleUnauthorized();
      }
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'ส่งไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('ส่งฟีดแบ็ค')),
      body: _services.feedback.canSend
          ? _buildForm(theme)
          : _SignInFirst(onOpenAccount: _openAccount),
    );
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountScreen()),
    );
    // กลับมาแล้วอาจล็อกอินสำเร็จ จึงต้อง build ใหม่เพื่อสลับจากข้อความเป็นฟอร์ม
    if (mounted) setState(() {});
  }

  Widget _buildForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'เจอปัญหา อยากได้อะไรเพิ่ม หรือตัวเลขที่เห็นดูไม่เข้าเค้า — เขียนมาได้เลย',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Text('เรื่องที่จะบอก', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in FeedbackKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _kind == kind,
                  onSelected: _sending ? null : (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _message,
            enabled: !_sending,
            minLines: 5,
            maxLines: 12,
            maxLength: FeedbackService.messageMax,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'รายละเอียด',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              hintText: 'เกิดอะไรขึ้น ทำอะไรอยู่ตอนนั้น และคาดว่าควรเป็นอย่างไร',
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.length < FeedbackService.messageMin) {
                return 'เขียนรายละเอียดอย่างน้อย ${FeedbackService.messageMin} ตัวอักษร';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          Text('ให้คะแนนแอพ (ไม่บังคับ)', style: theme.textTheme.titleSmall),
          _RatingStars(
            rating: _rating,
            enabled: !_sending,
            // แตะดาวเดิมซ้ำ = ยกเลิกคะแนน ไม่งั้นให้คะแนนไปแล้วเอาคืนไม่ได้
            onChanged: (value) => setState(() => _rating = _rating == value ? null : value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contact,
            enabled: !_sending,
            maxLength: 255,
            decoration: const InputDecoration(
              labelText: 'ช่องทางติดต่อกลับ (ไม่บังคับ)',
              border: OutlineInputBorder(),
              hintText: 'อีเมลหรือ LINE ID ถ้าอยากให้ตอบทางอื่น',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _submit,
            icon: const Icon(Icons.send),
            label: const Text('ส่งฟีดแบ็ค'),
          ),
          if (_sending) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 24),
          Text(
            'ส่งไปพร้อมบัญชีที่ล็อกอินอยู่ เวอร์ชันแอพ (${FeedbackService.appVersion}) '
            'และรุ่นระบบปฏิบัติการ เพื่อให้ตามบั๊กได้ — ไม่มีข้อมูลรถ ทะเบียน '
            'หรือประวัติการซ่อมติดไปด้วย',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// ดาวให้คะแนน 1–5 ดวง แตะดวงเดิมซ้ำเพื่อยกเลิก
class _RatingStars extends StatelessWidget {
  const _RatingStars({
    required this.rating,
    required this.enabled,
    required this.onChanged,
  });

  final int? rating;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        for (var score = 1; score <= 5; score++)
          IconButton(
            tooltip: '$score คะแนน',
            onPressed: enabled ? () => onChanged(score) : null,
            icon: Icon(
              (rating ?? 0) >= score ? Icons.star : Icons.star_border,
              color: (rating ?? 0) >= score ? theme.colorScheme.primary : null,
            ),
          ),
      ],
    );
  }
}

class _SignInFirst extends StatelessWidget {
  const _SignInFirst({required this.onOpenAccount});

  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rate_review_outlined, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('ต้องเข้าสู่ระบบก่อนส่งฟีดแบ็ค', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'เราแนบบัญชีของคุณไปกับข้อความ เพื่อให้ถามรายละเอียดเพิ่มได้\n'
              'เมื่อสิ่งที่คุณเจอต้องตามต่อ',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onOpenAccount,
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('ไปหน้าบัญชี'),
            ),
          ],
        ),
      ),
    );
  }
}
