import 'package:flutter/material.dart';

import '../models/payment_methods.dart';
import '../services/client_identity.dart';
import '../services/payment_methods_repository.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _repo = PaymentMethodsRepository();
  final _pixCtrl = TextEditingController();
  final _btcCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final key = await ClientIdentity.ensureClientKey();
      final p = await _repo.get(clientKey: key);
      if (!mounted) return;
      setState(() {
        _pixCtrl.text = p.pixKey ?? '';
        _btcCtrl.text = p.bitcoinAddress ?? '';
        _cardCtrl.text = p.creditCardNote ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar dados: $e')),
      );
    }
  }

  @override
  void dispose() {
    _pixCtrl.dispose();
    _btcCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final key = await ClientIdentity.ensureClientKey();
      await _repo.put(
        clientKey: key,
        methods: PaymentMethods(
          pixKey: _pixCtrl.text.trim().isEmpty ? null : _pixCtrl.text.trim(),
          bitcoinAddress: _btcCtrl.text.trim().isEmpty ? null : _btcCtrl.text.trim(),
          creditCardNote: _cardCtrl.text.trim().isEmpty ? null : _cardCtrl.text.trim(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados guardados no servidor (chave anónima).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao guardar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pagamentos')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Cadastre como recebe pagamentos. Os dados são associados à sua chave anónima no servidor — não armazene número completo de cartão.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _pixCtrl,
            decoration: const InputDecoration(
              labelText: 'Chave Pix',
              hintText: 'E-mail, telefone, EVP ou CPF/CNPJ',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.pix_outlined),
            ),
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _btcCtrl,
            decoration: const InputDecoration(
              labelText: 'Carteira Bitcoin',
              hintText: 'Endereço BTC (rede desejada)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.currency_bitcoin),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cardCtrl,
            decoration: const InputDecoration(
              labelText: 'Cartão de crédito',
              hintText: 'Últimos 4 dígitos ou apelido (não guarde PAN completo)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.credit_card_outlined),
            ),
            keyboardType: TextInputType.text,
            maxLength: 40,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _save,
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
