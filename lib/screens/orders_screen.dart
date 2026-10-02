import 'package:flutter/material.dart';

import '../models/marketplace_models.dart';
import '../state/marketplace_controller.dart';
import 'catalog_screen.dart';

class BuyerOrdersScreen extends StatelessWidget {
  const BuyerOrdersScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) => _OrdersList(
    orders: controller.orders,
    emptyMessage: 'Your orders will appear here after checkout.',
    seller: false,
  );
}

class SellerOrdersScreen extends StatelessWidget {
  const SellerOrdersScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) => _OrdersList(
    orders: controller.orders,
    emptyMessage: 'There are no orders to fulfil yet.',
    seller: true,
    onStatusChange: controller.updateOrderStatus,
  );
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({
    required this.orders,
    required this.emptyMessage,
    required this.seller,
    this.onStatusChange,
  });

  final List<MarketplaceOrder> orders;
  final String emptyMessage;
  final bool seller;
  final Future<void> Function(String, String)? onStatusChange;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          seller ? 'Fulfilment queue' : 'Your orders',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        for (final order in orders)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Order ${order.id.substring(0, order.id.length < 8 ? order.id.length : 8)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Chip(
                        label: Text(
                          seller
                              ? order.sellerStatus ?? order.status
                              : order.status,
                        ),
                      ),
                      Text(
                        formatNaira(order.total),
                        style: const TextStyle(
                          color: Color(0xff12483b),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  if (order.createdAt.isNotEmpty)
                    Text(
                      order.createdAt,
                      style: const TextStyle(
                        color: Color(0xff707b76),
                        fontSize: 10,
                      ),
                    ),
                  const Divider(height: 22),
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${item.name} × ${item.quantity}'),
                          ),
                          Text(formatNaira(item.unitPrice * item.quantity)),
                        ],
                      ),
                    ),
                  if (!seller && order.deliveryAddress.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        'Delivery: ${order.deliveryAddress}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  if (!seller)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Payment status: not paid (demo)',
                        style: TextStyle(
                          color: Color(0xff707b76),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (seller) ...[
                    const SizedBox(height: 10),
                    _StatusAction(
                      order: order,
                      onStatusChange: onStatusChange!,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({required this.order, required this.onStatusChange});

  final MarketplaceOrder order;
  final Future<void> Function(String, String) onStatusChange;

  static const transitions = {
    'placed': ('confirmed', 'Confirm order'),
    'confirmed': ('packed', 'Mark packed'),
    'packed': ('out_for_delivery', 'Send for delivery'),
    'out_for_delivery': ('delivered', 'Mark delivered'),
  };

  @override
  Widget build(BuildContext context) {
    final state = order.sellerStatus ?? order.status;
    final transition = transitions[state];
    if (transition == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: () => onStatusChange(order.id, transition.$1),
        icon: const Icon(Icons.arrow_forward),
        label: Text(transition.$2),
      ),
    );
  }
}
