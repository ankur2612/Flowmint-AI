import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/firebase_providers.dart';
import '../../core/utils/json_read.dart';

class CampaignUpdate {
  const CampaignUpdate(this.title, this.body, this.date);
  final String title;
  final String body;
  final DateTime? date;
}

/// A donation campaign from the `campaigns` collection, which only FLOWMINT
/// administrators can write. [raisedMinor] and [donorCount] are maintained
/// by Cloud Functions from PayPal-verified donations made through FLOWMINT.
class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    required this.organization,
    required this.description,
    required this.category,
    required this.currency,
    required this.minAmountMinor,
    required this.suggestedAmountsMinor,
    required this.organizationVerified,
    required this.paysOrganizationDirectly,
    this.goalMinor,
    this.raisedMinor = 0,
    this.donorCount = 0,
    this.imageUrl,
    this.updates = const [],
    this.isDemo = false,
  });

  final String id;
  final String title;
  final String organization;
  final String description;
  final String category;
  final String currency;
  final int minAmountMinor;
  final List<int> suggestedAmountsMinor;

  /// Set by an administrator after verifying the organisation's identity.
  final bool organizationVerified;

  /// True when the campaign has a PayPal payee account configured, so the
  /// donation is paid to the organisation's own PayPal account.
  final bool paysOrganizationDirectly;
  final int? goalMinor;
  final int raisedMinor;
  final int donorCount;
  final String? imageUrl;
  final List<CampaignUpdate> updates;

  /// Illustrative campaign for demonstrations; donations are disabled.
  final bool isDemo;

  String get recipientLabel => paysOrganizationDirectly
      ? organization
      : '${AppConstants.merchantName}, collecting for $organization';

  factory Campaign.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    final suggested =
        (m['suggestedAmountsMinor'] is List
                ? m['suggestedAmountsMinor'] as List
                : const [])
            .map((v) => Read.integer(v))
            .where((v) => v > 0)
            .toList();
    return Campaign(
      id: doc.id,
      title: Read.str(m['title']),
      organization: Read.str(m['organization']),
      description: Read.str(m['description']),
      category: Read.str(m['category']),
      currency: Read.str(m['currency'], 'USD'),
      minAmountMinor: Read.integer(m['minAmountMinor'], 100),
      suggestedAmountsMinor: suggested,
      organizationVerified: Read.boolean(m['organizationVerified']),
      paysOrganizationDirectly: Read.strOrNull(m['payeeMerchantId']) != null,
      goalMinor: m['goalMinor'] == null ? null : Read.integer(m['goalMinor']),
      raisedMinor: Read.integer(m['raisedMinor']),
      donorCount: Read.integer(m['donorCount']),
      imageUrl: Read.strOrNull(m['imageUrl']),
      updates: [
        for (final u in Read.maps(m['updates']))
          CampaignUpdate(
            Read.str(u['title']),
            Read.str(u['body']),
            Read.date(u['date']),
          ),
      ],
    );
  }

  bool matchesCause(String cause) {
    final c = cause.toLowerCase();
    return '$title $category $description'.toLowerCase().contains(c);
  }
}

/// Sample campaigns so ImpactGiving can be demonstrated before real
/// organisations are onboarded. Targets are illustrative; nothing has been
/// raised, no organisation is verified and donations are disabled.
const demoCampaigns = <Campaign>[
  Campaign(
    id: 'demo-campaign-education',
    title: 'Laptops for Rural Classrooms',
    organization: 'Sample education initiative',
    description:
        'An illustrative campaign showing how FLOWMINT presents education causes: '
        'refurbished laptops and internet access for village school computer labs.',
    category: 'Education',
    currency: 'INR',
    minAmountMinor: 10000,
    suggestedAmountsMinor: [50000, 100000, 250000],
    organizationVerified: false,
    paysOrganizationDirectly: false,
    goalMinor: 50000000,
    isDemo: true,
  ),
  Campaign(
    id: 'demo-campaign-water',
    title: 'Clean Water Points',
    organization: 'Sample water access project',
    description:
        'An illustrative campaign for community water filters and maintenance training.',
    category: 'Health',
    currency: 'INR',
    minAmountMinor: 10000,
    suggestedAmountsMinor: [50000, 150000, 300000],
    organizationVerified: false,
    paysOrganizationDirectly: false,
    goalMinor: 30000000,
    isDemo: true,
  ),
  Campaign(
    id: 'demo-campaign-meals',
    title: 'Community Kitchen Meals',
    organization: 'Sample food relief programme',
    description:
        'An illustrative campaign funding daily meals at a neighbourhood community kitchen.',
    category: 'Hunger relief',
    currency: 'INR',
    minAmountMinor: 5000,
    suggestedAmountsMinor: [25000, 50000, 100000],
    organizationVerified: false,
    paysOrganizationDirectly: false,
    goalMinor: 20000000,
    isDemo: true,
  ),
];

class CampaignRepository {
  CampaignRepository(this._firestore);
  final FirebaseFirestore _firestore;

  /// Published campaigns followed by the labelled demo campaigns.
  Future<List<Campaign>> fetchActive() async {
    try {
      final q = await _firestore
          .collection('campaigns')
          .where('active', isEqualTo: true)
          .limit(100)
          .get();
      return [...q.docs.map(Campaign.fromDoc), ...demoCampaigns];
    } on FirebaseException {
      return demoCampaigns;
    }
  }

  Stream<Campaign?> watch(String id) {
    for (final c in demoCampaigns) {
      if (c.id == id) return Stream.value(c);
    }
    return _watchPublished(id);
  }

  Stream<Campaign?> _watchPublished(String id) => _firestore
      .collection('campaigns')
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? Campaign.fromDoc(s) : null);
}

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (ref) => CampaignRepository(ref.watch(firestoreProvider)),
);

final campaignsProvider = FutureProvider.autoDispose<List<Campaign>>(
  (ref) => ref.watch(campaignRepositoryProvider).fetchActive(),
);

final campaignProvider = StreamProvider.autoDispose.family<Campaign?, String>(
  (ref, id) => ref.watch(campaignRepositoryProvider).watch(id),
);
