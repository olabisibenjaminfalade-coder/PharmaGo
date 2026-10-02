import 'package:flutter/material.dart';
import 'dart:math';

import '../models/marketplace_models.dart';
import '../state/marketplace_controller.dart';
import 'catalog_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    final cart = controller.cart;
    if (cart.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 50,
                color: Color(0xff12483b),
              ),
              SizedBox(height: 12),
              Text(
                'Your cart is empty',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 5),
              Text('Browse the shop and add products to get started.'),
            ],
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Your cart', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            for (final line in cart.items)
              _CartLineTile(line: line, controller: controller),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TotalRow(
                      label: 'Subtotal',
                      value: formatNaira(cart.total),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Delivery fee is confirmed by the seller before the order is finalized.',
                      style: TextStyle(fontSize: 11, color: Color(0xff707b76)),
                    ),
                    const SizedBox(height: 15),
                    FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    CheckoutScreen(controller: controller),
                              ),
                            ),
                      child: const Text('Continue to checkout'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.controller});

  final CartLine line;
  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 65,
            height: 65,
            child: Image.asset(
              line.product.image,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.medication_outlined, size: 36),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  line.product.size,
                  style: const TextStyle(
                    color: Color(0xff707b76),
                    fontSize: 11,
                  ),
                ),
                Text(
                  formatNaira(line.product.price * line.quantity),
                  style: const TextStyle(
                    color: Color(0xff12483b),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove one',
            onPressed: controller.busy
                ? null
                : () => controller.changeQuantity(
                    line.product.id,
                    line.quantity - 1,
                  ),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('${line.quantity}'),
          IconButton(
            tooltip: 'Add one',
            onPressed: controller.busy
                ? null
                : () => controller.changeQuantity(
                    line.product.id,
                    line.quantity + 1,
                  ),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    ),
  );
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  late final String _idempotencyKey = List<int>.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  String _paymentMethod = 'demo';

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final order = await widget.controller.checkout(
      _address.text.trim(),
      _paymentMethod,
      _idempotencyKey,
    );
    if (!mounted || order == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, color: Color(0xff12483b)),
        title: const Text('Demo order placed'),
        content: Text(
          'Reference ${order.id}\n'
          'Total: ${formatNaira(order.total)}\n\n'
          'This is a demonstration only. No payment was taken and this is not a confirmed real-world order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Checkout')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Delivery details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Delivery address',
                  hintText: 'House number, street, area and city',
                ),
                validator: (value) => (value?.trim().length ?? 0) < 5
                    ? 'Enter a complete delivery address.'
                    : null,
              ),
              const SizedBox(height: 22),
              Text(
                'Payment method',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _paymentMethod,
                onChanged: (value) =>
                    setState(() => _paymentMethod = value ?? 'demo'),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      value: 'demo',
                      title: Text('Simulated card payment'),
                      subtitle: Text(
                        'Demo only. No card details are requested and no charge is made.',
                      ),
                    ),
                    RadioListTile<String>(
                      value: 'pay_on_delivery',
                      title: Text('Pay on delivery'),
                      subtitle: Text(
                        'Demo order status only; payment is not processed.',
                      ),
                    ),
                  ],
                ),
              ),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Payment demo: this marketplace does not accept payment credentials or process real payments. A production release must use a server-verified payment provider.',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _TotalRow(
                label: 'Estimated total before delivery',
                value: formatNaira(widget.controller.cart.total),
              ),
              const SizedBox(height: 16),
              if (widget.controller.error != null)
                Text(
                  widget.controller.error!,
                  style: const TextStyle(color: Color(0xffa52e24)),
                ),
              FilledButton(
                onPressed: widget.controller.busy ? null : _submit,
                child: widget.controller.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Place demo order'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      Text(
        value,
        style: const TextStyle(
          color: Color(0xff12483b),
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}
