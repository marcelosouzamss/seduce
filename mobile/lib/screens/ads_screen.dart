import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../models/user_ad.dart';
import '../services/client_identity.dart';
import '../services/user_ads_repository.dart';

class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key});

  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _PendingPhoto {
  _PendingPhoto({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

class _AdsScreenState extends State<AdsScreen> {
  final _repo = UserAdsRepository();
  final _picker = ImagePicker();
  List<UserAd> _ads = [];
  bool _loading = true;

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _ageCtrl = TextEditingController(text: '25');
  final _priceCtrl = TextEditingController(text: '200');
  final _addressCtrl = TextEditingController();
  String _gender = 'feminino';
  bool _hasLocation = false;
  bool _isProfessional = false;
  /// Posição escolhida no mapa quando «Tem local» está ativo.
  LatLng? _draftMapPin;
  final List<_PendingPhoto> _pendingPhotos = [];
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _ageCtrl.dispose();
    _priceCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final key = await ClientIdentity.ensureClientKey();
      final list = await _repo.list(clientKey: key);
      if (!mounted) return;
      setState(() {
        _ads = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar anúncios: $e')),
      );
    }
  }

  Future<void> _openEditor() async {
    _titleCtrl.clear();
    _bodyCtrl.clear();
    _ageCtrl.text = '25';
    _priceCtrl.text = '200';
    _addressCtrl.clear();
    _gender = 'feminino';
    _hasLocation = false;
    _isProfessional = false;
    _draftMapPin = null;
    _pendingPhotos.clear();

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
                        Text('Novo anúncio', style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 96,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (var i = 0; i < _pendingPhotos.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          _pendingPhotos[i].bytes,
                                          width: 96,
                                          height: 96,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: IconButton.filledTonal(
                                          iconSize: 20,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                          onPressed: () {
                                            setM(() => _pendingPhotos.removeAt(i));
                                          },
                                          icon: const Icon(Icons.close),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Material(
                                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  onTap: () async {
                                    if (_pendingPhotos.length >= 8) return;
                                    final xf = await _picker.pickImage(source: ImageSource.gallery);
                                    if (xf == null) return;
                                    final b = await xf.readAsBytes();
                                    setM(() {
                                      _pendingPhotos.add(_PendingPhoto(bytes: b, filename: xf.name));
                                    });
                                  },
                                  child: SizedBox(
                                    width: 96,
                                    height: 96,
                                    child: Icon(
                                      Icons.add_photo_alternate_outlined,
                                      color: Theme.of(ctx).colorScheme.primary,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Adicione de 1 a 8 fotos.',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Título do anúncio',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _bodyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Descrição',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          minLines: 3,
                          maxLines: 8,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _ageCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Idade',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _priceCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Preço (R\$/h)',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _addressCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Endereço / região',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 12),
                        Text('Gênero', style: Theme.of(ctx).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'feminino', label: Text('Fem.')),
                            ButtonSegment(value: 'masculino', label: Text('Masc.')),
                            ButtonSegment(value: 'trans', label: Text('Trans.')),
                          ],
                          selected: {_gender},
                          onSelectionChanged: (s) => setM(() => _gender = s.first),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Tem local para atendimento'),
                          value: _hasLocation,
                          onChanged: (v) => setM(() {
                            _hasLocation = v;
                            if (!v) _draftMapPin = null;
                          }),
                        ),
                        if (_hasLocation) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final choice = await openAdLocationPicker(
                                ctx2,
                                initial: _draftMapPin,
                              );
                              if (choice != null) {
                                setM(() => _draftMapPin = choice);
                              }
                            },
                            icon: const Icon(Icons.map_outlined),
                            label: Text(
                              _draftMapPin == null
                                  ? 'Marcar local no mapa'
                                  : 'Ajustar local no mapa',
                            ),
                          ),
                          if (_draftMapPin != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Coordenadas: ${_draftMapPin!.latitude.toStringAsFixed(5)}, '
                                '${_draftMapPin!.longitude.toStringAsFixed(5)}',
                                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                        ],
                        SwitchListTile(
                          title: const Text('Perfil profissional'),
                          value: _isProfessional,
                          onChanged: (v) => setM(() => _isProfessional = v),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            if (_pendingPhotos.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Adicione pelo menos uma foto.')),
                              );
                              return;
                            }
                            if (_titleCtrl.text.trim().length < 2) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Título muito curto')),
                              );
                              return;
                            }
                            if (_bodyCtrl.text.trim().length < 4) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Descreva o anúncio')),
                              );
                              return;
                            }
                            final age = int.tryParse(_ageCtrl.text.trim());
                            if (age == null || age < 18 || age > 99) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Idade entre 18 e 99')),
                              );
                              return;
                            }
                            final price = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.'));
                            if (price == null || price <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Preço inválido')),
                              );
                              return;
                            }
                            if (_addressCtrl.text.trim().length < 3) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Indique endereço ou região')),
                              );
                              return;
                            }
                            if (_hasLocation && _draftMapPin == null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Marque o local no mapa — ou desative «Tem local».',
                                  ),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('Publicar'),
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

    if (!ok || !mounted) return;

    setState(() => _publishing = true);
    try {
      final key = await ClientIdentity.ensureClientKey();
      final urls = <String>[];
      for (final p in _pendingPhotos) {
        final u = await _repo.uploadPhoto(
          clientKey: key,
          bytes: p.bytes,
          filename: p.filename,
        );
        urls.add(u);
      }
      await _repo.add(
        clientKey: key,
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        gender: _gender,
        age: int.parse(_ageCtrl.text.trim()),
        priceBrl: double.parse(_priceCtrl.text.trim().replaceAll(',', '.')),
        hasLocation: _hasLocation,
        isProfessional: _isProfessional,
        address: _addressCtrl.text.trim(),
        photoUrls: urls,
        latitude: _hasLocation ? _draftMapPin?.latitude : null,
        longitude: _hasLocation ? _draftMapPin?.longitude : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao publicar: $e')),
        );
      }
      setState(() => _publishing = false);
      return;
    }
    if (!mounted) return;
    setState(() => _publishing = false);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anúncio publicado. Aparece na aba Buscar.')),
      );
    }
  }

  Future<void> _confirmRemove(UserAd ad) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover anúncio?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (r != true || !mounted) return;
    try {
      final key = await ClientIdentity.ensureClientKey();
      await _repo.remove(clientKey: key, id: ad.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao remover: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Anúncios')),
          floatingActionButton: _publishing
              ? null
              : FloatingActionButton.extended(
                  onPressed: _openEditor,
                  icon: const Icon(Icons.add),
                  label: const Text('Criar'),
                ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _ads.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nenhum anúncio ainda. Toque em Criar — com fotos, preço e dados — e aparecerá em Buscar.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _ads.length,
                      itemBuilder: (context, i) {
                        final ad = _ads[i];
                        final noMapPin =
                            ad.hasLocation && (ad.latitude == null || ad.longitude == null);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            isThreeLine: true,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: ad.coverPhotoUrl.isNotEmpty
                                    ? Image.network(
                                        ad.coverPhotoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.campaign_outlined),
                                      )
                                    : const ColoredBox(
                                        color: Colors.black12,
                                        child: Icon(Icons.campaign_outlined),
                                      ),
                              ),
                            ),
                            title: Text(ad.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'R\$${ad.priceBrl.round()}/h · ${ad.age} anos · '
                              '${ad.hasLocation ? ((ad.latitude != null && ad.longitude != null) ? "com local (mapa)" : "com local") : "sem local"}'
                              '${noMapPin ? " · sem posição no mapa" : ""} · '
                              '${ad.isProfessional ? "profissional" : "não profissional"}\n'
                              '${ad.body}\n'
                              '${DateTime.fromMillisecondsSinceEpoch(ad.createdAtMs).toLocal()}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmRemove(ad),
                            ),
                          ),
                        );
                      },
                    ),
        ),
        if (_publishing)
          const ColoredBox(
            color: Color(0x66000000),
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('A enviar fotos…'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<LatLng?> openAdLocationPicker(BuildContext context, {LatLng? initial}) {
  return Navigator.of(context).push<LatLng?>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => _AdLocationPickerPage(initial: initial),
    ),
  );
}

