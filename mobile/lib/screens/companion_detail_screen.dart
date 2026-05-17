import 'package:flutter/material.dart';

import '../models/companion.dart';
import '../services/api_exceptions.dart';
import '../services/chat_repository.dart';
import '../services/companion_repository.dart';
import 'companion_chat_screen.dart';

class CompanionDetailScreen extends StatefulWidget {
  const CompanionDetailScreen({
    super.key,
    required this.initial,
    required this.repo,
    this.heroTag,
  });

  final Companion initial;
  final CompanionRepository repo;
  final Object? heroTag;

  static String genderLabelPt(String gender) =>
      switch (gender) {
        'feminino' => 'Feminino',
        'masculino' => 'Masculino',
        'trans' => 'Trans',
        _ => gender,
      };

  @override
  State<CompanionDetailScreen> createState() => _CompanionDetailScreenState();
}

class _CompanionDetailScreenState extends State<CompanionDetailScreen> {
  late final Future<Companion> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.repo.fetchById(widget.initial.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Companion>(
      future: _detailFuture,
      builder: (context, snap) {
        final c = snap.data ?? widget.initial;
        final ht = widget.heroTag;
        final img = AspectRatio(
          aspectRatio: 3 / 4,
          child: ht != null
              ? Hero(
                  tag: ht,
                  child: _Photo(url: c.photoUrl, fit: BoxFit.cover),
                )
              : _Photo(url: c.photoUrl, fit: BoxFit.cover),
        );

        final booting =
            snap.connectionState == ConnectionState.waiting && snap.data == null;

        if (booting) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(widget.initial.displayName),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          final err = snap.error;
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text('Erro'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      err is CompanionApiException
                          ? 'Erro HTTP (${err.statusCode})'
                          : 'Não foi possível carregar o perfil',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          bottomNavigationBar: Material(
            elevation: 12,
            color: Theme.of(context).colorScheme.surface,
            shadowColor: Colors.black26,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Enviar mensagem'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => CompanionChatScreen(
                            companionId: c.id,
                            displayName: c.displayName,
                            photoUrl: c.photoUrl,
                            chatRepository:
                                ChatRepository(baseUrl: widget.repo.baseUrl),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Conversa anônima neste aparelho. Resposta automática só na primeira mensagem.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: MediaQuery.of(context).size.shortestSide * 0.9,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: img,
                  titlePadding:
                      const EdgeInsetsDirectional.only(start: 48, bottom: 12),
                  title: Text(
                    c.displayName,
                    style: TextStyle(
                      shadows: [
                        Shadow(
                          blurRadius: 8,
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.cake_outlined, size: 18),
                            label: Text('${c.age} anos'),
                          ),
                          Chip(
                            avatar:
                                const Icon(Icons.location_on_outlined, size: 18),
                            label: Text('${c.distanceKm.toStringAsFixed(1)} km'),
                          ),
                          Chip(
                            avatar: const Icon(Icons.wc_outlined, size: 18),
                            label:
                                Text(CompanionDetailScreen.genderLabelPt(c.gender)),
                          ),
                          Chip(
                            avatar: Icon(
                              c.hasLocation ? Icons.home : Icons.directions_walk,
                              size: 18,
                            ),
                            label: Text(c.hasLocation ? 'Tem local' : 'Sem local'),
                          ),
                          Chip(
                            avatar: Icon(
                              c.isProfessional
                                  ? Icons.verified_outlined
                                  : Icons.person_outline,
                              size: 18,
                            ),
                            label: Text(c.isProfessional
                                ? 'Profissional'
                                : 'Independente'),
                          ),
                          Chip(
                            avatar: const Icon(Icons.payments_outlined, size: 18),
                            label: Text(
                              'R\$ ${c.hourlyRateBrl.round()}/h',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(c.city, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Text(
                        'Sobre',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.bio.isEmpty ? 'Sem descrição.' : c.bio,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      width: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded /
                    progress.expectedTotalBytes!
                : null,
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person_off_outlined,
            size: 64, color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}
