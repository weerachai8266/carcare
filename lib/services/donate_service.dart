import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

class DonateOption {
  final String id;
  final String title;
  final String description;
  final int sortOrder;

  const DonateOption({
    required this.id,
    required this.title,
    required this.description,
    required this.sortOrder,
  });
}

class DonateCatalog {
  static const small = DonateOption(
    id: 'carcare_support_small',
    title: 'เลี้ยงกาแฟ',
    description: 'ช่วยเป็นกำลังใจเล็ก ๆ ให้พัฒนา CarCare ต่อ',
    sortOrder: 1,
  );

  static const medium = DonateOption(
    id: 'carcare_support_medium',
    title: 'ช่วยค่าน้ำมัน',
    description: 'สนับสนุนเวลาทดสอบและปรับปรุงแอพ',
    sortOrder: 2,
  );

  static const large = DonateOption(
    id: 'carcare_support_large',
    title: 'สนับสนุนใหญ่',
    description: 'ช่วยให้มีแรงดูแลฟีเจอร์และ backend ต่อเนื่อง',
    sortOrder: 3,
  );

  static const all = <DonateOption>[small, medium, large];
  static const ids = <String>{
    'carcare_support_small',
    'carcare_support_medium',
    'carcare_support_large',
  };

  static DonateOption? byId(String id) {
    for (final option in all) {
      if (option.id == id) return option;
    }
    return null;
  }
}

class DonatePurchaseResult {
  final bool success;
  final String message;

  const DonatePurchaseResult._(this.success, this.message);

  const DonatePurchaseResult.success(String message) : this._(true, message);
  const DonatePurchaseResult.info(String message) : this._(false, message);
}

class DonateService {
  DonateService({InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance;

  final InAppPurchase _store;

  Stream<List<PurchaseDetails>> get purchaseStream => _store.purchaseStream;

  Future<bool> isAvailable() => _store.isAvailable();

  Future<List<ProductDetails>> loadProducts() async {
    final available = await isAvailable();
    if (!available) return const [];

    final response = await _store.queryProductDetails(DonateCatalog.ids);
    final products =
        response.productDetails.toList()..sort((a, b) {
          final left = DonateCatalog.byId(a.id)?.sortOrder ?? 99;
          final right = DonateCatalog.byId(b.id)?.sortOrder ?? 99;
          return left.compareTo(right);
        });

    return products;
  }

  Future<void> buy(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    return _store.buyConsumable(purchaseParam: param, autoConsume: true);
  }

  Future<DonatePurchaseResult?> handlePurchase(PurchaseDetails purchase) async {
    if (!DonateCatalog.ids.contains(purchase.productID)) {
      return null;
    }

    if (purchase.pendingCompletePurchase) {
      await _store.completePurchase(purchase);
    }

    switch (purchase.status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        return const DonatePurchaseResult.success(
          'ขอบคุณที่สนับสนุน CarCare มาก ๆ ครับ',
        );
      case PurchaseStatus.pending:
        return const DonatePurchaseResult.info(
          'คำสั่งซื้อกำลังรอดำเนินการใน Google Play',
        );
      case PurchaseStatus.error:
        return DonatePurchaseResult.info(
          purchase.error?.message ?? 'ซื้อไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
        );
      case PurchaseStatus.canceled:
        return const DonatePurchaseResult.info('ยกเลิกการสนับสนุนแล้ว');
    }
  }
}
