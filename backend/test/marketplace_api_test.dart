import 'dart:convert';
import 'dart:io';

import 'package:pharmago_backend/marketplace_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Database database;
  late HttpServer server;
  late HttpClient client;
  const jwtSecret = 'test-only-secret-that-is-long-enough-to-meet-minimum';
  final allowedOrigins = {'http://localhost:5000'};

  setUp(() async {
    database = sqlite3.openInMemory();
    client = HttpClient();
    final api = MarketplaceApi.forTesting(
      database: database,
      jwtSecret: jwtSecret,
      allowedOrigins: allowedOrigins,
    );
    server = await shelf_io.serve(
      const Pipeline().addMiddleware(api.corsMiddleware).addHandler(api.router),
      InternetAddress.loopbackIPv4,
      0,
    );
  });

  tearDown(() async {
    client.close(force: true);
    await server.close(force: true);
    database.dispose();
  });

  test('buyer registration, stock validation, checkout and replay are safe',
      () async {
    final weakRegistration = await _send(
      client,
      server,
      'POST',
      '/auth/register',
      body: {
        'fullName': 'Test Buyer',
        'email': 'weak@example.test',
        'password': 'short',
        'role': 'buyer',
      },
    );
    expect(weakRegistration.statusCode, 400);

    final registration = await _send(
      client,
      server,
      'POST',
      '/auth/register',
      body: {
        'fullName': 'Test Buyer',
        'email': 'buyer@example.test',
        'password': 'a-correct-horse-battery-staple',
        'role': 'buyer',
      },
    );
    expect(registration.statusCode, 201);

    final unknownLogin = await _send(
      client,
      server,
      'POST',
      '/auth/login',
      body: {'email': 'missing@example.test', 'password': 'incorrect'},
    );
    expect(unknownLogin.statusCode, 401);
    expect(_json(unknownLogin)['error'], 'Email or password is incorrect.');

    final login = await _send(
      client,
      server,
      'POST',
      '/auth/login',
      body: {
        'email': 'buyer@example.test',
        'password': 'a-correct-horse-battery-staple',
      },
    );
    expect(login.statusCode, 200);
    final token = _json(login)['token'] as String;

    final forbiddenCart = await _send(
      client,
      server,
      'GET',
      '/cart',
      token: 'invalid',
    );
    expect(forbiddenCart.statusCode, 401);

    final tooManyItems = await _send(
      client,
      server,
      'PUT',
      '/cart/multi',
      token: token,
      body: {'quantity': 21},
    );
    expect(tooManyItems.statusCode, 409);

    final cart = await _send(
      client,
      server,
      'PUT',
      '/cart/multi',
      token: token,
      body: {'quantity': 2},
    );
    expect(cart.statusCode, 200);
    expect(_json(cart)['total'], 17000);

    final checkout = await _send(
      client,
      server,
      'POST',
      '/orders',
      token: token,
      headers: {'idempotency-key': 'test-checkout-key-0001'},
      body: {
        'deliveryAddress': '1 Test Street, Gombe',
        'paymentMethod': 'demo',
        'total': 1,
        'price': 1,
      },
    );
    expect(checkout.statusCode, 201);
    final checkoutOrder = _json(checkout)['order'] as Map<String, dynamic>;
    expect(checkoutOrder['paymentStatus'], 'not_paid_demo');
    expect(checkoutOrder['total'], 17000);
    expect(
      database.select(
          'SELECT stock FROM products WHERE id = ?', ['multi']).first['stock'],
      18,
    );

    final retry = await _send(
      client,
      server,
      'POST',
      '/orders',
      token: token,
      headers: {'idempotency-key': 'test-checkout-key-0001'},
      body: {
        'deliveryAddress': '1 Test Street, Gombe',
        'paymentMethod': 'demo',
      },
    );
    expect(retry.statusCode, 200);
    expect((_json(retry)['order'] as Map<String, dynamic>)['id'],
        checkoutOrder['id']);

    await MarketplaceApi.forTesting(
      database: database,
      jwtSecret: jwtSecret,
      allowedOrigins: allowedOrigins,
    ).bootstrapAdministrator(
      'admin@example.test',
      'a-correct-horse-battery-staple',
    );
    final adminLogin = await _send(
      client,
      server,
      'POST',
      '/auth/login',
      body: {
        'email': 'admin@example.test',
        'password': 'a-correct-horse-battery-staple',
      },
    );
    final adminToken = _json(adminLogin)['token'] as String;
    for (final status in [
      'confirmed',
      'packed',
      'out_for_delivery',
      'delivered'
    ]) {
      final update = await _send(
        client,
        server,
        'PATCH',
        '/seller/orders/${checkoutOrder['id']}',
        token: adminToken,
        body: {'vendorId': 'pharmago-store', 'status': status},
      );
      expect(update.statusCode, 200, reason: 'Transition to $status');
    }
    final invalidTransition = await _send(
      client,
      server,
      'PATCH',
      '/seller/orders/${checkoutOrder['id']}',
      token: adminToken,
      body: {'vendorId': 'pharmago-store', 'status': 'packed'},
    );
    expect(invalidTransition.statusCode, 409);

    await _send(
      client,
      server,
      'PUT',
      '/cart/multi',
      token: token,
      body: {'quantity': 1},
    );
    final payOnDelivery = await _send(
      client,
      server,
      'POST',
      '/orders',
      token: token,
      headers: {'idempotency-key': 'test-checkout-key-0002'},
      body: {
        'deliveryAddress': '1 Test Street, Gombe',
        'paymentMethod': 'pay_on_delivery',
      },
    );
    expect(payOnDelivery.statusCode, 201);
    expect(
      (_json(payOnDelivery)['order'] as Map<String, dynamic>)['paymentStatus'],
      'awaiting_delivery_payment',
    );

    final orders = await _send(client, server, 'GET', '/orders', token: token);
    expect((_json(orders)['orders'] as List<dynamic>).length, 2);
    final completedOrder = (_json(orders)['orders'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((order) => order['id'] == checkoutOrder['id']);
    final item = (completedOrder['items'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(item['name'], 'Daily Multivitamin');
    expect(item['unitPrice'], 8500);

    final signOut = await _send(
      client,
      server,
      'POST',
      '/auth/logout',
      token: token,
    );
    expect(signOut.statusCode, 200);
    final revokedSession = await _send(
      client,
      server,
      'GET',
      '/orders',
      token: token,
    );
    expect(revokedSession.statusCode, 401);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('seller listing requires administrator approval and is ownership scoped',
      () async {
    final sellerRegistration = await _send(
      client,
      server,
      'POST',
      '/auth/register',
      body: {
        'fullName': 'Test Seller',
        'email': 'seller@example.test',
        'password': 'a-correct-horse-battery-staple',
        'role': 'seller',
      },
    );
    expect(sellerRegistration.statusCode, 201);
    final sellerLogin = await _send(
      client,
      server,
      'POST',
      '/auth/login',
      body: {
        'email': 'seller@example.test',
        'password': 'a-correct-horse-battery-staple',
      },
    );
    final sellerToken = _json(sellerLogin)['token'] as String;

    final product = {
      'name': 'Seller Test Product',
      'category': 'Vitamins',
      'note': 'Test listing',
      'size': '1 pack',
      'price': 1200,
      'stock': 4,
      'tag': '',
      'image': 'multivitamin.jpg',
      'description': 'Test listing for the automated marketplace check.',
    };
    final pendingCreate = await _send(
      client,
      server,
      'POST',
      '/products',
      token: sellerToken,
      body: product,
    );
    expect(pendingCreate.statusCode, 403);

    final api = MarketplaceApi.forTesting(
      database: database,
      jwtSecret: jwtSecret,
      allowedOrigins: allowedOrigins,
    );
    await api.bootstrapAdministrator(
      'admin@example.test',
      'a-correct-horse-battery-staple',
    );
    final adminLogin = await _send(
      client,
      server,
      'POST',
      '/auth/login',
      body: {
        'email': 'admin@example.test',
        'password': 'a-correct-horse-battery-staple',
      },
    );
    final adminToken = _json(adminLogin)['token'] as String;
    final vendors = await _send(
      client,
      server,
      'GET',
      '/admin/vendors',
      token: adminToken,
    );
    final pendingVendor = (_json(vendors)['vendors'] as List<dynamic>).single
        as Map<String, dynamic>;
    final approval = await _send(
      client,
      server,
      'PATCH',
      '/admin/vendors/${pendingVendor['id']}/approve',
      token: adminToken,
    );
    expect(approval.statusCode, 200);

    final created = await _send(
      client,
      server,
      'POST',
      '/products',
      token: sellerToken,
      body: product,
    );
    expect(created.statusCode, 201);
    final createdId =
        (_json(created)['product'] as Map<String, dynamic>)['id'] as String;

    final secondSellerRegistration = await _send(
      client,
      server,
      'POST',
      '/auth/register',
      body: {
        'fullName': 'Another Seller',
        'email': 'another-seller@example.test',
        'password': 'a-correct-horse-battery-staple',
        'role': 'seller',
      },
    );
    expect(secondSellerRegistration.statusCode, 201);
    final secondSellerLogin = await _send(
      client,
      server,
      'POST',
      '/auth/login',
      body: {
        'email': 'another-seller@example.test',
        'password': 'a-correct-horse-battery-staple',
      },
    );
    final secondSellerToken = _json(secondSellerLogin)['token'] as String;
    final secondVendor = (_json(await _send(
      client,
      server,
      'GET',
      '/admin/vendors',
      token: adminToken,
    ))['vendors'] as List<dynamic>)
        .single as Map<String, dynamic>;
    final secondApproval = await _send(
      client,
      server,
      'PATCH',
      '/admin/vendors/${secondVendor['id']}/approve',
      token: adminToken,
    );
    expect(secondApproval.statusCode, 200);
    final otherSellerUpdate = await _send(
      client,
      server,
      'PUT',
      '/products/$createdId',
      token: secondSellerToken,
      body: product,
    );
    expect(otherSellerUpdate.statusCode, 404);

    final buyerRegistration = await _send(
      client,
      server,
      'POST',
      '/auth/register',
      body: {
        'fullName': 'Other Seller',
        'email': 'other@example.test',
        'password': 'a-correct-horse-battery-staple',
        'role': 'buyer',
      },
    );
    expect(buyerRegistration.statusCode, 201);
    final buyerLogin = await _send(
      client,
      server,
      'POST',
      '/auth/login',
      body: {
        'email': 'other@example.test',
        'password': 'a-correct-horse-battery-staple',
      },
    );
    final buyerToken = _json(buyerLogin)['token'] as String;
    final unauthorizedUpdate = await _send(
      client,
      server,
      'PUT',
      '/products/$createdId',
      token: buyerToken,
      body: product,
    );
    expect(unauthorizedUpdate.statusCode, 403);

    final listing = await _send(
      client,
      server,
      'GET',
      '/products?q=Seller%20Test',
    );
    expect(listing.statusCode, 200);
    expect((_json(listing)['products'] as List<dynamic>).length, 1);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('browser origins are restricted to explicit allowlist', () async {
    final allowed = await _send(
      client,
      server,
      'GET',
      '/health',
      headers: {'origin': 'http://localhost:5000'},
    );
    expect(allowed.statusCode, 200);
    final rejected = await _send(
      client,
      server,
      'GET',
      '/health',
      headers: {'origin': 'https://untrusted.example'},
    );
    expect(rejected.statusCode, 403);
    final preflight = await _send(
      client,
      server,
      'OPTIONS',
      '/orders',
      headers: {
        'origin': 'http://localhost:5000',
        'access-control-request-method': 'POST',
        'access-control-request-headers':
            'authorization, content-type, idempotency-key',
      },
    );
    expect(preflight.statusCode, 204);
    expect(
      preflight.allowedHeaders,
      contains('idempotency-key'),
    );
  });
}

Future<HttpResponseData> _send(
  HttpClient client,
  HttpServer server,
  String method,
  String path, {
  Map<String, Object?>? body,
  Map<String, String> headers = const {},
  String? token,
}) async {
  final request = await client.openUrl(
      method, Uri.parse('http://127.0.0.1:${server.port}$path'));
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  if (body != null) request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  headers.forEach(request.headers.set);
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  return HttpResponseData(
    response.statusCode,
    responseBody,
    response.headers.value('access-control-allow-headers'),
  );
}

Map<String, dynamic> _json(HttpResponseData response) =>
    jsonDecode(response.body) as Map<String, dynamic>;

class HttpResponseData {
  const HttpResponseData(this.statusCode, this.body, this.allowedHeaders);

  final int statusCode;
  final String body;
  final String? allowedHeaders;
}
