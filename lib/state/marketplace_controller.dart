import 'package:flutter/foundation.dart';

import '../models/marketplace_models.dart';
import '../services/api_client.dart';

class MarketplaceController extends ChangeNotifier {
  MarketplaceController(this.api);

  final ApiClient api;
  MarketplaceUser? user;
  List<MarketplaceProduct> products = [];
  List<MarketplaceProduct> sellerProducts = [];
  CartSnapshot cart = const CartSnapshot(items: [], total: 0);
  List<MarketplaceOrder> orders = [];
  List<Map<String, dynamic>> pendingVendors = [];
  List<Map<String, dynamic>> adminProducts = [];
  List<Map<String, dynamic>> adminCategories = [];
  List<Map<String, dynamic>> adminUsers = [];
  List<String> categories = [];
  Map<String, dynamic> adminReport = {};
  String? error;
  bool busy = false;

  bool get isSignedIn => user != null;
  bool get isSeller => user?.role == 'seller';
  bool get isAdmin => user?.role == 'admin';

  Future<void> restoreSession() async {
    busy = true;
    notifyListeners();
    try {
      if (await api.readToken() != null) {
        user = await api.currentUser();
        await _loadMarketplace();
      }
    } on ApiException catch (exception) {
      error = exception.message;
      if (exception.statusCode == 401) await api.clearToken();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    await _run(() async {
      user = await api.signIn(email, password);
      await _loadMarketplace();
    });
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    await _run(
      () => api.register(
        fullName: fullName,
        email: email,
        password: password,
        role: role,
      ),
    );
  }

  Future<void> signOut() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await api.signOut();
    } on ApiException catch (exception) {
      error = exception.message;
    } finally {
      user = null;
      cart = const CartSnapshot(items: [], total: 0);
      orders = [];
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh({String query = '', String? category}) async {
    await _run(() => _loadMarketplace(query: query, category: category));
  }

  Future<void> searchCatalog({String query = '', String? category}) async {
    await _run(() async {
      products = await api.listProducts(query: query, category: category);
    });
  }

  Future<void> changeQuantity(String productId, int quantity) async {
    await _run(() async {
      cart = await api.setCartQuantity(productId, quantity);
    });
  }

  Future<MarketplaceOrder?> checkout(
    String address,
    String paymentMethod,
    String idempotencyKey,
  ) async {
    MarketplaceOrder? order;
    await _run(() async {
      order = await api.checkout(
        deliveryAddress: address,
        paymentMethod: paymentMethod,
        idempotencyKey: idempotencyKey,
      );
      cart = await api.getCart();
      orders = await api.listOrders();
    });
    return order;
  }

  Future<void> saveProduct(MarketplaceProduct product, {String? id}) async {
    await _run(() async {
      await api.saveProduct(product, id: id);
      sellerProducts = await api.listSellerProducts();
      products = await api.listProducts();
    });
  }

  Future<void> removeProduct(String id) async {
    await _run(() async {
      await api.removeProduct(id);
      sellerProducts = await api.listSellerProducts();
      products = await api.listProducts();
    });
  }

  Future<void> updateOrderStatus(String id, String status) async {
    await _run(() async {
      await api.updateOrderStatus(id, status);
      orders = await api.listOrders(seller: true);
    });
  }

  Future<void> approveVendor(String id) async {
    await _run(() async {
      await api.approveVendor(id);
      pendingVendors = await api.pendingVendors();
      adminReport = await api.adminSummary();
    });
  }

  Future<void> setProductActive(String id, bool active) async {
    await _run(() async {
      await api.setProductActive(id, active);
      adminProducts = await api.adminProducts();
      products = await api.listProducts();
    });
  }

  Future<void> createCategory(String name) async {
    await _run(() async {
      await api.createCategory(name);
      adminCategories = await api.adminCategories();
      categories = await api.listCategories();
    });
  }

  Future<void> setCategoryActive(String id, bool active) async {
    await _run(() async {
      await api.setCategoryActive(id, active);
      adminCategories = await api.adminCategories();
      categories = await api.listCategories();
    });
  }

  Future<void> setUserActive(String id, bool active) async {
    await _run(() async {
      await api.setUserActive(id, active);
      adminUsers = await api.adminUsers();
    });
  }

  Future<void> _loadMarketplace({String query = '', String? category}) async {
    products = await api.listProducts(query: query, category: category);
    categories = await api.listCategories();
    if (user?.role == 'buyer') {
      cart = await api.getCart();
      orders = await api.listOrders();
    } else if (isSeller) {
      sellerProducts = await api.listSellerProducts();
      orders = await api.listOrders(seller: true);
    } else if (isAdmin) {
      adminReport = await api.adminSummary();
      pendingVendors = await api.pendingVendors();
      adminProducts = await api.adminProducts();
      adminCategories = await api.adminCategories();
      adminUsers = await api.adminUsers();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (exception) {
      error = exception.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
