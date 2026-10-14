import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/donate_service.dart';

class DonateScreen extends StatefulWidget {
  const DonateScreen({super.key, DonateService? service}) : _service = service;

  final DonateService? _service;

  @override
  State<DonateScreen> createState() => _DonateScreenState();
}

class _DonateScreenState extends State<DonateScreen> {
  late final DonateService _service = widget._service ?? DonateService();
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _loading = true;
  bool _busy = false;
  bool _storeAvailable = false;
  String? _message;
  List<ProductDetails> _products = const [];

  @override
  void initState() {
    super.initState();
    _subscription = _service.purchaseStream.listen(_onPurchases);
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final products = await _service.loadProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _storeAvailable = products.isNotEmpty;
        _message =
            products.isEmpty
                ? 'ยังโหลดรายการสนับสนุนจาก Google Play ไม่ได้ กรุณาตรวจ product IDs ใน Play Console'
                : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _storeAvailable = false;
        _message = 'โหลดรายการสนับสนุนไม่สำเร็จ: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final result = await _service.handlePurchase(purchase);
      if (result == null || !mounted) continue;
      setState(() {
        _busy = false;
        _message = result.message;
      });
    }
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await _service.buy(product);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'เปิดหน้าชำระเงินไม่สำเร็จ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('สนับสนุน CarCare')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.volunteer_activism_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'ขอบคุณที่ช่วยให้แอพนี้ไปต่อ',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'การสนับสนุนเป็นทางเลือกและไม่ปลดล็อกฟีเจอร์พิเศษ '
                      'ทุกคนใช้ฟีเจอร์หลักของ CarCare ได้เหมือนเดิม',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_products.isEmpty)
              _EmptyStoreView(message: _message, onRetry: _load)
            else ...[
              for (final product in _products) ...[
                _DonateProductTile(
                  product: product,
                  enabled: !_busy && _storeAvailable,
                  onTap: () => _buy(product),
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (_message != null && _products.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(_message!),
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: 24),
            Text(
              'รายการนี้ดำเนินการผ่าน Google Play Billing ตามนโยบายของ Play Store '
              'และไม่ควรสร้างลิงก์ไปช่องทางจ่ายเงินภายนอกภายในแอพ',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DonateProductTile extends StatelessWidget {
  const _DonateProductTile({
    required this.product,
    required this.enabled,
    required this.onTap,
  });

  final ProductDetails product;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final option = DonateCatalog.byId(product.id);

    return Card(
      child: ListTile(
        leading: const Icon(Icons.favorite_outline),
        title: Text(option?.title ?? product.title),
        subtitle: Text(option?.description ?? product.description),
        trailing: FilledButton(
          onPressed: enabled ? onTap : null,
          child: Text(product.price),
        ),
      ),
    );
  }
}

class _EmptyStoreView extends StatelessWidget {
  const _EmptyStoreView({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 52,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              message ?? 'ยังไม่มีรายการสนับสนุน',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}
