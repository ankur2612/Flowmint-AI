import 'package:flowmint_ai/core/widgets/app_card.dart';
import 'package:flowmint_ai/core/widgets/surfaces.dart';
import 'package:flowmint_ai/features/activity/activity_repository.dart';
import 'package:flowmint_ai/features/activity/activity_screen.dart';
import 'package:flowmint_ai/features/shopping/demo_catalog.dart';
import 'package:flowmint_ai/features/shopping/widgets/product_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders widgets on a narrow phone with large accessibility text. Any
/// RenderFlex overflow fails the test.
Future<void> pumpSmall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(1.6),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('activity tile with long text fits a small screen', (
    tester,
  ) async {
    await pumpSmall(
      tester,
      ActivityTile(
        entry: ActivityEntry(
          id: 'x',
          type: ActivityType.expenseSplit,
          status: ActivityStatus.pending,
          title: 'Weekend trip dinner at a restaurant with a very long name',
          subtitle:
              '2 of 5 settled · ₹12,40,000 outstanding across participants',
          verified: false,
          amountMinor: 124000000,
          createdAt: DateTime(2026, 11, 10),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo product tiles fit a small screen', (tester) async {
    await pumpSmall(
      tester,
      Column(
        children: [
          for (final p in demoCatalog.take(4))
            ProductTile(
              product: p,
              reason: 'Matches the budget and has the requested specs.',
              selected: false,
              onSelectChanged: (_) {},
            ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('DEMO'), findsWidgets);
  });

  testWidgets('light panel detail rows wrap long values', (tester) async {
    await pumpSmall(
      tester,
      const LightPanel(
        child: Column(
          children: [
            DetailRow(
              'Reference',
              'shopping_order_6f0c2a91-4a52-4a8f-9a37-1c8f3f2b9d11',
            ),
            DetailRow('Total', '₹1,23,45,678.90', emphasize: true),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
