import 'dart:io';

import 'package:pharmago_backend/marketplace_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart';

Future<void> main() async {
  final jwtSecret = Platform.environment['PHARMAGO_JWT_SECRET'];
  if (jwtSecret == null || utf8Length(jwtSecret) < 32) {
    stderr.writeln(
        'Set PHARMAGO_JWT_SECRET to a unique secret of at least 32 bytes.');
    exitCode = 64;
    return;
  }
  final databasePath =
      Platform.environment['PHARMAGO_DATABASE'] ?? 'pharmago.sqlite';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080');
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln('PORT must be a valid TCP port.');
    exitCode = 64;
    return;
  }

  final database = sqlite3.open(databasePath);
  try {
    final allowedOrigins =
        (Platform.environment['PHARMAGO_ALLOWED_ORIGINS'] ?? '')
            .split(',')
            .map((origin) => origin.trim())
            .where((origin) => origin.isNotEmpty)
            .toSet();
    final api = MarketplaceApi(
      database: database,
      jwtSecret: jwtSecret,
      allowedOrigins: allowedOrigins,
    );
    final adminEmail = Platform.environment['PHARMAGO_ADMIN_EMAIL'];
    final adminPassword = Platform.environment['PHARMAGO_ADMIN_PASSWORD'];
    if (adminEmail != null && adminPassword != null) {
      await api.bootstrapAdministrator(adminEmail, adminPassword);
    }
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(api.corsMiddleware)
        .addHandler(api.router);
    final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    stdout.writeln('PharmaGo API listening on ${server.address.host}:$port');
    await ProcessSignal.sigint.watch().first;
    await server.close(force: true);
  } finally {
    database.dispose();
  }
}

int utf8Length(String value) => value.codeUnits.fold<int>(
      0,
      (length, unit) => length + (unit > 0x7f ? 2 : 1),
    );
