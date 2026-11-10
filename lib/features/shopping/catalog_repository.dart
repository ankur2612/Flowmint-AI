import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';
import 'demo_catalog.dart';
import 'shopping_models.dart';

/// Catalogue integration boundary. Products live in the `catalog_products`
/// Firestore collection, which is read-only for clients and maintained by
/// the merchant (console, admin tooling or a feed import). The same
/// collection is the price source the Cloud Functions charge from.
class CatalogRepository {
  CatalogRepository(this._firestore);
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('catalog_products');

  /// Merchant products followed by the labelled demo catalogue.
  Future<List<Product>> fetchActive({int limit = 200}) async {
    try {
      final q = await _col.where('active', isEqualTo: true).limit(limit).get();
      return [...q.docs.map(Product.fromDoc), ...demoCatalog];
    } on FirebaseException {
      return demoCatalog;
    }
  }

  Future<Product?> fetch(String id) async {
    for (final p in demoCatalog) {
      if (p.id == id) return p;
    }
    final s = await _col.doc(id).get();
    return s.exists ? Product.fromDoc(s) : null;
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(firestoreProvider)),
);

final catalogProvider = FutureProvider.autoDispose<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).fetchActive(),
);

final productProvider = FutureProvider.autoDispose.family<Product?, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).fetch(id),
);
