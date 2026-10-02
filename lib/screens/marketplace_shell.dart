import 'package:flutter/material.dart';

import '../state/marketplace_controller.dart';
import 'admin_screen.dart';
import 'catalog_screen.dart';
import 'cart_checkout_screen.dart';
import 'orders_screen.dart';
import 'seller_screen.dart';

class MarketplaceShell extends StatefulWidget {
  const MarketplaceShell({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  State<MarketplaceShell> createState() => _MarketplaceShellState();
}

class _MarketplaceShellState extends State<MarketplaceShell> {
  int _selectedIndex = 0;

  List<_Destination> get _destinations {
    if (widget.controller.isSeller) {
      return const [
        _Destination('Shop', Icons.storefront_outlined),
        _Destination('Listings', Icons.inventory_2_outlined),
        _Destination('Fulfilment', Icons.local_shipping_outlined),
      ];
    }
    if (widget.controller.isAdmin) {
      return const [
        _Destination('Shop', Icons.storefront_outlined),
        _Destination('Sellers', Icons.verified_user_outlined),
        _Destination('Reports', Icons.analytics_outlined),
      ];
    }
    return const [
      _Destination('Shop', Icons.storefront_outlined),
      _Destination('Cart', Icons.shopping_bag_outlined),
      _Destination('Orders', Icons.receipt_long_outlined),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    final index = _selectedIndex.clamp(0, destinations.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final page = _pageFor(index);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'gom.png',
              height: 33,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.local_pharmacy_outlined, size: 27),
            ),
            const SizedBox(width: 9),
            const Text(
              'PharmaGo',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          if (widget.controller.user?.role == 'buyer')
            IconButton(
              tooltip: 'Shopping cart',
              onPressed: () => setState(() => _selectedIndex = 1),
              icon: Badge(
                label: Text(
                  '${widget.controller.cart.items.fold<int>(0, (sum, line) => sum + line.quantity)}',
                ),
                isLabelVisible: widget.controller.cart.items.isNotEmpty,
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                widget.controller.user?.fullName ?? '',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.controller.busy
                ? null
                : widget.controller.signOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          if (widget.controller.error != null)
            MaterialBanner(
              content: Text(widget.controller.error!),
              leading: const Icon(Icons.error_outline),
              actions: [
                TextButton(
                  onPressed: () => widget.controller.refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: index,
                        onDestinationSelected: (value) =>
                            setState(() => _selectedIndex = value),
                        labelType: NavigationRailLabelType.all,
                        destinations: destinations
                            .map(
                              (item) => NavigationRailDestination(
                                icon: Icon(item.icon),
                                label: Text(item.label),
                              ),
                            )
                            .toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: page),
                    ],
                  )
                : page,
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) =>
                  setState(() => _selectedIndex = value),
              destinations: destinations
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _pageFor(int index) {
    if (index == 0) return CatalogScreen(controller: widget.controller);
    if (widget.controller.isSeller) {
      return index == 1
          ? SellerProductsScreen(controller: widget.controller)
          : SellerOrdersScreen(controller: widget.controller);
    }
    if (widget.controller.isAdmin) {
      return AdminScreen(controller: widget.controller, showReport: index == 2);
    }
    return index == 1
        ? CartScreen(controller: widget.controller)
        : BuyerOrdersScreen(controller: widget.controller);
  }
}

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final IconData icon;
}
