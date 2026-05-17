import 'package:flutter/material.dart';

import '../models/user_ad.dart';

/// Detalhe de um anúncio público (sem chat de acompanhante).
class UserAdDetailScreen extends StatelessWidget {
  const UserAdDetailScreen({
    super.key,
    required this.ad,
    required this.heroTag,
  });

  final UserAd ad;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                ad.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: heroTag,
                    child: Material(
                      child: ad.photoUrls.isNotEmpty
                          ? Image.network(
                              ad.photoUrls.first,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: cs.surfaceContainerHigh,
                                child: Icon(Icons.broken_image_outlined, color: cs.outline, size: 48),
                              ),
                            )
                          : ColoredBox(
                              color: cs.surfaceContainerHigh,
                              child: Icon(Icons.campaign_outlined, size: 80, color: cs.outline),
                            ),
                    ),
                  ),
                  if (ad.photoUrls.length > 1)
                    Positioned(
                      bottom: 48,
                      right: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            '${ad.photoUrls.length} fotos',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text(
                          'Anúncio',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ad.photoUrls.length > 1) ...[
                    SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: ad.photoUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.network(
                                ad.photoUrls[i],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => ColoredBox(color: cs.surfaceContainerHigh),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('${ad.age} anos')),
                      Chip(label: Text('R\$${ad.priceBrl.toStringAsFixed(0)}/h')),
                      Chip(
                        avatar: Icon(ad.hasLocation ? Icons.home : Icons.home_outlined, size: 16),
                        label: Text(ad.hasLocation ? 'Com local' : 'Sem local'),
                      ),
                      Chip(
                        avatar: Icon(ad.isProfessional ? Icons.verified : Icons.person_outline, size: 16),
                        label: Text(ad.isProfessional ? 'Profissional' : 'Não profissional'),
                      ),
                      Chip(label: Text(_genderLabel(ad.gender))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Endereço', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(ad.address, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 20),
                  Text('Descrição', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(ad.body, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _genderLabel(String g) {
    return switch (g) {
      'feminino' => 'Fem.',
      'masculino' => 'Masc.',
      'trans' => 'Trans.',
      _ => g,
    };
  }
}
