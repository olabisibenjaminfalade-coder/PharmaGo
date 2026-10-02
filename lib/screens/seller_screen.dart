import 'package:flutter/material.dart';

import '../models/marketplace_models.dart';
import '../state/marketplace_controller.dart';
import 'catalog_screen.dart';

class SellerProductsScreen extends StatelessWidget {
  const SellerProductsScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    final products = controller.sellerProducts;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your product listings',
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            FilledButton.icon(
              onPressed: () => _editProduct(context, controller),
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text('No listings yet. Add a product to get started.'),
            ),
          ),
        for (final product in products)
          Card(
            child: ListTile(
              leading: SizedBox(
                width: 45,
                height: 45,
                child: Image.asset(product.image,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.medication_outlined)),
              ),
              title: Text(product.name),
              subtitle: Text(
                  '${product.category} · ${formatNaira(product.price)} · Stock ${product.stock}'),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Edit listing',
                    onPressed: () => _editProduct(context, controller, product),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove listing',
                    onPressed: () => _removeProduct(context, controller, product),
                    icon: const Icon(Icons.delete_outline, color: Color(0xffa52e24)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _editProduct(
  BuildContext context,
  MarketplaceController controller, [
  MarketplaceProduct? existing,
]) async {
  final formKey = GlobalKey<FormState>();
  final fields = {
    'name': TextEditingController(text: existing?.name ?? ''),
    'category': TextEditingController(text: existing?.category ?? ''),
    'note': TextEditingController(text: existing?.note ?? ''),
    'size': TextEditingController(text: existing?.size ?? ''),
    'price': TextEditingController(text: existing?.price.toString() ?? ''),
    'stock': TextEditingController(text: existing?.stock.toString() ?? '1'),
    'image': TextEditingController(text: existing?.image ?? ''),
    'description': TextEditingController(text: existing?.description ?? ''),
  };
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(existing == null ? 'Add product' : 'Edit product'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: entry.value,
                    keyboardType: {'price', 'stock'}.contains(entry.key)
                        ? TextInputType.number
                        : TextInputType.text,
                    minLines: entry.key == 'description' ? 2 : 1,
                    maxLines: entry.key == 'description' ? 3 : 1,
                    decoration: InputDecoration(
                      labelText: switch (entry.key) {
                        'name' => 'Product name',
                        'category' => 'Category',
                        'note' => 'Short description',
                        'size' => 'Pack size',
                        'price' => 'Price in naira',
                        'stock' => 'Available stock',
                        'image' => 'Project image filename',
                        _ => 'Full product description',
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'This field is required.';
                      }
                      if ({'price', 'stock'}.contains(entry.key)) {
                        final number = int.tryParse(value);
                        if (number == null || number < (entry.key == 'price' ? 1 : 0)) {
                          return entry.key == 'price'
                              ? 'Enter a whole-number price above zero.'
                              : 'Stock cannot be negative.';
                        }
                      }
                      return null;
                    },
                  ),
                ),
              const Text(
                'The image filename must refer to an asset included in this app build.',
                style: TextStyle(color: Color(0xff707b76), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, true);
            }
          },
          child: const Text('Save listing'),
        ),
      ],
    ),
  );
  if (saved == true) {
    final product = MarketplaceProduct(
      id: existing?.id ?? '',
      name: fields['name']!.text.trim(),
      category: fields['category']!.text.trim(),
      note: fields['note']!.text.trim(),
      size: fields['size']!.text.trim(),
      price: int.parse(fields['price']!.text),
      stock: int.parse(fields['stock']!.text),
      image: fields['image']!.text.trim(),
      description: fields['description']!.text.trim(),
      seller: '',
    );
    await controller.saveProduct(product, id: existing?.id);
  }
  for (final field in fields.values) {
    field.dispose();
  }
}

Future<void> _removeProduct(
  BuildContext context,
  MarketplaceController controller,
  MarketplaceProduct product,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove listing?'),
      content: Text('${product.name} will be hidden from buyers.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed == true) await controller.removeProduct(product.id);
}
