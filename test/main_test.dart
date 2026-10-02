import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmago/main.dart';
import 'package:pharmago/services/api_client.dart';
import 'package:pharmago/state/marketplace_controller.dart';

void main() {
  testWidgets('sign-in and registration forms fit a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      PharmaGoApp(controller: MarketplaceController(ApiClient())),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('New to PharmaGo? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Buyer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
