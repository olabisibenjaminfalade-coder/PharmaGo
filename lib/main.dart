import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'screens/marketplace_shell.dart';
import 'services/api_client.dart';
import 'state/marketplace_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = MarketplaceController(ApiClient());
  runApp(PharmaGoApp(controller: controller));
  controller.restoreSession();
}

class PharmaGoApp extends StatelessWidget {
  const PharmaGoApp({super.key, required this.controller});

  final MarketplaceController controller;

  static const forest = Color(0xff12483b);
  static const paper = Color(0xfff8f8f3);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PharmaGo Marketplace',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: forest,
            primary: forest,
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: paper,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: forest,
            elevation: 0,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xffe4e8e1)),
            ),
          ),
        ),
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (controller.busy && controller.user == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (controller.user == null) {
              return AuthScreen(controller: controller);
            }
            return MarketplaceShell(controller: controller);
          },
        ),
      );
}
