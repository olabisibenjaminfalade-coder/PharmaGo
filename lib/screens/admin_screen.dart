import 'package:flutter/material.dart';

import '../state/marketplace_controller.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({
    super.key,
    required this.controller,
    required this.showReport,
  });

  final MarketplaceController controller;
  final bool showReport;

  @override
  Widget build(BuildContext context) {
    if (showReport) {
      final report = controller.adminReport;
      return ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            'Marketplace report',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          _ReportTile(
            label: 'Active listings',
            value: '${report['activeListings'] ?? 0}',
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(height: 10),
          _ReportTile(
            label: 'Account roles',
            value: (report['users'] as List<dynamic>? ?? const [])
                .map((row) => '${row['role']}: ${row['count']}')
                .join(' · '),
            icon: Icons.people_outline,
          ),
          const SizedBox(height: 10),
          _ReportTile(
            label: 'Order states',
            value: (report['ordersByStatus'] as List<dynamic>? ?? const [])
                .map((row) => '${row['status']}: ${row['count']}')
                .join(' · '),
            icon: Icons.receipt_long_outlined,
          ),
          const SizedBox(height: 14),
          const Text(
            'Reports are operational summaries only; review database access and privacy policy before exporting personal data.',
            style: TextStyle(
              color: Color(0xff707b76),
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      );
    }

    final vendors = controller.pendingVendors;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Text(
          'Marketplace administration',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(
          'Seller applications',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (vendors.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('There are no pending seller applications.'),
            ),
          ),
        for (final vendor in vendors)
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.storefront_outlined),
              ),
              title: Text(vendor['name'] as String? ?? 'Seller'),
              subtitle: Text(
                '${vendor['fullName'] ?? ''} · ${vendor['email'] ?? ''}',
              ),
              trailing: FilledButton(
                onPressed: controller.busy
                    ? null
                    : () => controller.approveVendor(vendor['id'] as String),
                child: const Text('Approve'),
              ),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'Product moderation',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final product in controller.adminProducts)
          Card(
            child: SwitchListTile(
              title: Text(product['name'] as String? ?? 'Product'),
              subtitle: Text(
                '${product['seller'] ?? ''} · ${product['category'] ?? ''} · ${product['active'] == true ? 'Visible' : 'Hidden'}',
              ),
              value: product['active'] == true,
              onChanged: controller.busy
                  ? null
                  : (active) => controller.setProductActive(
                      product['id'] as String,
                      active,
                    ),
            ),
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'Categories',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => _addCategory(context, controller),
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            ),
          ],
        ),
        for (final category in controller.adminCategories)
          Card(
            child: SwitchListTile(
              title: Text(category['name'] as String? ?? ''),
              subtitle: Text(category['active'] == true ? 'Active' : 'Hidden'),
              value: category['active'] == true,
              onChanged: controller.busy
                  ? null
                  : (active) => controller.setCategoryActive(
                      category['id'] as String,
                      active,
                    ),
            ),
          ),
        const SizedBox(height: 18),
        Text('User accounts', style: Theme.of(context).textTheme.titleMedium),
        for (final user in controller.adminUsers)
          Card(
            child: SwitchListTile(
              title: Text(
                user['fullName'] as String? ?? user['email'] as String? ?? '',
              ),
              subtitle: Text('${user['role']} · ${user['email']}'),
              value: user['active'] == true,
              onChanged: user['id'] == controller.user?.id || controller.busy
                  ? null
                  : (active) =>
                        controller.setUserActive(user['id'] as String, active),
            ),
          ),
      ],
    );
  }
}

Future<void> _addCategory(
  BuildContext context,
  MarketplaceController controller,
) async {
  final field = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add category'),
      content: TextField(
        controller: field,
        maxLength: 60,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Category name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, field.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  field.dispose();
  if (name != null && name.isNotEmpty) await controller.createCategory(name);
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, color: const Color(0xff12483b)),
      title: Text(label),
      subtitle: Text(value.isEmpty ? 'No records yet' : value),
    ),
  );
}
