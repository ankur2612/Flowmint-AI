import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/json_read.dart';

/// A product from the FLOWMINT catalogue (`catalog_products` collection).
/// Prices here are for display; the backend re-reads them when charging.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.description,
    required this.priceMinor,
    required this.currency,
    this.specs = const {},
    this.imageUrl,
    this.stock = 0,
    this.isDemo = false,
  });

  final String id;
  final String name;
  final String brand;
  final String category;
  final String description;
  final int priceMinor;
  final String currency;
  final Map<String, String> specs;
  final String? imageUrl;
  final int stock;

  /// Sample product for demonstrations; never payable.
  final bool isDemo;

  bool get inStock => stock > 0;

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Product(
      id: doc.id,
      name: Read.str(m['name']),
      brand: Read.str(m['brand']),
      category: Read.str(m['category']),
      description: Read.str(m['description']),
      priceMinor: Read.integer(m['priceMinor']),
      currency: Read.str(m['currency'], 'USD'),
      specs: Read.map(m['specs']).map((k, v) => MapEntry(k, Read.str(v))),
      imageUrl: Read.strOrNull(m['imageUrl']),
      stock: Read.integer(m['stock']),
    );
  }

  /// Compact representation sent to Gemini for ranking.
  Map<String, dynamic> toAiJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'category': category,
    'price': priceMinor / 100,
    'currency': currency,
    'specs': specs,
    'description': description.length > 240
        ? description.substring(0, 240)
        : description,
  };
}

class CartItem {
  const CartItem(this.product, this.quantity);
  final Product product;
  final int quantity;
  int get lineMinor => product.priceMinor * quantity;
}

class Recommendation {
  const Recommendation(this.product, this.reason);
  final Product product;
  final String reason;
}

class ShoppingResult {
  const ShoppingResult({
    required this.recommendations,
    required this.catalogueEmpty,
    this.summary,
    this.budgetMinor,
  });

  final List<Recommendation> recommendations;
  final bool catalogueEmpty;
  final String? summary;
  final int? budgetMinor;
}
