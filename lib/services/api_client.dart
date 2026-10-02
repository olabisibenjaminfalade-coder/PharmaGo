import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/marketplace_models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? httpClient,
    FlutterSecureStorage? secureStorage,
  }) : baseUrl =
           (baseUrl ??
                   const String.fromEnvironment(
                     'PHARMAGO_API_URL',
                     defaultValue: 'http://127.0.0.1:8080',
                   ))
               .replaceAll(RegExp(r'/$'), ''),
       _http = httpClient ?? http.Client(),
       _storage = secureStorage ?? const FlutterSecureStorage();

  final String baseUrl;
  final http.Client _http;
  final FlutterSecureStorage _storage;
  static const _tokenKey = 'pharmago_access_token';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    await _request(
      'POST',
      '/auth/register',
      body: {
        'fullName': fullName,
        'email': email,
        'password': password,
        'role': role,
      },
      authenticated: false,
    );
  }

  Future<MarketplaceUser> signIn(String email, String password) async {
    final response = await _request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );
    final token = response['token'];
    final user = response['user'];
    if (token is! String || user is! Map<String, dynamic>) {
      throw const ApiException(
        'The server returned an invalid sign-in response.',
      );
    }
    await _storage.write(key: _tokenKey, value: token);
    return MarketplaceUser.fromJson(user);
  }

  Future<MarketplaceUser> currentUser() async {
    final response = await _request('GET', '/auth/me');
    return MarketplaceUser.fromJson(response['user'] as Map<String, dynamic>);
  }

  Future<void> signOut() async {
    try {
      await _request('POST', '/auth/logout');
    } finally {
      await clearToken();
    }
  }

  Future<List<MarketplaceProduct>> listProducts({
    String query = '',
    String? category,
  }) async {
    final uri = Uri.parse('$baseUrl/products').replace(
      queryParameters: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );
    final response = await _requestUri('GET', uri);
    return (response['products'] as List<dynamic>)
        .map(
          (item) => MarketplaceProduct.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<String>> listCategories() async {
    final response = await _request('GET', '/categories', authenticated: false);
    return (response['categories'] as List<dynamic>).cast<String>();
  }

  Future<CartSnapshot> getCart() async {
    final response = await _request('GET', '/cart');
    return CartSnapshot.fromJson(response);
  }

  Future<CartSnapshot> setCartQuantity(String productId, int quantity) async {
    final response = await _request(
      'PUT',
      '/cart/${Uri.encodeComponent(productId)}',
      body: {'quantity': quantity},
    );
    return CartSnapshot.fromJson(response);
  }

  Future<MarketplaceOrder> checkout({
    required String deliveryAddress,
    required String paymentMethod,
    required String idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/orders',
      headers: {'idempotency-key': idempotencyKey},
      body: {
        'deliveryAddress': deliveryAddress,
        'paymentMethod': paymentMethod,
      },
    );
    return MarketplaceOrder.fromJson(response['order'] as Map<String, dynamic>);
  }

  Future<List<MarketplaceOrder>> listOrders({bool seller = false}) async {
    final response = await _request(
      'GET',
      seller ? '/seller/orders' : '/orders',
    );
    return (response['orders'] as List<dynamic>)
        .map((item) => MarketplaceOrder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    await _request(
      'PATCH',
      '/seller/orders/${Uri.encodeComponent(orderId)}',
      body: {'status': status},
    );
  }

  Future<List<MarketplaceProduct>> listSellerProducts() async {
    final response = await _request('GET', '/seller/products');
    return (response['products'] as List<dynamic>)
        .map(
          (item) => MarketplaceProduct.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> saveProduct(MarketplaceProduct product, {String? id}) async {
    await _request(
      id == null ? 'POST' : 'PUT',
      id == null ? '/products' : '/products/${Uri.encodeComponent(id)}',
      body: product.toJson(),
    );
  }

  Future<void> removeProduct(String id) async {
    await _request('DELETE', '/products/${Uri.encodeComponent(id)}');
  }

  Future<Map<String, dynamic>> adminSummary() =>
      _request('GET', '/admin/summary');

  Future<List<Map<String, dynamic>>> adminProducts() async {
    final response = await _request('GET', '/admin/products');
    return (response['products'] as List<dynamic>)
        .map((product) => product as Map<String, dynamic>)
        .toList();
  }

  Future<void> setProductActive(String id, bool active) async {
    await _request(
      'PATCH',
      '/admin/products/${Uri.encodeComponent(id)}/active',
      body: {'active': active},
    );
  }

  Future<List<Map<String, dynamic>>> adminCategories() async {
    final response = await _request('GET', '/admin/categories');
    return (response['categories'] as List<dynamic>)
        .map((category) => category as Map<String, dynamic>)
        .toList();
  }

  Future<void> createCategory(String name) async {
    await _request('POST', '/admin/categories', body: {'name': name});
  }

  Future<void> setCategoryActive(String id, bool active) async {
    await _request(
      'PATCH',
      '/admin/categories/${Uri.encodeComponent(id)}',
      body: {'active': active},
    );
  }

  Future<List<Map<String, dynamic>>> adminUsers() async {
    final response = await _request('GET', '/admin/users');
    return (response['users'] as List<dynamic>)
        .map((user) => user as Map<String, dynamic>)
        .toList();
  }

  Future<void> setUserActive(String id, bool active) async {
    await _request(
      'PATCH',
      '/admin/users/${Uri.encodeComponent(id)}',
      body: {'active': active},
    );
  }

  Future<List<Map<String, dynamic>>> pendingVendors() async {
    final response = await _request('GET', '/admin/vendors');
    return (response['vendors'] as List<dynamic>)
        .map((vendor) => vendor as Map<String, dynamic>)
        .toList();
  }

  Future<void> approveVendor(String id) async {
    await _request(
      'PATCH',
      '/admin/vendors/${Uri.encodeComponent(id)}/approve',
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? headers,
    bool authenticated = true,
  }) => _requestUri(
    method,
    Uri.parse('$baseUrl$path'),
    body: body,
    extraHeaders: headers,
    authenticated: authenticated,
  );

  Future<Map<String, dynamic>> _requestUri(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    Map<String, String>? extraHeaders,
    bool authenticated = true,
  }) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (extraHeaders != null) headers.addAll(extraHeaders);
    if (body != null) headers['content-type'] = 'application/json';
    if (authenticated) {
      final token = await readToken();
      if (token == null) throw const ApiException('Sign in to continue.');
      headers['authorization'] = 'Bearer $token';
    }
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _http.send(request);
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException('The server returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          decoded['error'] as String? ?? 'The request could not be completed.',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach the PharmaGo API: ${error.message}');
    } on FormatException {
      throw const ApiException('The server returned malformed data.');
    }
  }

  void close() => _http.close();
}
