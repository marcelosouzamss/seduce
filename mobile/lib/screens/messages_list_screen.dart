import 'package:flutter/material.dart';

import '../models/message_thread.dart';
import '../services/client_identity.dart';
import '../services/message_threads_repository.dart';
import 'companion_chat_screen.dart';
import 'main_shell_screen.dart';

/// Lista de conversas (contatos). Abre o chat ao tocar.
class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final _repo = MessageThreadsRepository();
  List<MessageThread> _threads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final key = await ClientIdentity.ensureClientKey();
      final list = await _repo.list(clientKey: key);
      if (!mounted) return;
      setState(() {
        _threads = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar conversas: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mensagens')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _threads.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined, size: 56, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(
                          'Ainda não há conversas.',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Abra o chat a partir de um perfil em Buscar. As conversas são listadas pelo servidor.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.tonal(
                          onPressed: () {
                            MainShellScreen.tryState(context)?.goToBuscar();
                          },
                          child: const Text('Ir para Buscar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _threads.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
                    itemBuilder: (context, i) {
                      final t = _threads[i];
                      return ListTile(
                        leading: t.photoUrl.isEmpty
                            ? const CircleAvatar(child: Icon(Icons.person))
                            : CircleAvatar(
                                backgroundImage: NetworkImage(t.photoUrl),
                                onBackgroundImageError: (_, __) {},
                              ),
                        title: Text(
                          t.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          t.lastPreview ?? 'Toque para conversar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => CompanionChatScreen(
                                companionId: t.companionId,
                                displayName: t.displayName,
                                photoUrl: t.photoUrl,
                              ),
                            ),
                          );
                          _reload();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
