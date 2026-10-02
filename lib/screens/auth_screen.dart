import 'package:flutter/material.dart';

import '../state/marketplace_controller.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final MarketplaceController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  String _role = 'buyer';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_registering) {
      await widget.controller.register(
        fullName: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        role: _role,
      );
      if (!mounted) return;
      if (widget.controller.error == null) {
        setState(() => _registering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _role == 'seller'
                  ? 'Account created. Seller access is pending administrator approval.'
                  : 'Account created. Sign in to continue.',
            ),
          ),
        );
      }
      return;
    }
    await widget.controller.signIn(_email.text.trim(), _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 740;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: wide
                  ? Row(
                      children: [
                        Expanded(child: _welcomePanel()),
                        Expanded(child: _formPanel()),
                      ],
                    )
                  : _formPanel(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcomePanel() => Container(
    constraints: const BoxConstraints(minHeight: 490),
    padding: const EdgeInsets.all(42),
    color: const Color(0xff12483b),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'gom.png',
          height: 58,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.local_pharmacy, size: 52, color: Colors.white),
        ),
        const SizedBox(height: 20),
        const Text(
          'PharmaGo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'A thoughtful marketplace for pharmacy essentials and everyday wellness.',
          style: TextStyle(color: Color(0xffe6efe8), fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 28),
        const _WelcomePoint(
          icon: Icons.search,
          label: 'Find trusted essentials',
        ),
        const _WelcomePoint(
          icon: Icons.storefront_outlined,
          label: 'Shop from approved sellers',
        ),
        const _WelcomePoint(
          icon: Icons.local_shipping_outlined,
          label: 'Follow your order',
        ),
      ],
    ),
  );

  Widget _formPanel() => Padding(
    padding: const EdgeInsets.all(32),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _registering ? 'Create your account' : 'Welcome back',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              _registering
                  ? 'Join PharmaGo as a buyer or apply to sell.'
                  : 'Sign in to browse and manage your PharmaGo orders.',
              style: const TextStyle(color: Color(0xff707b76), height: 1.5),
            ),
            const SizedBox(height: 24),
            if (_registering) ...[
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) =>
                    (value?.trim().length ?? 0) < 2 ? 'Enter your name.' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Account type'),
                items: const [
                  DropdownMenuItem(value: 'buyer', child: Text('Buyer')),
                  DropdownMenuItem(value: 'seller', child: Text('Seller')),
                ],
                onChanged: (value) => setState(() => _role = value ?? 'buyer'),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email address'),
              validator: (value) =>
                  value != null &&
                      RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(value.trim())
                  ? null
                  : 'Enter a valid email address.',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: [
                _registering
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _registering ? 'Use at least 15 characters.' : null,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Enter your password.';
                }
                if (_registering && value.length < 15) {
                  return 'Use a passphrase of at least 15 characters.';
                }
                if (value.length > 128) return 'Password is too long.';
                return null;
              },
            ),
            const SizedBox(height: 18),
            if (widget.controller.error != null) ...[
              Text(
                widget.controller.error!,
                style: const TextStyle(color: Color(0xffa52e24)),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: widget.controller.busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: widget.controller.busy
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_registering ? 'Create account' : 'Sign in'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _registering = !_registering),
              child: Text(
                _registering
                    ? 'Already registered? Sign in'
                    : 'New to PharmaGo? Create an account',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'For product safety, always read the product label and contact a pharmacist with questions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xff707b76),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WelcomePoint extends StatelessWidget {
  const _WelcomePoint({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xffc9ef62), size: 20),
        const SizedBox(width: 11),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}
