import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show HttpConnectionInfo;

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

typedef _AuthenticatedAction = FutureOr<Response> Function(
  Request request,
  Map<String, Object?> user,
);

class MarketplaceApi {
  MarketplaceApi({
    required Database database,
    required String jwtSecret,
    required Set<String> allowedOrigins,
  }) : this._(
          database: database,
          jwtSecret: jwtSecret,
          allowedOrigins: allowedOrigins,
          passwordIterations: 600000,
        );

  MarketplaceApi.forTesting({
    required Database database,
    required String jwtSecret,
    required Set<String> allowedOrigins,
  }) : this._(
          database: database,
          jwtSecret: jwtSecret,
          allowedOrigins: allowedOrigins,
          passwordIterations: 10000,
        );

  MarketplaceApi._({
    required this.database,
    required this.jwtSecret,
    required this.allowedOrigins,
    required int passwordIterations,
  })  : _passwordIterations = passwordIterations,
        _passwordKdf = cryptography.Pbkdf2.hmacSha256(
          iterations: passwordIterations,
          bits: 256,
        ) {
    _initializeDatabase();
    _seedCatalog();
  }

  final Database database;
  final String jwtSecret;
  final Set<String> allowedOrigins;
  final int _passwordIterations;
  final cryptography.Pbkdf2 _passwordKdf;
  final Map<String, List<DateTime>> _loginAttempts = {};

  Handler get router {
    final routes = Router()
      ..get('/health', (Request request) => _json({'status': 'ok'}))
      ..post('/auth/register', _register)
      ..post('/auth/login', _login)
      ..get('/auth/me', _authenticated(_currentUser))
      ..post('/auth/logout', _authenticated(_logout))
      ..get('/categories', _listCategories)
      ..get('/products', _listProducts)
      ..post('/products', _authenticated(_createProduct))
      ..put('/products/<id>', _authenticated(_updateProduct))
      ..delete('/products/<id>', _authenticated(_removeProduct))
      ..get('/seller/products', _authenticated(_listSellerProducts))
      ..get('/cart', _authenticated(_getCart))
      ..put('/cart/<productId>', _authenticated(_updateCart))
      ..post('/orders', _authenticated(_createOrder))
      ..get('/orders', _authenticated(_listOrders))
      ..get('/seller/orders', _authenticated(_listSellerOrders))
      ..patch('/seller/orders/<id>', _authenticated(_updateOrderStatus))
      ..get('/admin/summary', _authenticated(_adminSummary))
      ..get('/admin/products', _authenticated(_adminProducts))
      ..patch('/admin/products/<id>/active', _authenticated(_setProductActive))
      ..get('/admin/categories', _authenticated(_adminCategories))
      ..post('/admin/categories', _authenticated(_createCategory))
      ..patch('/admin/categories/<id>', _authenticated(_setCategoryActive))
      ..get('/admin/users', _authenticated(_adminUsers))
      ..patch('/admin/users/<id>', _authenticated(_setUserActive));
    routes.get('/admin/vendors', _authenticated(_listPendingVendors));
    routes.patch('/admin/vendors/<id>/approve', _authenticated(_approveVendor));
    return routes.call;
  }

  Middleware get corsMiddleware => (Handler inner) => (Request request) async {
        final origin = request.headers['origin'];
        if (origin != null && !allowedOrigins.contains(origin)) {
          return _json({'error': 'Origin not allowed.'}, status: 403);
        }
        if (request.method == 'OPTIONS') {
          return Response(204, headers: _corsHeaders(origin));
        }
        return (await inner(request)).change(headers: _corsHeaders(origin));
      };

  Map<String, String> _corsHeaders(String? origin) => {
        if (origin != null) 'access-control-allow-origin': origin,
        'access-control-allow-methods':
            'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers':
            'authorization, content-type, idempotency-key',
        'vary': 'Origin',
      };

