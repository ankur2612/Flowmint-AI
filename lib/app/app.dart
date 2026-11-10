import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/notification_service.dart';
import '../core/widgets/state_views.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class FlowmintApp extends ConsumerWidget {
  const FlowmintApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'FLOWMINT AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown when Firebase could not be initialised (missing google-services.json
/// or invalid project configuration).
class FirebaseSetupRequiredApp extends StatelessWidget {
  const FirebaseSetupRequiredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Firebase is not configured',
            message:
                'Add android/app/google-services.json for your Firebase project '
                'and rebuild the app. FLOWMINT needs Firebase for sign-in, data, '
                'AI and payments.',
          ),
        ),
      ),
    );
  }
}
