import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';
import '../../core/utils/json_read.dart';

class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.email,
    this.paypalMeUsername,
    this.notifyPayments = true,
    this.notifyRenewals = true,
    this.notifyActivity = true,
  });

  final String displayName;
  final String email;

  /// Used to build PayPal.me links in SmartSplit payment requests.
  final String? paypalMeUsername;
  final bool notifyPayments;
  final bool notifyRenewals;
  final bool notifyActivity;

  String get firstName {
    final n = displayName.trim();
    if (n.isEmpty) return '';
    return n.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    if (parts.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
    displayName: Read.str(m['displayName']),
    email: Read.str(m['email']),
    paypalMeUsername: Read.strOrNull(m['paypalMeUsername']),
    notifyPayments: Read.boolean(m['notifyPayments'], true),
    notifyRenewals: Read.boolean(m['notifyRenewals'], true),
    notifyActivity: Read.boolean(m['notifyActivity'], true),
  );
}

class ProfileRepository extends UserScopedRepository {
  const ProfileRepository(super.userDoc);

  Stream<UserProfile?> watch() => !isSignedIn
      ? const Stream.empty()
      : user.snapshots().map(
          (s) => s.data() == null ? null : UserProfile.fromMap(s.data()!),
        );

  Future<void> update(Map<String, Object?> fields) =>
      user.set(fields, SetOptions(merge: true));
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(userDocProvider)),
);

final profileProvider = StreamProvider<UserProfile?>(
  (ref) => ref.watch(profileRepositoryProvider).watch(),
);
