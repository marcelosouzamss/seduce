import 'package:flutter/material.dart';

import '../models/ranking_entry.dart';
import '../services/client_identity.dart';
import '../services/rankings_repository.dart';

/// Avaliações 1–5 estrelas com relatos (servidor).
class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final _repo = RankingsRepository();
  bool _profissionais = true;
  List<RankingEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final list = await _repo.list(isProfessional: _profissionais);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar rankings: $e')),
      );
    }
  }

  Future<void> _openNovaAvaliacao() async {
    final nameCtrl = TextEditingController();
    final relatoCtrl = TextEditingController();
    var estrelas = 5;
    var tipoPro = _profissionais;

    final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (ctx2, setM) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 8,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Nova avaliação', style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: true, label: Text('Profissional')),
                            ButtonSegment(value: false, label: Text('Cliente')),
                          ],
                          selected: {tipoPro},
                          onSelectionChanged: (s) => setM(() => tipoPro = s.first),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nome ou apelido',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text('Estrelas: ', style: Theme.of(ctx).textTheme.titleSmall),
                            Expanded(
                              child: Slider(
                                value: estrelas.toDouble(),
                                min: 1,
                                max: 5,
                                divisions: 4,
                                label: '$estrelas',
                                onChanged: (v) => setM(() => estrelas = v.round()),
                              ),
                            ),
                            Text('$estrelas', style: Theme.of(ctx).textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: relatoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Relato / comentário',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          minLines: 2,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () {
                            if (nameCtrl.text.trim().length < 2) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Indique um nome')),
                              );
                              return;
                            }
                            if (relatoCtrl.text.trim().length < 4) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Escreva um relato')),
                              );
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('Publicar na API'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ) ??
        false;

    if (!ok || !mounted) {
      nameCtrl.dispose();
      relatoCtrl.dispose();
      return;
    }

    try {
      final key = await ClientIdentity.ensureClientKey();
      await _repo.submit(
        clientKey: key,
        name: nameCtrl.text.trim(),
        isProfessional: tipoPro,
        stars: estrelas,
        testimonial: relatoCtrl.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao publicar: $e')),
        );
      }
      nameCtrl.dispose();
      relatoCtrl.dispose();
      return;
    }
    nameCtrl.dispose();
    relatoCtrl.dispose();
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avaliação enviada ao servidor.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final items = _entries;

    return Scaffold(
      appBar: AppBar(title: const Text('Rankings')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNovaAvaliacao,
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Avaliar'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Profissionais')),
                ButtonSegment(value: false, label: Text('Clientes')),
              ],
              selected: {_profissionais},
              onSelectionChanged: (s) {
                setState(() => _profissionais = s.first);
                _reload(quiet: true);
              },
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'Sem entradas nesta categoria.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  ...List.generate(
                                    5,
                                    (j) => Icon(
                                      j < e.stars ? Icons.star : Icons.star_border,
                                      size: 18,
                                      color: j < e.stars ? Colors.amber.shade700 : cs.outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                e.testimonial,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