  void _initializeDatabase() {
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        full_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('buyer', 'seller', 'admin')),
        vendor_id TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS auth_sessions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id),
        expires_at TEXT NOT NULL,
        revoked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS vendors (
        id TEXT PRIMARY KEY,
        owner_user_id TEXT REFERENCES users(id),
        name TEXT NOT NULL,
        approved INTEGER NOT NULL DEFAULT 0
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        vendor_id TEXT NOT NULL REFERENCES vendors(id),
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        note TEXT NOT NULL,
        size TEXT NOT NULL,
        price INTEGER NOT NULL CHECK (price > 0),
        stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
        tag TEXT NOT NULL DEFAULT '',
        image TEXT NOT NULL,
        description TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS cart_items (
        buyer_id TEXT NOT NULL REFERENCES users(id),
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        PRIMARY KEY (buyer_id, product_id)
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY,
        buyer_id TEXT NOT NULL REFERENCES users(id),
        idempotency_key TEXT UNIQUE,
        status TEXT NOT NULL,
        payment_status TEXT NOT NULL,
        total INTEGER NOT NULL CHECK (total >= 0),
        delivery_address TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    final orderColumns = database.select('PRAGMA table_info(orders)');
    if (!orderColumns.any((column) => column['name'] == 'idempotency_key')) {
      database.execute('ALTER TABLE orders ADD COLUMN idempotency_key TEXT');
      database.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS orders_idempotency_key ON orders(idempotency_key)');
    }
    database.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        order_id TEXT NOT NULL REFERENCES orders(id),
        product_id TEXT NOT NULL REFERENCES products(id),
        vendor_id TEXT NOT NULL REFERENCES vendors(id),
        product_name TEXT NOT NULL,
        unit_price INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        PRIMARY KEY (order_id, product_id)
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS order_fulfillments (
        order_id TEXT NOT NULL REFERENCES orders(id),
        vendor_id TEXT NOT NULL REFERENCES vendors(id),
        status TEXT NOT NULL DEFAULT 'placed',
        PRIMARY KEY (order_id, vendor_id)
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS audit_events (
        id TEXT PRIMARY KEY,
        actor_id TEXT REFERENCES users(id),
        action TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> bootstrapAdministrator(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!_validEmail(normalizedEmail) ||
        password.length < 15 ||
        password.length > 128) {
      throw ArgumentError(
          'Administrator bootstrap requires a valid email and passphrase of 15–128 characters.');
    }
    final existing = database
        .select('SELECT id FROM users WHERE email = ?', [normalizedEmail]);
    if (existing.isNotEmpty) return;
    final passwordHash = await _hashPassword(password);
    database.execute(
      '''INSERT INTO users (id, email, full_name, password_hash, role, created_at)
      VALUES (?, ?, 'PharmaGo Administrator', ?, 'admin', ?)''',
      [_newId(), normalizedEmail, passwordHash, _now()],
    );
  }

  void _seedCatalog() {
    database.execute(
      'INSERT OR IGNORE INTO vendors (id, name, approved) VALUES (?, ?, 1)',
      ['pharmago-store', 'PharmaGo Store'],
    );
    const seedProducts = [
      [
        'multi',
        'Daily Multivitamin',
        'Vitamins',
        'Everyday support',
        '60 tablets',
        8500,
        20,
        'multivitamin.jpg',
        'A daily multivitamin. Check the label for ingredients and directions.'
      ],
      [
        'vitc',
        'Vitamin C 1000 mg',
        'Vitamins',
        'Immune support',
        '30 tablets',
        5200,
        20,
        'Vitamin-C-1000mg-Mega-C-1.webp',
        'Vitamin C tablets. Refer to the packaging for ingredients and warnings.'
      ],
      [
        'omega',
        'Omega-3 Fish Oil',
        'Vitamins',
        'Daily wellness',
        '60 softgels',
        17500,
        20,
        's-l1600.webp',
        'Omega-3 softgels. Check the label for full product details.'
      ],
      [
        'thermo',
        'Digital Thermometer',
        'First aid',
        'Quick, clear readings',
        '1 device',
        7800,
        20,
        'images.jpg',
        'A digital thermometer. Follow the device instructions for use and cleaning.'
      ],
      [
        'firstaid',
        'Antiseptic First Aid',
        'First aid',
        'For minor cuts and scrapes',
        '250 ml',
        4300,
        20,
        'Antiseptic First Aid.jpg',
        'Read the packaging for directions, precautions and intended use.'
      ],
      [
        'sun',
        'Daily Sunscreen SPF 50',
        'Personal care',
        'Broad spectrum care',
        '50 ml',
        6800,
        20,
        'Daily Sunscreen SPF 50.jpg',
        'Follow the product label for application and reapplication directions.'
      ],
      [
        'balm',
        'Soothing Skin Balm',
        'Personal care',
        'Everyday moisture',
        '100 ml',
        6100,
        20,
        'Soothing Skin Balm.jpg',
        'Review the packaging for ingredients and suitability for your skin.'
      ],
      [
        'pain',
        'Pain Relief Tablets',
        'Pain relief',
        'For occasional aches',
        '10 tablets',
        1000,
        20,
        '1a8ee9606909489d6cb71348387babba.jpg',
        'The active ingredient is not specified here; check the package and ask a pharmacist.'
      ],
      [
        'sudrex',
        'Sudrex Tablets',
        'Pain relief',
        'For occasional aches',
        'Tablets',
        2000,
        20,
        'sudrex.jpg',
        'Check the product packaging for ingredients, strength, pack size and directions.'
      ],
      [
        'cream',
        'Cream',
        'Personal care',
        'Everyday personal care',
        'See product packaging',
        1800,
        20,
        'vaseline.jpg',
        'Check the product packaging for intended use, ingredients and directions.'
      ],
    ];
    for (final product in seedProducts) {
      database.execute(
        'INSERT OR IGNORE INTO categories (id, name, active) VALUES (?, ?, 1)',
        [_categoryId(_text(product[2])), _text(product[2])],
      );
      database.execute(
        '''INSERT OR IGNORE INTO products
        (id, vendor_id, name, category, note, size, price, stock, image, description)
        VALUES (?, 'pharmago-store', ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          product[0],
          product[1],
          product[2],
          product[3],
          product[4],
          product[5],
          product[6],
          product[7],
          product[8],
        ],
      );
    }
  }

  Handler _authenticated(_AuthenticatedAction action) =>
      (Request request) async {
        final authorization = request.headers['authorization'];
        if (authorization == null || !authorization.startsWith('Bearer ')) {
          return _json({'error': 'Authentication required.'}, status: 401);
        }
        final claims = _verifyToken(authorization.substring(7));
        if (claims == null) {
          return _json(
              {'error': 'Session is invalid or expired. Sign in again.'},
              status: 401);
        }
        final sessions = database.select(
          '''SELECT id FROM auth_sessions
          WHERE id = ? AND user_id = ? AND revoked = 0 AND expires_at > ?''',
          [claims['sid'], claims['sub'], _now()],
        );
        if (sessions.isEmpty) {
          return _json({'error': 'Session is no longer active. Sign in again.'},
              status: 401);
        }
        final users = database.select(
          'SELECT id, email, full_name, role, vendor_id, active FROM users WHERE id = ?',
          [claims['sub']],
        );
        if (users.isEmpty || users.first['active'] != 1) {
          return _json({'error': 'Account is unavailable.'}, status: 403);
        }
        return action(request, users.first);
      };

  Future<Response> _register(Request request) async {
    final body = await _readJson(request);
    if (body is! Map<String, Object?>) {
      return _json({'error': 'Expected a JSON object.'}, status: 400);
    }
    final email = _text(body['email']).toLowerCase();
    final name = _text(body['fullName']);
    final password = _text(body['password']);
    final requestedRole = _text(body['role']);
    if (!_validEmail(email) ||
        name.trim().length < 2 ||
        password.length < 15 ||
        password.length > 128 ||
        !const {'buyer', 'seller'}.contains(requestedRole)) {
      return _json({
        'error':
            'Provide a valid email, name, passphrase of 15–128 characters, and buyer or seller role.',
      }, status: 400);
    }
    if (database
        .select('SELECT id FROM users WHERE email = ?', [email]).isNotEmpty) {
      return _json({'error': 'An account with that email already exists.'},
          status: 409);
    }
    final id = _newId();
    final vendorId = requestedRole == 'seller' ? 'vendor-$id' : null;
    final passwordHash = await _hashPassword(password);
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute(
        '''INSERT INTO users (id, email, full_name, password_hash, role, vendor_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)''',
        [id, email, name.trim(), passwordHash, requestedRole, vendorId, _now()],
      );
      if (vendorId != null) {
        database.execute(
          'INSERT INTO vendors (id, owner_user_id, name, approved) VALUES (?, ?, ?, 0)',
          [vendorId, id, '${name.trim()} pharmacy'],
        );
      }
      database.execute('COMMIT');
    } on SqliteException catch (error) {
      database.execute('ROLLBACK');
      if (error.message.contains('UNIQUE constraint failed: users.email')) {
        return _json({'error': 'An account with that email already exists.'},
            status: 409);
      }
      rethrow;
    }
    return _json({
      'message':
          'Account created. Seller listings require administrator approval.'
    }, status: 201);
  }

  Future<Response> _login(Request request) async {
    final body = await _readJson(request);
    if (body is! Map<String, Object?>) {
      return _json({'error': 'Expected a JSON object.'}, status: 400);
    }
    final email = _text(body['email']).toLowerCase();
    final connection = request.context['shelf.io.connection_info'];
    final remoteAddress = connection is HttpConnectionInfo
        ? connection.remoteAddress.address
        : 'unknown';
    if (!_allowLogin('$remoteAddress:$email')) {
      return _json(
          {'error': 'Too many sign-in attempts. Wait before trying again.'},
          status: 429);
    }
    final password = _text(body['password']);
    final rows =
        database.select('SELECT * FROM users WHERE email = ?', [email]);
    if (rows.isEmpty ||
        rows.first['active'] != 1 ||
        !(await _verifyPassword(
            password, _text(rows.first['password_hash'])))) {
      return _json({'error': 'Email or password is incorrect.'}, status: 401);
    }
    final user = rows.first;
    final sessionId = _newId();
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 1));
    database.execute(
      'INSERT INTO auth_sessions (id, user_id, expires_at) VALUES (?, ?, ?)',
      [sessionId, user['id'], expiresAt.toIso8601String()],
    );
    final token = _createToken({
      'sub': user['id'],
      'role': user['role'],
      'sid': sessionId,
      'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
    });
    return _json({
      'token': token,
      'user': _publicUser(Map<String, Object?>.from(user)),
    });
  }

  Response _currentUser(Request request, Map<String, Object?> user) =>
      _json({'user': _publicUser(user)});

  Response _listCategories(Request request) {
    final rows = database.select(
      'SELECT name FROM categories WHERE active = 1 ORDER BY name',
    );
    return _json({'categories': rows.map((row) => row['name']).toList()});
  }

  Response _logout(Request request, Map<String, Object?> user) {
    final claims = _verifyToken(request.headers['authorization']!.substring(7));
    if (claims == null) {
      return _json({'error': 'Session is invalid or expired.'}, status: 401);
    }
    database.execute(
      'UPDATE auth_sessions SET revoked = 1 WHERE id = ? AND user_id = ?',
      [claims['sid'], user['id']],
    );
    return _json({'message': 'Signed out.'});
  }

  Response _listProducts(Request request) {
    final query = (request.url.queryParameters['q'] ?? '').trim().toLowerCase();
    final category = request.url.queryParameters['category'];
    final rows = database.select(
      '''SELECT p.*, v.name AS vendor_name FROM products p
      JOIN vendors v ON v.id = p.vendor_id
      WHERE p.active = 1 AND v.approved = 1
      AND (? = '' OR lower(p.name || ' ' || p.category || ' ' || p.note) LIKE ?)
      AND (? IS NULL OR p.category = ?)
      ORDER BY p.name''',
      [query, '%$query%', category, category],
    );
    return _json({'products': rows.map(_publicProduct).toList()});
  }

  Future<Response> _createProduct(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'seller' || user['vendor_id'] == null) {
      return _json({'error': 'An approved seller account is required.'},
          status: 403);
    }
    final approved = database.select(
        'SELECT approved FROM vendors WHERE id = ?', [user['vendor_id']]);
    if (approved.isEmpty || approved.first['approved'] != 1) {
      return _json(
          {'error': 'Your seller account is awaiting administrator approval.'},
          status: 403);
    }
    final body = await _readJson(request);
    final product = _validateProduct(body);
    if (product == null) {
      return _json({'error': 'Product fields are invalid.'}, status: 400);
    }
    if (!_activeCategory(product['category'] as String)) {
      return _json({'error': 'Choose an active marketplace category.'},
          status: 400);
    }
    final id = _newId();
    database.execute(
      '''INSERT INTO products (id, vendor_id, name, category, note, size, price, stock, tag, image, description)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        user['vendor_id'],
        product['name'],
        product['category'],
        product['note'],
        product['size'],
        product['price'],
        product['stock'],
        product['tag'],
        product['image'],
        product['description']
      ],
    );
    return _json({
      'product': {...product, 'id': id, 'sellerId': user['vendor_id']}
    }, status: 201);
  }

  Future<Response> _updateProduct(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'seller') {
      return _json({'error': 'Seller role required.'}, status: 403);
    }
    final body = await _readJson(request);
    final product = _validateProduct(body);
    if (product == null) {
      return _json({'error': 'Product fields are invalid.'}, status: 400);
    }
    if (!_activeCategory(product['category'] as String)) {
      return _json({'error': 'Choose an active marketplace category.'},
          status: 400);
    }
    final updated = database.select(
      'SELECT id FROM products WHERE id = ? AND vendor_id = ?',
      [request.params['id'], user['vendor_id']],
    );
    if (updated.isEmpty) {
      return _json({'error': 'Product not found.'}, status: 404);
    }
    database.execute(
      '''UPDATE products SET name=?, category=?, note=?, size=?, price=?, stock=?, tag=?, image=?, description=?
      WHERE id=? AND vendor_id=?''',
      [
        product['name'],
        product['category'],
        product['note'],
        product['size'],
        product['price'],
        product['stock'],
        product['tag'],
        product['image'],
        product['description'],
        request.params['id'],
        user['vendor_id']
      ],
    );
    return _json({
      'product': {...product, 'id': request.params['id']}
    });
  }

  Response _removeProduct(Request request, Map<String, Object?> user) {
    if (user['role'] != 'seller') {
      return _json({'error': 'Seller role required.'}, status: 403);
    }
    final id = request.params['id'];
    final existing = database.select(
      'SELECT id FROM products WHERE id = ? AND vendor_id = ?',
      [id, user['vendor_id']],
    );
    if (existing.isEmpty) {
      return _json({'error': 'Product not found.'}, status: 404);
    }
    database.execute('UPDATE products SET active = 0 WHERE id = ?', [id]);
    return _json({'message': 'Product deactivated.'});
  }

  Response _listSellerProducts(Request request, Map<String, Object?> user) {
    if (user['role'] != 'seller' || user['vendor_id'] == null) {
      return _json({'error': 'Seller role required.'}, status: 403);
    }
    final rows = database.select(
      '''SELECT p.*, v.name AS vendor_name FROM products p
      JOIN vendors v ON v.id = p.vendor_id
      WHERE p.vendor_id = ? ORDER BY p.name''',
      [user['vendor_id']],
    );
    return _json({'products': rows.map(_publicProduct).toList()});
  }

  Response _getCart(Request request, Map<String, Object?> user) {
    if (user['role'] != 'buyer') {
      return _json({'error': 'Buyer role required.'}, status: 403);
    }
    return _cartResponse(user['id'] as String);
  }

  Future<Response> _updateCart(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'buyer') {
      return _json({'error': 'Buyer role required.'}, status: 403);
    }
    final body = await _readJson(request);
    final quantity = body is Map<String, Object?> ? body['quantity'] : null;
    if (quantity is! int || quantity < 0) {
      return _json({'error': 'Quantity must be a non-negative integer.'},
          status: 400);
    }
    final productId = request.params['productId'];
    final product = database.select(
        'SELECT stock FROM products WHERE id = ? AND active = 1', [productId]);
    if (product.isEmpty) {
      return _json({'error': 'Product is unavailable.'}, status: 404);
    }
    if (quantity > (product.first['stock'] as int)) {
      return _json({'error': 'Requested quantity exceeds stock.'}, status: 409);
    }
    if (quantity == 0) {
      database.execute(
          'DELETE FROM cart_items WHERE buyer_id = ? AND product_id = ?',
          [user['id'], productId]);
    } else {
      database.execute(
        '''INSERT INTO cart_items (buyer_id, product_id, quantity) VALUES (?, ?, ?)
        ON CONFLICT(buyer_id, product_id) DO UPDATE SET quantity = excluded.quantity''',
        [user['id'], productId, quantity],
      );
    }
    return _cartResponse(user['id'] as String);
  }

  Future<Response> _createOrder(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'buyer') {
      return _json({'error': 'Buyer role required.'}, status: 403);
    }
    final body = await _readJson(request);
    if (body is! Map<String, Object?>) {
      return _json({'error': 'Expected a JSON object.'}, status: 400);
    }
    final address = _text(body['deliveryAddress']).trim();
    final paymentMethod = _text(body['paymentMethod']);
    final idempotencyKey = request.headers['idempotency-key']?.trim() ?? '';
    if (address.length < 5 ||
        address.length > 300 ||
        idempotencyKey.length < 16 ||
        idempotencyKey.length > 120 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(idempotencyKey) ||
        !const {'demo', 'pay_on_delivery'}.contains(paymentMethod)) {
      return _json({
        'error':
            'Provide a valid delivery address and supported demo payment method.'
      }, status: 400);
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      final previousOrder = database.select(
        'SELECT * FROM orders WHERE buyer_id = ? AND idempotency_key = ?',
        [user['id'], idempotencyKey],
      );
      if (previousOrder.isNotEmpty) {
        database.execute('COMMIT');
        return _json({
          'order': _orderWithItems(previousOrder.first),
          'message': 'This order request was already processed.'
        }, status: 200);
      }
      final cart = database.select(
        '''SELECT p.id, p.name, p.vendor_id, p.price, p.stock, c.quantity
        FROM cart_items c JOIN products p ON p.id = c.product_id
        WHERE c.buyer_id = ? AND p.active = 1''',
        [user['id']],
      );
      if (cart.isEmpty) {
        database.execute('ROLLBACK');
        return _json({'error': 'Your cart is empty.'}, status: 400);
      }
      for (final item in cart) {
        if ((item['quantity'] as int) > (item['stock'] as int)) {
          database.execute('ROLLBACK');
          return _json({'error': '${item['name']} no longer has enough stock.'},
              status: 409);
        }
      }
      final total = cart.fold<int>(
          0,
          (sum, item) =>
              sum + (item['price'] as int) * (item['quantity'] as int));
      final orderId = _newId();
      database.execute(
        '''INSERT INTO orders (id, buyer_id, idempotency_key, status, payment_status, total, delivery_address, created_at)
        VALUES (?, ?, ?, 'placed', ?, ?, ?, ?)''',
        [
          orderId,
          user['id'],
          idempotencyKey,
          paymentMethod == 'pay_on_delivery'
              ? 'awaiting_delivery_payment'
              : 'not_paid_demo',
          total,
          address,
          _now(),
        ],
      );
      final vendorIds = cart.map((item) => item['vendor_id'] as String).toSet();
      for (final vendorId in vendorIds) {
        database.execute(
          'INSERT INTO order_fulfillments (order_id, vendor_id, status) VALUES (?, ?, ?)',
          [orderId, vendorId, 'placed'],
        );
      }
      for (final item in cart) {
        database.execute(
          '''INSERT INTO order_items (order_id, product_id, vendor_id, product_name, unit_price, quantity)
          VALUES (?, ?, ?, ?, ?, ?)''',
          [
            orderId,
            item['id'],
            item['vendor_id'],
            item['name'],
            item['price'],
            item['quantity']
          ],
        );
        database.execute(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [item['quantity'], item['id']],
        );
      }
      database
          .execute('DELETE FROM cart_items WHERE buyer_id = ?', [user['id']]);
      database.execute(
        'INSERT INTO audit_events (id, actor_id, action, entity_id, created_at) VALUES (?, ?, ?, ?, ?)',
        [_newId(), user['id'], 'order_placed', orderId, _now()],
      );
      database.execute('COMMIT');
      return _json({
        'order': {
          'id': orderId,
          'status': 'placed',
          'paymentStatus': paymentMethod == 'pay_on_delivery'
              ? 'awaiting_delivery_payment'
              : 'not_paid_demo',
          'total': total,
        },
        'message': paymentMethod == 'demo'
            ? 'Demo order placed; no payment was taken.'
            : 'Order placed for pay-on-delivery.',
      }, status: 201);
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Response _listOrders(Request request, Map<String, Object?> user) {
    if (user['role'] != 'buyer') {
      return _json({'error': 'Buyer role required.'}, status: 403);
    }
    final orders = database.select(
      'SELECT * FROM orders WHERE buyer_id = ? ORDER BY created_at DESC',
      [user['id']],
    );
    return _json({'orders': orders.map(_orderWithItems).toList()});
  }

  Response _listSellerOrders(Request request, Map<String, Object?> user) {
    if (user['role'] != 'seller' || user['vendor_id'] == null) {
      return _json({'error': 'Seller role required.'}, status: 403);
    }
    final orders = database.select(
      '''SELECT o.*, f.vendor_id AS fulfillment_vendor_id, f.status AS fulfillment_status
      FROM orders o JOIN order_fulfillments f ON f.order_id = o.id
      WHERE f.vendor_id = ? ORDER BY o.created_at DESC''',
      [user['vendor_id']],
    );
    return _json({
      'orders': orders
          .map((order) => {
                ..._orderWithItems(order,
                    vendorId: user['vendor_id'] as String),
                'sellerStatus': order['fulfillment_status'],
              })
          .toList()
    });
  }

  Future<Response> _updateOrderStatus(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'seller' && user['role'] != 'admin') {
      return _json({'error': 'Seller or administrator role required.'},
          status: 403);
    }
    final body = await _readJson(request);
    final nextStatus =
        body is Map<String, Object?> ? _text(body['status']) : '';
    final vendorId = user['role'] == 'admin'
        ? (body is Map<String, Object?> ? _text(body['vendorId']) : '')
        : _text(user['vendor_id']);
    const transitions = {
      'placed': {'confirmed', 'cancelled'},
      'confirmed': {'packed', 'cancelled'},
      'packed': {'out_for_delivery'},
      'out_for_delivery': {'delivered'},
      'delivered': <String>{},
      'cancelled': <String>{},
    };
    final orderId = request.params['id']!;
    database.execute('BEGIN IMMEDIATE');
    try {
      final fulfillments = database.select(
        '''SELECT status FROM order_fulfillments
        WHERE order_id = ? AND vendor_id = ?''',
        [orderId, vendorId],
      );
      if (fulfillments.isEmpty) {
        if (user['role'] != 'admin') {
          _audit(user['id'] as String, 'denied_order_update', orderId);
          database.execute('COMMIT');
          return _json({'error': 'You cannot update this order.'}, status: 403);
        }
        database.execute('ROLLBACK');
        return _json(
          {'error': 'Seller fulfilment was not found; provide its vendor ID.'},
          status: 404,
        );
      }
      final currentStatus = fulfillments.first['status'] as String;
      if (!(transitions[currentStatus] ?? const <String>{})
          .contains(nextStatus)) {
        database.execute('ROLLBACK');
        return _json({'error': 'That order status transition is not allowed.'},
            status: 409);
      }
      database.execute(
        'UPDATE order_fulfillments SET status = ? WHERE order_id = ? AND vendor_id = ?',
        [nextStatus, orderId, vendorId],
      );
      if (nextStatus == 'cancelled') {
        final items = database.select(
          'SELECT product_id, quantity FROM order_items WHERE order_id = ? AND vendor_id = ?',
          [orderId, vendorId],
        );
        for (final item in items) {
          database.execute('UPDATE products SET stock = stock + ? WHERE id = ?',
              [item['quantity'], item['product_id']]);
        }
      }
      final states = database
          .select(
            'SELECT status FROM order_fulfillments WHERE order_id = ?',
            [orderId],
          )
          .map((row) => row['status'] as String)
          .toList();
      final terminal = states.every(
        (status) => status == 'delivered' || status == 'cancelled',
      );
      final aggregateStatus = !terminal
          ? 'in_fulfilment'
          : states.every((status) => status == 'cancelled')
              ? 'cancelled'
              : states.contains('cancelled')
                  ? 'partially_cancelled'
                  : 'delivered';
      database.execute('UPDATE orders SET status = ? WHERE id = ?',
          [aggregateStatus, orderId]);
      _audit(user['id'] as String, 'fulfilment_status_$nextStatus', orderId);
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    return _json(
        {'orderId': orderId, 'vendorId': vendorId, 'status': nextStatus});
  }

  Response _adminSummary(Request request, Map<String, Object?> user) {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final users = database
        .select('SELECT role, COUNT(*) AS count FROM users GROUP BY role')
        .map((row) => {'role': row['role'], 'count': row['count']})
        .toList();
    final listings = database
        .select('SELECT COUNT(*) AS count FROM products WHERE active = 1')
        .first['count'];
    final orders = database
        .select('SELECT status, COUNT(*) AS count FROM orders GROUP BY status')
        .map((row) => {'status': row['status'], 'count': row['count']})
        .toList();
    return _json(
        {'users': users, 'activeListings': listings, 'ordersByStatus': orders});
  }

  Response _adminProducts(Request request, Map<String, Object?> user) {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final rows = database.select(
      '''SELECT p.*, v.name AS vendor_name FROM products p
      JOIN vendors v ON v.id = p.vendor_id ORDER BY p.name''',
    );
    return _json({
      'products': rows
          .map((row) => {
                ..._publicProduct(row),
                'active': row['active'] == 1,
                'vendorId': row['vendor_id'],
              })
          .toList(),
    });
  }

  Future<Response> _setProductActive(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final body = await _readJson(request);
    final active = body is Map<String, Object?> ? body['active'] : null;
    if (active is! bool) {
      return _json({'error': 'Active must be true or false.'}, status: 400);
    }
    final productId = request.params['id']!;
    final product =
        database.select('SELECT id FROM products WHERE id = ?', [productId]);
    if (product.isEmpty) {
      return _json({'error': 'Product not found.'}, status: 404);
    }
    database.execute('UPDATE products SET active = ? WHERE id = ?',
        [active ? 1 : 0, productId]);
    _audit(user['id'] as String,
        active ? 'product_approved' : 'product_deactivated', productId);
    return _json({'productId': productId, 'active': active});
  }

  Response _adminCategories(Request request, Map<String, Object?> user) {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final rows = database
        .select('SELECT id, name, active FROM categories ORDER BY name');
    return _json({
      'categories': rows
          .map((row) => {
                'id': row['id'],
                'name': row['name'],
                'active': row['active'] == 1,
              })
          .toList(),
    });
  }

  Future<Response> _createCategory(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final body = await _readJson(request);
    final name = body is Map<String, Object?> ? _text(body['name']).trim() : '';
    if (name.isEmpty || name.length > 60) {
      return _json({'error': 'Category name must be 1–60 characters.'},
          status: 400);
    }
    if (database.select(
        'SELECT id FROM categories WHERE name = ?', [name]).isNotEmpty) {
      return _json({'error': 'That category already exists.'}, status: 409);
    }
    final id = _categoryId(name);
    final idExists = database
        .select('SELECT id FROM categories WHERE id = ?', [id]).isNotEmpty;
    final categoryId = idExists ? '$id-${_newId().substring(0, 8)}' : id;
    database.execute(
        'INSERT INTO categories (id, name) VALUES (?, ?)', [categoryId, name]);
    _audit(user['id'] as String, 'category_created', categoryId);
    return _json({'id': categoryId, 'name': name, 'active': true}, status: 201);
  }

  Future<Response> _setCategoryActive(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final body = await _readJson(request);
    final active = body is Map<String, Object?> ? body['active'] : null;
    if (active is! bool) {
      return _json({'error': 'Active must be true or false.'}, status: 400);
    }
    final id = request.params['id']!;
    final category =
        database.select('SELECT id FROM categories WHERE id = ?', [id]);
    if (category.isEmpty) {
      return _json({'error': 'Category not found.'}, status: 404);
    }
    database.execute(
        'UPDATE categories SET active = ? WHERE id = ?', [active ? 1 : 0, id]);
    _audit(user['id'] as String,
        active ? 'category_activated' : 'category_deactivated', id);
    return _json({'id': id, 'active': active});
  }

  Response _adminUsers(Request request, Map<String, Object?> user) {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final rows = database.select(
      'SELECT id, email, full_name, role, active, created_at FROM users ORDER BY created_at DESC',
    );
    return _json({
      'users': rows
          .map((row) => {
                'id': row['id'],
                'email': row['email'],
                'fullName': row['full_name'],
                'role': row['role'],
                'active': row['active'] == 1,
                'createdAt': row['created_at'],
              })
          .toList()
    });
  }

  Future<Response> _setUserActive(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final body = await _readJson(request);
    final active = body is Map<String, Object?> ? body['active'] : null;
    if (active is! bool) {
      return _json({'error': 'Active must be true or false.'}, status: 400);
    }
    final id = request.params['id']!;
    if (id == user['id']) {
      return _json(
          {'error': 'Administrators cannot deactivate their own account.'},
          status: 409);
    }
    final account = database.select('SELECT id FROM users WHERE id = ?', [id]);
    if (account.isEmpty) {
      return _json({'error': 'User not found.'}, status: 404);
    }
    database.execute(
        'UPDATE users SET active = ? WHERE id = ?', [active ? 1 : 0, id]);
    if (!active) {
      database.execute(
          'UPDATE auth_sessions SET revoked = 1 WHERE user_id = ?', [id]);
    }
    _audit(user['id'] as String, active ? 'user_activated' : 'user_deactivated',
        id);
    return _json({'userId': id, 'active': active});
  }

  Response _listPendingVendors(Request request, Map<String, Object?> user) {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final vendors = database.select(
      '''SELECT v.id, v.name, u.email, u.full_name
      FROM vendors v JOIN users u ON u.id = v.owner_user_id
      WHERE v.approved = 0 ORDER BY v.name''',
    );
    return _json({
      'vendors': vendors
          .map((row) => {
                'id': row['id'],
                'name': row['name'],
                'email': row['email'],
                'fullName': row['full_name'],
              })
          .toList()
    });
  }

  Future<Response> _approveVendor(
      Request request, Map<String, Object?> user) async {
    if (user['role'] != 'admin') {
      return _json({'error': 'Administrator role required.'}, status: 403);
    }
    final updated = database
        .select('SELECT id FROM vendors WHERE id = ?', [request.params['id']]);
    if (updated.isEmpty) {
      return _json({'error': 'Seller application not found.'}, status: 404);
    }
    database.execute(
        'UPDATE vendors SET approved = 1 WHERE id = ?', [request.params['id']]);
    _audit(user['id'] as String, 'seller_approved', request.params['id']!);
    return _json({'vendorId': request.params['id'], 'approved': true});
  }

  Response _cartResponse(String buyerId) {
    final rows = database.select(
      '''SELECT p.id, p.name, p.category, p.size, p.price, p.image, p.stock, c.quantity
      FROM cart_items c JOIN products p ON p.id = c.product_id
      WHERE c.buyer_id = ? AND p.active = 1 ORDER BY p.name''',
      [buyerId],
    );
    final items = rows
        .map((row) => {
              'id': row['id'],
              'name': row['name'],
              'category': row['category'],
              'size': row['size'],
              'price': row['price'],
              'image': row['image'],
              'stock': row['stock'],
              'quantity': row['quantity'],
            })
        .toList();
    return _json({
      'items': items,
      'total': rows.fold<int>(0,
          (sum, row) => sum + (row['price'] as int) * (row['quantity'] as int))
    });
  }

  Map<String, Object?> _orderWithItems(Row order, {String? vendorId}) {
    final items = database
        .select(
          '''SELECT i.product_id AS productId, i.product_name AS name, i.unit_price AS unitPrice,
      i.quantity, f.status AS sellerStatus
      FROM order_items i JOIN order_fulfillments f
      ON f.order_id = i.order_id AND f.vendor_id = i.vendor_id
      WHERE i.order_id = ? AND (? IS NULL OR i.vendor_id = ?)''',
          [order['id'], vendorId, vendorId],
        )
        .map((item) => {
              'productId': item['productId'],
              'name': item['name'],
              'unitPrice': item['unitPrice'],
              'quantity': item['quantity'],
              'sellerStatus': item['sellerStatus'],
            })
        .toList();
    return {
      'id': order['id'],
      'status': order['status'],
      'paymentStatus': order['payment_status'],
      'total': order['total'],
      'deliveryAddress': order['delivery_address'],
      'createdAt': order['created_at'],
      'items': items,
    };
  }

  Map<String, Object?> _publicUser(Map<String, Object?> user) => {
        'id': user['id'],
        'email': user['email'],
        'fullName': user['full_name'],
        'role': user['role'],
        'vendorId': user['vendor_id'],
      };

  Map<String, Object?> _publicProduct(Row product) => {
        'id': product['id'],
        'name': product['name'],
        'category': product['category'],
        'note': product['note'],
        'size': product['size'],
        'price': product['price'],
        'stock': product['stock'],
        'tag': product['tag'],
        'image': product['image'],
        'description': product['description'],
        'seller': product['vendor_name'],
      };

  Map<String, Object?>? _validateProduct(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final name = _text(value['name']).trim();
    final category = _text(value['category']).trim();
    final note = _text(value['note']).trim();
    final size = _text(value['size']).trim();
    final description = _text(value['description']).trim();
    final image = _text(value['image']).trim();
    final price = value['price'];
    final stock = value['stock'];
    final tag = _text(value['tag']).trim();
    if (name.isEmpty ||
        name.length > 100 ||
        category.isEmpty ||
        category.length > 60 ||
        note.isEmpty ||
        note.length > 160 ||
        size.isEmpty ||
        size.length > 80 ||
        description.isEmpty ||
        description.length > 2000 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._ ()-]{0,175}\.(png|jpe?g|webp)$',
                caseSensitive: false)
            .hasMatch(image) ||
        image.contains('..') ||
        tag.length > 40 ||
        price is! int ||
        price < 1 ||
        stock is! int ||
        stock < 0) {
      return null;
    }
    return {
      'name': name,
      'category': category,
      'note': note,
      'size': size,
      'description': description,
      'image': image,
      'price': price,
      'stock': stock,
      'tag': tag,
    };
  }

  Future<Object?> _readJson(Request request) async {
    try {
      return jsonDecode(await request.readAsString());
    } on FormatException {
      return null;
    }
  }

  Response _json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  String _text(Object? value) => value is String ? value : '';
  bool _validEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  String _now() => DateTime.now().toUtc().toIso8601String();
  String _categoryId(String name) {
    final id = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return id.isEmpty ? 'category-${_newId()}' : id;
  }

  bool _activeCategory(String name) => database.select(
        'SELECT id FROM categories WHERE name = ? AND active = 1',
        [name],
      ).isNotEmpty;

  String _newId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void _audit(String actorId, String action, String entityId) {
    database.execute(
      'INSERT INTO audit_events (id, actor_id, action, entity_id, created_at) VALUES (?, ?, ?, ?, ?)',
      [_newId(), actorId, action, entityId, _now()],
    );
  }

  bool _allowLogin(String key) {
    final now = DateTime.now().toUtc();
    final recent = (_loginAttempts[key] ?? const [])
        .where((time) => now.difference(time) < const Duration(minutes: 15))
        .toList();
    if (recent.length >= 10) {
      _loginAttempts[key] = recent;
      return false;
    }
    recent.add(now);
    _loginAttempts[key] = recent;
    return true;
  }

  Future<String> _hashPassword(String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await _passwordKdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    return 'pbkdf2-sha256\$$_passwordIterations\$${base64UrlEncode(salt)}\$${base64UrlEncode(await hash.extractBytes())}';
  }

  Future<bool> _verifyPassword(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations != _passwordIterations) return false;
    try {
      final salt = base64Url.decode(base64Url.normalize(parts[2]));
      final expected = base64Url.decode(base64Url.normalize(parts[3]));
      final actual = await _passwordKdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      return _constantTimeEquals(expected, await actual.extractBytes());
    } on FormatException {
      return false;
    }
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    var difference = a.length ^ b.length;
    final length = max(a.length, b.length);
    for (var i = 0; i < length; i++) {
      difference |= (i < a.length ? a[i] : 0) ^ (i < b.length ? b[i] : 0);
    }
    return difference == 0;
  }

  String _createToken(Map<String, Object?> claims) {
    final header = base64Url
        .encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})))
        .replaceAll('=', '');
    final payload =
        base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
    final content = '$header.$payload';
    final signature = Hmac(sha256, utf8.encode(jwtSecret))
        .convert(utf8.encode(content))
        .bytes;
    return '$content.${base64Url.encode(signature).replaceAll('=', '')}';
  }

  Map<String, Object?>? _verifyToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final header = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))));
      final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (header is! Map ||
          header['alg'] != 'HS256' ||
          claims is! Map<String, Object?>) {
        return null;
      }
      final content = '${parts[0]}.${parts[1]}';
      final expected = Hmac(sha256, utf8.encode(jwtSecret))
          .convert(utf8.encode(content))
          .bytes;
      final provided = base64Url.decode(base64Url.normalize(parts[2]));
      if (!_constantTimeEquals(expected, provided)) return null;
      if (claims['exp'] is! int ||
          (claims['exp'] as int) <=
              DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) {
        return null;
      }
      return claims;
    } on FormatException {
      return null;
    }
  }
}