class _AdLocationPickerPage extends StatefulWidget {
  const _AdLocationPickerPage({this.initial});

  final LatLng? initial;

  @override
  State<_AdLocationPickerPage> createState() => _AdLocationPickerPageState();
}

class _AdLocationPickerPageState extends State<_AdLocationPickerPage> {
  static const LatLng _fallback = LatLng(-23.5505, -46.6333);
  late LatLng _pin;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _pin = widget.initial ?? _fallback;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryCenterOnUser());
  }

  Future<void> _tryCenterOnUser() async {
    if (widget.initial != null) return;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled || !mounted) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever ||
          !mounted) {
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _pin = LatLng(p.latitude, p.longitude);
      });
      _mapController.move(_pin, 14);
    } catch (_) {}
  }

  Future<void> _useMyLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ative os serviços de localização.')),
          );
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissão de localização negada.')),
          );
        }
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() => _pin = LatLng(p.latitude, p.longitude));
      _mapController.move(_pin, 15);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível usar a sua posição.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop<LatLng>(_pin);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop<LatLng?>(),
        ),
        title: const Text('Local no mapa'),
        actions: [
          IconButton(
            tooltip: 'Minha posição',
            onPressed: _useMyLocation,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _pin,
                initialZoom: widget.initial != null ? 15 : 12,
                onTap: (_, latLng) => setState(() => _pin = latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.seduce.seduce_mobile',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pin,
                      width: 48,
                      height: 48,
                      alignment: Alignment.bottomCenter,
                      child: Icon(Icons.location_on, color: cs.primary, size: 44),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: cs.surfaceContainerLow,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Toque no mapa para mover o marcador. Confirme quando estiver correto.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop<LatLng?>(),
                          child: const Text('Cancelar'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _confirm,
                          child: const Text('Usar este local'),
                        ),
                      ],
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
}
