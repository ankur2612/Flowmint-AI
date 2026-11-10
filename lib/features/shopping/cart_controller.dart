import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/firebase_providers.dart';
import 'shopping_models.dart';

class CartState {
  const CartState(this.items, this.checkoutKey);

  final List<CartItem> items;

  /// Idempotency key for checking out exactly this cart. It changes whenever
  /// the cart changes, so retrying a failed checkout of the same cart reuses
  /// the existing PayPal order instead of creating a duplicate.
  final String checkoutKey;

  bool get isEmpty => items.isEmpty;
  int get count => items.fold(0, (s, i) => s + i.quantity);
  int get totalMinor => items.fold(0, (s, i) => s + i.lineMinor);
  String? get currency => items.isEmpty ? null : items.first.product.currency;
}

class CartController extends Notifier<CartState> {
  static const maxQuantity = 10;

  @override
  CartState build() {
    // A different (or no) signed-in user always starts with an empty cart.
    ref.watch(uidProvider);
    return CartState(const [], const Uuid().v4());
  }

  /// Returns an error message when the product cannot be added.
  String? add(Product product, {int quantity = 1}) {
    if (!product.inStock) return '${product.name} is out of stock.';
    final currency = state.currency;
    if (currency != null && currency != product.currency) {
      return 'Your cart is in $currency. Check out or clear it before adding items priced in ${product.currency}.';
    }
    final existing = state.items
        .where((i) => i.product.id == product.id)
        .firstOrNull;
    final next = ((existing?.quantity ?? 0) + quantity).clamp(1, maxQuantity);
    _set(product.id, product, next);
    return null;
  }

  void setQuantity(String productId, int quantity) {
    final item = state.items
        .where((i) => i.product.id == productId)
        .firstOrNull;
    if (item == null) return;
    if (quantity <= 0) {
      remove(productId);
    } else {
      _set(productId, item.product, quantity.clamp(1, maxQuantity));
    }
  }

  void remove(String productId) => state = CartState(
    state.items.where((i) => i.product.id != productId).toList(),
    const Uuid().v4(),
  );

  void clear() => state = CartState(const [], const Uuid().v4());

  void _set(String id, Product product, int quantity) {
    final items = [...state.items];
    final index = items.indexWhere((i) => i.product.id == id);
    if (index == -1) {
      items.add(CartItem(product, quantity));
    } else {
      items[index] = CartItem(product, quantity);
    }
    state = CartState(items, const Uuid().v4());
  }
}

final cartProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);
