import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/user_profile_store.dart';

/// Configuração de conta: nome, tipo (cliente/profissional), idade e foto.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  AccountRole _role = AccountRole.cliente;
  String? _photoBase64;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await UserProfileStore.load();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = p.displayName;
      if (p.age != null) {
        _ageCtrl.text = '${p.age}';
      }
      _role = p.role;
      _photoBase64 = p.photoBase64;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 82,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 900000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imagem grande demais. Escolha outra ou comprima antes.'),
        ),
      );
      return;
    }
    setState(() {
      _photoBase64 = base64Encode(bytes);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ageParsed =
        _ageCtrl.text.trim().isEmpty ? null : int.tryParse(_ageCtrl.text.trim());
    final profile = UserProfile(
      displayName: _nameCtrl.text.trim(),
      role: _role,
      age: ageParsed,
      photoBase64: _photoBase64,
    );
    await UserProfileStore.save(profile);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dados guardados neste dispositivo.')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('A sua conta')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('A sua conta'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Estes dados ficam guardados só neste aparelho.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: CircleAvatar(
                      radius: 56,
                      backgroundColor: cs.primaryContainer,
                      backgroundImage: _photoBase64 != null
                          ? MemoryImage(base64Decode(_photoBase64!))
                          : null,
                      child: _photoBase64 == null
                          ? Icon(
                              Icons.add_a_photo_outlined,
                              size: 40,
                              color: cs.onPrimaryContainer,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Escolher foto da galeria'),
                  ),
                  if (_photoBase64 != null)
                    TextButton(
                      onPressed: () => setState(() => _photoBase64 = null),
                      child: Text(
                        'Remover foto',
                        style: TextStyle(color: cs.error),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome ou como prefere ser chamado',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) {
                  return 'Indique um nome';
                }
                if (t.length < 2) {
                  return 'Nome muito curto';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text('Sou', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<AccountRole>(
              segments: const [
                ButtonSegment(
                  value: AccountRole.cliente,
                  label: Text('Cliente'),
                  icon: Icon(Icons.person_search_outlined),
                ),
                ButtonSegment(
                  value: AccountRole.profissional,
                  label: Text('Profissional'),
                  icon: Icon(Icons.work_outline),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _ageCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: const InputDecoration(
                labelText: 'Idade (opcional)',
                hintText: 'Ex.: 28',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cake_outlined),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                if (n == null || n < 18 || n > 120) {
                  return 'Idade entre 18 e 120';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
