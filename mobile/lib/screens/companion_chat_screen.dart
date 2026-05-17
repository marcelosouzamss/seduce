import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/chat_repository.dart';
import '../services/client_identity.dart';

/// Chat com mensagens persistidas por [companionId] + cliente anônimo ([ClientIdentity]).
class CompanionChatScreen extends StatefulWidget {
  const CompanionChatScreen({
    super.key,
    required this.companionId,
    required this.displayName,
    required this.photoUrl,
    ChatRepository? chatRepository,
  }) : _chatRepo = chatRepository;

  final int companionId;
  final String displayName;
  final String photoUrl;
  final ChatRepository? _chatRepo;

  @override
  State<CompanionChatScreen> createState() => _CompanionChatScreenState();
}

class _CompanionChatScreenState extends State<CompanionChatScreen> {
  late final ChatRepository _repo =
      widget._chatRepo ?? ChatRepository();
  late final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  String? _clientKey;
  List<ChatMessage> _msgs = [];
  bool _booting = true;
  bool _sending = false;
  Timer? _poll;
  Object? _loadErr;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final key = await ClientIdentity.ensureClientKey();
      final first = await _repo.fetchMessages(
        companionId: widget.companionId,
        clientKey: key,
      );
      if (!mounted) return;
      setState(() {
        _clientKey = key;
        _msgs = first..sort((a, b) => a.id.compareTo(b.id));
        _booting = false;
        _loadErr = null;
      });
      _scrollToBottom();
      _poll = Timer.periodic(const Duration(seconds: 6), (_) => _pollNew());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadErr = e;
        _booting = false;
      });
    }
  }

  int _latestId() {
    if (_msgs.isEmpty) return 0;
    return _msgs.map((m) => m.id).reduce((a, b) => a > b ? a : b);
  }

  Future<void> _pollNew() async {
    final key = _clientKey;
    if (key == null || !_scroll.hasClients) return;
    try {
      final batch = await _repo.fetchMessages(
        companionId: widget.companionId,
        clientKey: key,
        afterId: _latestId(),
      );
      if (batch.isEmpty || !mounted) return;
      setState(() {
        final map = <int, ChatMessage>{for (final m in _msgs) m.id: m};
        for (final m in batch) {
          map[m.id] = m;
        }
        _msgs = map.values.toList()..sort((a, b) => a.id.compareTo(b.id));
      });
          _scrollToBottom();
    } catch (_) {
      /* silencioso no poll */
    }
  }

  Future<void> _send() async {
    final key = _clientKey;
    if (key == null || _sending) return;
    final t = _input.text.trim();
    if (t.isEmpty) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      final created = await _repo.sendMessage(
        companionId: widget.companionId,
        clientKey: key,
        text: t,
      );
      if (!mounted) return;
      setState(() {
        final map = <int, ChatMessage>{for (final m in _msgs) m.id: m};
        for (final m in created) {
          map[m.id] = m;
        }
        _msgs = map.values.toList()..sort((a, b) => a.id.compareTo(b.id));
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar: $e')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_booting) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.displayName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadErr != null || _clientKey == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.displayName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 48, color: cs.error),
                const SizedBox(height: 12),
                Text('Não foi possível abrir o chat.', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                FilledButton(onPressed: () {
                  setState(() {
                    _booting = true;
                    _loadErr = null;
                  });
                  _init();
                }, child: const Text('Tentar novamente')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 36,
                height: 36,
                child: Image.network(
                  widget.photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.person,
                    size: 22,
                    color: cs.onPrimary,
                  ),
                  loadingBuilder: (_, child, p) {
                    if (p == null) return child;
                    return Container(
                      alignment: Alignment.center,
                      color: cs.primaryContainer,
                      child: const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Mensagens salvas neste dispositivo',
                    style: TextStyle(fontSize: 11, color: cs.onPrimary.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Envie a primeira mensagem para iniciar a conversa.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _msgs.length,
                    itemBuilder: (context, index) {
                      final m = _msgs[index];
                      final mine = m.isCliente;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          child: Card(
                            color: mine ? cs.primaryContainer : cs.surfaceContainerHigh,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.body,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _timeLabel(m.sentAt),
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: cs.onSurface.withValues(alpha: 0.55),
                                        ),
                                  ),
                                  if (!mine)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        widget.displayName,
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Material(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Escreva uma mensagem…',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : _send,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(14),
                      ),
                      child: _sending
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime utc) {
    final local = utc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
