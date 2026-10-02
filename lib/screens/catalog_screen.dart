import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/marketplace_models.dart';
import '../state/marketplace_controller.dart';

String formatNaira(int value) => 'N${value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match[1]},',
    )}';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _search = TextEditingController();
  Timer? _searchTimer;
  String? _category;

  CartLine? _cartLineFor(String id) {
    for (final line in widget.controller.cart.items) {
      if (line.product.id == id) return line;
    }
    return null;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _searchProducts() {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      widget.controller.searchCatalog(
        query: _search.text,
        category: _category,
      );
    });
  }

  Future<void> _showDetails(MarketplaceProduct product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Wrap(
            runSpacing: 12,
            children: [
              Center(child: _ProductImage(product: product, height: 190)),
              Text(product.category.toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 1)),
              Text(product.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(product.note),
              Text('${formatNaira(product.price)}  ·  ${product.size}',
                  style: const TextStyle(
                      color: Color(0xff12483b), fontWeight: FontWeight.w800)),
              Text(product.description),
              Text('Seller: ${product.seller}'),
              Text('Available: ${product.stock}'),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: product.stock < 1
                      ? null
                      : () async {
                          final line = _cartLineFor(product.id);
                          await widget.controller.changeQuantity(
                            product.id,
                            (line?.quantity ?? 0) + 1,
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add to cart'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.controller.products;
    final categories = products.map((product) => product.category).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 9),
          child: Text('Shop pharmacy essentials',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xff0d382e),
                    fontWeight: FontWeight.w700,
                  )),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: TextField(
            controller: _search,
            onChanged: (_) => _searchProducts(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search medicines, vitamins and more',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        _searchProducts();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 58,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            scrollDirection: Axis.horizontal,
            children: [
              _CategoryChip(
                label: 'All products',
                selected: _category == null,
                onTap: () => setState(() {
                  _category = null;
                  _searchProducts();
                }),
              ),
              for (final category in categories)
                _CategoryChip(
                  label: category,
                  selected: _category == category,
                  onTap: () => setState(() {
                    _category = category;
                    _searchProducts();
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: widget.controller.busy
                      ? const CircularProgressIndicator()
                      : const Text('No products found. Try another search.'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1100
                        ? 4
                        : constraints.maxWidth >= 690
                            ? 3
                            : constraints.maxWidth >= 430
                                ? 2
                                : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 13,
                        mainAxisSpacing: 13,
                        childAspectRatio: columns == 1 ? 2.05 : .78,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) => _ProductCard(
                        product: products[index],
                        onDetails: () => _showDetails(products[index]),
                        onAdd: () async {
                          final line = _cartLineFor(products[index].id);
                          await widget.controller.changeQuantity(
                            products[index].id,
                            (line?.quantity ?? 0) + 1,
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onDetails,
    required this.onAdd,
  });

  final MarketplaceProduct product;
  final VoidCallback onDetails;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                onTap: onDetails,
                child: ColoredBox(
                  color: const Color(0xfff0f3ec),
                  child: _ProductImage(product: product),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.category.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xff707b76),
                          fontSize: 9,
                          letterSpacing: .6)),
                  const SizedBox(height: 4),
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: Text(formatNaira(product.price),
                            style: const TextStyle(
                                color: Color(0xff12483b),
                                fontWeight: FontWeight.w800)),
                      ),
                      Text(product.size,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xff707b76), fontSize: 9)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: product.stock > 0 ? onAdd : null,
                      child: Text(product.stock > 0 ? 'Add to cart' : 'Out of stock'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product, this.height});

  final MarketplaceProduct product;
  final double? height;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Image.asset(
            product.image,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.medication_outlined,
              size: 65,
              color: Color(0xff12483b),
            ),
          ),
        ),
      );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
}
