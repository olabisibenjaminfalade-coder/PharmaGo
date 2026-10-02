class MarketplaceUser {
  const MarketplaceUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.vendorId,
  });

  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? vendorId;

  factory MarketplaceUser.fromJson(Map<String, dynamic> json) => MarketplaceUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        role: json['role'] as String,
        vendorId: json['vendorId'] as String?,
      );
}

class MarketplaceProduct {
  const MarketplaceProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.note,
    required this.size,
    required this.price,
    required this.stock,
    required this.image,
    required this.description,
    required this.seller,
    this.tag = '',
  });

  final String id;
  final String name;
  final String category;
  final String note;
  final String size;
  final int price;
  final int stock;
  final String image;
  final String description;
  final String seller;
  final String tag;

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) =>
      MarketplaceProduct(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        note: json['note'] as String,
        size: json['size'] as String,
        price: json['price'] as int,
        stock: json['stock'] as int,
        image: json['image'] as String,
        description: json['description'] as String,
        seller: json['seller'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
      );

  Map<String, Object> toJson() => {
        'name': name,
        'category': category,
        'note': note,
        'size': size,
        'price': price,
        'stock': stock,
        'image': image,
        'description': description,
        'tag': tag,
      };
}

class CartLine {
  const CartLine({
    required this.product,
    required this.quantity,
  });

  final MarketplaceProduct product;
  final int quantity;

  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
        product: MarketplaceProduct.fromJson({
          ...json,
          'description': json['description'] ?? '',
          'note': json['note'] ?? '',
          'seller': json['seller'] ?? '',
          'tag': json['tag'] ?? '',
        }),
        quantity: json['quantity'] as int,
      );
}

class MarketplaceOrderItem {
  const MarketplaceOrderItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.sellerStatus,
  });

  final String productId;
  final String name;
  final int unitPrice;
  final int quantity;
  final String? sellerStatus;

  factory MarketplaceOrderItem.fromJson(Map<String, dynamic> json) =>
      MarketplaceOrderItem(
        productId: json['productId'] as String,
        name: json['name'] as String,
        unitPrice: json['unitPrice'] as int,
        quantity: json['quantity'] as int,
        sellerStatus: json['sellerStatus'] as String?,
      );
}

class MarketplaceOrder {
  const MarketplaceOrder({
    required this.id,
    required this.status,
    required this.paymentStatus,
    required this.total,
    required this.createdAt,
    required this.items,
    this.deliveryAddress = '',
    this.sellerStatus,
  });

  final String id;
  final String status;
  final String paymentStatus;
  final int total;
  final String createdAt;
  final String deliveryAddress;
  final String? sellerStatus;
  final List<MarketplaceOrderItem> items;

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) =>
      MarketplaceOrder(
        id: json['id'] as String,
        status: json['status'] as String,
        paymentStatus: json['paymentStatus'] as String,
        total: json['total'] as int,
        createdAt: json['createdAt'] as String? ?? '',
        deliveryAddress: json['deliveryAddress'] as String? ?? '',
        sellerStatus: json['sellerStatus'] as String?,
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) => MarketplaceOrderItem.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class CartSnapshot {
  const CartSnapshot({required this.items, required this.total});

  final List<CartLine> items;
  final int total;

  factory CartSnapshot.fromJson(Map<String, dynamic> json) => CartSnapshot(
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((item) => CartLine.fromJson(item as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int? ?? 0,
      );
}
