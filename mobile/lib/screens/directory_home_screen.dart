import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import '../models/companion.dart';
import '../models/directory_entry.dart';
import '../models/user_ad.dart';
import '../services/companion_repository.dart';
import '../services/user_ads_repository.dart';
import '../services/user_profile_store.dart';
import 'account_settings_screen.dart';
import 'companion_detail_screen.dart';
import 'user_ad_detail_screen.dart';

LatLng? _directoryEntryLatLng(DirectoryEntry e) {
  if (e.isAd) {
    final a = e.ad!;
    final lat = a.latitude;
    final lng = a.longitude;
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }
  final c = e.companion!;
  final lat = c.latitude;
  final lng = c.longitude;
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

/// Descoberta com chips rápidos + bottom sheet tipo apps de redes sociais/marketplaces.
class DirectoryHomeScreen extends StatefulWidget {
  const DirectoryHomeScreen({super.key});

  @override
  State<DirectoryHomeScreen> createState() => _DirectoryHomeScreenState();
}

class _DirectoryHomeScreenState extends State<DirectoryHomeScreen> {
  final CompanionRepository _repo = CompanionRepository();
  final UserAdsRepository _adsRepo = UserAdsRepository();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _reloadDebounce;

  double _maxDistanceKm = 50;
  RangeValues _ageRange = const RangeValues(18, 60);
  String _genderKey = 'todos';
  TriFilter _hasLocationFilter = TriFilter.any;
  TriFilter _professionalFilter = TriFilter.any;
  double? _hourlyPriceMinBrl;
  double? _hourlyPriceMaxBrl;

  /// Ver mapa em vez da grelha; o botão ao lado de «ajustes finos» alterna o modo.
  bool _directoryMapMode = false;

  List<DirectoryEntry> _directory = [];
  bool _loading = true;
  String? _error;

  UserProfile _accountProfile = const UserProfile();
  static const Map<String, String> _genderOptions = {
    'todos': 'Todos',
    'feminino': 'Fem.',
    'masculino': 'Masc.',
    'trans': 'Trans.',
  };

  static const List<double> _distanceSelectKm = [5, 10, 15, 25, 35, 50];

  static final List<({String key, RangeValues range, String label})> _agePresets = [
    (key: '1828', range: const RangeValues(18, 28), label: '18–28'),
    (key: '2636', range: const RangeValues(26, 36), label: '26–36'),
    (key: '3245', range: const RangeValues(32, 45), label: '32–45'),
    (key: '4260', range: const RangeValues(42, 60), label: '42+'),
    (key: 'livre', range: const RangeValues(18, 60), label: '18–60 (livre)'),
  ];

  static final List<({String key, double? min, double? max, String label})> _pricePresets = [
    (key: 'none', min: null, max: null, label: 'Todos'),
    (key: 'p150', min: null, max: 150, label: 'Até R\$150'),
    (key: 'p350', min: null, max: 350, label: 'Até R\$350'),
    (key: 'r350650', min: 350, max: 650, label: 'R\$350–650'),
    (key: 'p650', min: 650, max: null, label: 'R\$650+'),
  ];

  double _snapDistanceToPreset(double km) {
    var best = _distanceSelectKm.first;
    for (final d in _distanceSelectKm) {
      if ((km - d).abs() < (km - best).abs()) {
        best = d;
      }
    }
    return best;
  }

  String _ageKeyForRange() {
    for (final p in _agePresets) {
      if ((_ageRange.start - p.range.start).abs() < 0.6 &&
          (_ageRange.end - p.range.end).abs() < 0.6) {
        return p.key;
      }
    }
    return '__other__';
  }

  String _priceKeyForState() {
    for (final p in _pricePresets) {
      if (_sameBound(_hourlyPriceMinBrl, p.min) && _sameBound(_hourlyPriceMaxBrl, p.max)) {
        return p.key;
      }
    }
    return '__other__';
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _loadAccountProfile();
    _load(immediate: true);
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccountProfile() async {
    final p = await UserProfileStore.load();
    if (!mounted) return;
    setState(() => _accountProfile = p);
  }

  Widget _accountAvatar(ColorScheme cs) {
    final b64 = _accountProfile.photoBase64;
    ImageProvider? provider;
    if (b64 != null && b64.isNotEmpty) {
      try {
        provider = MemoryImage(base64Decode(b64));
      } catch (_) {
        provider = null;
      }
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: cs.primaryContainer,
      foregroundImage: provider,
      child: provider == null
          ? Icon(
              Icons.person_rounded,
              color: cs.onPrimaryContainer,
              size: 20,
            )
          : null,
    );
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
    await _loadAccountProfile();
  }

  int _extrasActiveCount() {
    int n = 0;
    if (_maxDistanceKm < 49.9) n++;
    if (_ageRange.start > 17.9 || _ageRange.end < 59.9) n++;
    if (_genderKey != 'todos') n++;
    if (_hasLocationFilter != TriFilter.any) n++;
    if (_professionalFilter != TriFilter.any) n++;
    if (_hourlyPriceMinBrl != null || _hourlyPriceMaxBrl != null) n++;
    return n;
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 380), () {
      if (!mounted) return;
      _load(immediate: true);
    });
  }

  Future<void> _load({bool immediate = false}) async {
    if (immediate && _reloadDebounce?.isActive == true) {
      _reloadDebounce?.cancel();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Companion> companions = [];
      List<UserAd> ads = [];
      Object? loadErr;
      try {
        companions = await _repo.fetchFiltered(
          maxDistanceKm: _maxDistanceKm,
          gender: _genderKey == 'todos' ? null : _genderKey,
          minAge: _ageRange.start.round(),
          maxAge: _ageRange.end.round(),
          hasLocationFilter: _hasLocationFilter,
          professionalFilter: _professionalFilter,
          minHourlyRateBrl: _hourlyPriceMinBrl,
          maxHourlyRateBrl: _hourlyPriceMaxBrl,
        );
      } catch (e) {
        loadErr = e;
      }
      try {
        ads = await _adsRepo.fetchPublic(
          maxDistanceKm: _maxDistanceKm,
          gender: _genderKey == 'todos' ? null : _genderKey,
          minAge: _ageRange.start.round(),
          maxAge: _ageRange.end.round(),
          hasLocationFilter: _hasLocationFilter,
          professionalFilter: _professionalFilter,
          minHourlyRateBrl: _hourlyPriceMinBrl,
          maxHourlyRateBrl: _hourlyPriceMaxBrl,
        );
      } catch (_) {
        /* anúncios são opcionais */
      }
      if (!mounted) return;
      final merged = DirectoryEntry.mergeLists(companions, ads);
      setState(() {
        _directory = merged;
        _loading = false;
        _error = loadErr != null && merged.isEmpty ? '$loadErr' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _resetFilters() {
    setState(() {
      _maxDistanceKm = 50;
      _ageRange = const RangeValues(18, 60);
      _genderKey = 'todos';
      _hasLocationFilter = TriFilter.any;
      _professionalFilter = TriFilter.any;
      _hourlyPriceMinBrl = null;
      _hourlyPriceMaxBrl = null;
      _searchCtrl.clear();
    });
    _scheduleReload();
  }

  List<DirectoryEntry> _visibleDirectory() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      return _directory;
    }
    return _directory.where((e) {
      if (e.isAd) {
        final a = e.ad!;
        return a.title.toLowerCase().contains(q) ||
            a.address.toLowerCase().contains(q) ||
            a.body.toLowerCase().contains(q);
      }
      final c = e.companion!;
      return c.displayName.toLowerCase().contains(q) ||
          c.city.toLowerCase().contains(q) ||
          c.bio.toLowerCase().contains(q);
    }).toList();
  }

  bool _sameBound(double? a, double? b) =>
      (a == null && b == null) || (a != null && b != null && (a - b).abs() < 0.01);

  Widget _profileGenderRow() {
    final cs = Theme.of(context).colorScheme;
    const keys = <String>['feminino', 'masculino', 'trans'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Perfil',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 10),
            for (final k in keys) ...[
              FilterChip(
                label: Text(_genderOptions[k]!),
                selected: _genderKey == k,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _toggleGenderFilter(k),
              ),
              const SizedBox(width: 6),
            ],
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() => _directoryMapMode = !_directoryMapMode),
              child: Text(
                _directoryMapMode ? 'Exibir lista' : 'Explorar no mapa',
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Ajustes finos',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: Icon(Icons.tune_rounded, color: cs.primary, size: 24),
              onPressed: _openTuneSheet,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleGenderFilter(String key) {
    setState(() {
      if (_genderKey == key) {
        _genderKey = 'todos';
      } else {
        _genderKey = key;
      }
    });
    _scheduleReload();
  }

  String _distanceSummaryDisplay() {
    final d = _snapDistanceToPreset(_maxDistanceKm);
    return '≤${d.round()} km';
  }

  String _ageSummaryDisplay() {
    final key = _ageKeyForRange();
    if (key != '__other__') {
      return _agePresets.firstWhere((p) => p.key == key).label;
    }
    return '${_ageRange.start.round()}–${_ageRange.end.round()} anos';
  }

  String _priceSummaryDisplay() {
    final key = _priceKeyForState();
    if (key != '__other__') {
      return _pricePresets.firstWhere((p) => p.key == key).label;
    }
    final minB = _hourlyPriceMinBrl;
    final maxB = _hourlyPriceMaxBrl;
    if (minB == null && maxB != null) {
      return 'Até R\$${maxB.round()}';
    }
    if (minB != null && maxB != null) {
      return 'R\$${minB.round()}–${maxB.round()}';
    }
    if (minB != null && maxB == null) {
      return '≥ R\$${minB.round()}';
    }
    return 'Personalizado';
  }

  Future<void> _showDistanceEditorModal() async {
    var km = _maxDistanceKm;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setM) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).padding.bottom + 20,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Distância máxima', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text(
                    'Mostrar até ${km.round()} km',
                    style: Theme.of(ctx).textTheme.bodyLarge,
                  ),
                  Slider(
                    value: km.clamp(1, 50),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${km.round()} km',
                    onChanged: (v) => setM(() => km = v),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _distanceSelectKm.map((d) {
                      return ChoiceChip(
                        label: Text('≤${d.round()} km'),
                        selected: (km - d).abs() < 0.6,
                        onSelected: (_) => setM(() => km = d),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _maxDistanceKm = km);
                      _scheduleReload();
                    },
                    child: const Text('Aplicar'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAgeEditorModal() async {
    var ages = _ageRange;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setM) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).padding.bottom + 20,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Faixa de idade', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  RangeSlider(
                    values: ages,
                    min: 18,
                    max: 60,
                    divisions: 42,
                    labels: RangeLabels(
                      '${ages.start.round()}',
                      '${ages.end.round()}',
                    ),
                    onChanged: (v) => setM(() => ages = v),
                  ),
                  Text(
                    '${ages.start.round()} – ${ages.end.round()} anos',
                    style: Theme.of(ctx).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _ageRange = ages);
                      _scheduleReload();
                    },
                    child: const Text('Aplicar'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openTuneSheet();
                    },
                    child: const Text('Mais opções nos ajustes finos'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPriceEditorModal() async {
    var pxMin = _hourlyPriceMinBrl;
    var pxMax = _hourlyPriceMaxBrl;
    final limitCtrl = TextEditingController(
      text: (pxMin == null && pxMax != null) ? pxMax.round().toString() : '',
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setM) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                top: 8,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Valor da hora (R\$)', style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: pxMin == null && pxMax == null,
                          onSelected: (_) => setM(() {
                            pxMin = null;
                            pxMax = null;
                            limitCtrl.clear();
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Até 150'),
                          selected:
                              pxMin == null && pxMax != null && (pxMax! - 150).abs() < 0.01,
                          onSelected: (_) => setM(() {
                            pxMin = null;
                            pxMax = 150;
                            limitCtrl.text = '150';
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('Até 350'),
                          selected:
                              pxMin == null && pxMax != null && (pxMax! - 350).abs() < 0.01,
                          onSelected: (_) => setM(() {
                            pxMin = null;
                            pxMax = 350;
                            limitCtrl.text = '350';
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('350–650'),
                          selected: pxMin != null &&
                              (pxMin! - 350).abs() < 0.01 &&
                              pxMax != null &&
                              (pxMax! - 650).abs() < 0.01,
                          onSelected: (_) => setM(() {
                            pxMin = 350;
                            pxMax = 650;
                            limitCtrl.clear();
                          }),
                        ),
                        ChoiceChip(
                          label: const Text('650+'),
                          selected: pxMin != null && (pxMin! - 650).abs() < 0.01 && pxMax == null,
                          onSelected: (_) => setM(() {
                            pxMin = 650;
                            pxMax = null;
                            limitCtrl.clear();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Teto personalizado (R\$/h)',
                      style: Theme.of(ctx).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: limitCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        hintText: 'Ex.: 480',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        final raw = limitCtrl.text.trim();
                        if (raw.isNotEmpty) {
                          final n = int.tryParse(raw);
                          if (n != null && n > 0) {
                            pxMin = null;
                            pxMax = n.toDouble();
                          }
                        }
                        Navigator.pop(ctx);
                        setState(() {
                          _hourlyPriceMinBrl = pxMin;
                          _hourlyPriceMaxBrl = pxMax;
                        });
                        _scheduleReload();
                      },
                      child: const Text('Aplicar'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openTuneSheet();
                      },
                      child: const Text('Abrir ajustes finos completos'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(limitCtrl.dispose);
  }

  Widget _secondaryFiltersRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterEditorTile(
            label: 'Distância',
            valueText: _distanceSummaryDisplay(),
            onTap: () => _showDistanceEditorModal(),
          ),
          _filterEditorTile(
            label: 'Idade',
            valueText: _ageSummaryDisplay(),
            onTap: () => _showAgeEditorModal(),
          ),
          _filterEditorTile(
            label: 'Preço',
            valueText: _priceSummaryDisplay(),
            onTap: () => _showPriceEditorModal(),
          ),
        ],
      ),
    );
  }

  Widget _filterEditorTile({
    required String label,
    required String valueText,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: cs.surfaceContainerHighest,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: cs.outline.withValues(alpha: 0.25)),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Icon(Icons.expand_more, size: 18, color: cs.outline),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    valueText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _exploreFiltersBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profileGenderRow(),
        _secondaryFiltersRow(),
      ],
    );
  }

  Widget _extrasRowFixed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _menuTri(
            label: 'Tem local?',
            icon: Icons.home_outlined,
            current: _hasLocationFilter,
            onChanged: (v) => setState(() => _hasLocationFilter = v),
          ),
          _menuTri(
            label: 'Profissional?',
            icon: Icons.verified_outlined,
            current: _professionalFilter,
            onChanged: (v) => setState(() => _professionalFilter = v),
          ),
          if (_extrasActiveCount() > 0)
            TextButton(onPressed: _resetFilters, child: const Text('Limpar filtros')),
        ],
      ),
    );
  }

  Widget _menuTri({
    required String label,
    required IconData icon,
    required TriFilter current,
    required ValueChanged<TriFilter> onChanged,
  }) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () {
            onChanged(TriFilter.any);
            _scheduleReload();
          },
          child: const Text('Qualquer um'),
        ),
        MenuItemButton(
          onPressed: () {
            onChanged(TriFilter.yes);
            _scheduleReload();
          },
          child: const Text('Sim'),
        ),
        MenuItemButton(
          onPressed: () {
            onChanged(TriFilter.no);
            _scheduleReload();
          },
          child: const Text('Não'),
        ),
      ],
      builder: (ctx2, ctrl, _) {
        return FilterChip(
          avatar: Icon(icon, size: 18),
          label: Text('$label • ${_triLabelPt(current)}'),
          selected: current != TriFilter.any,
          visualDensity: VisualDensity.compact,
          onSelected: (_) {
            if (ctrl.isOpen) {
              ctrl.close();
            } else {
              ctrl.open();
            }
          },
        );
      },
    );
  }

  static String _triLabelPt(TriFilter t) =>
      switch (t) {
        TriFilter.any => 'todos',
        TriFilter.yes => 'sim',
        TriFilter.no => 'não',
      };

  Future<void> _openTuneSheet() async {
    var km = _maxDistanceKm;
    var ages = _ageRange;
    var gen = _genderKey;
    var loc = _hasLocationFilter;
    var prof = _professionalFilter;
    var pxMin = _hourlyPriceMinBrl;
    var pxMax = _hourlyPriceMaxBrl;

    final limitCtrl = TextEditingController(
      text: (pxMin == null && pxMax != null) ? pxMax.round().toString() : '',
    );

    void applyCustomLimitFieldToState() {
      final raw = limitCtrl.text.trim();
      if (raw.isEmpty) {
        return;
      }
      final n = int.tryParse(raw);
      if (n != null && n > 0) {
        pxMin = null;
        pxMax = n.toDouble();
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx2, setM) {
            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  Text('Ajustes finos',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Defina filtros como em apps de busca próximos a você.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const Divider(height: 28),
                  Text('Raio até', style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    '${km.round()} km',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Slider(
                    value: km,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${km.round()} km',
                    onChanged: (v) => setM(() => km = v),
                  ),
                  const SizedBox(height: 8),
                  Text('Idade', style: Theme.of(context).textTheme.titleSmall),
                  RangeSlider(
                    values: ages,
                    min: 18,
                    max: 60,
                    divisions: 42,
                    labels: RangeLabels(
                      '${ages.start.round()}',
                      '${ages.end.round()}',
                    ),
                    onChanged: (v) => setM(() => ages = v),
                  ),
                  Text(
                    '${ages.start.round()} – ${ages.end.round()} anos',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Divider(height: 28),
                  Text('Gênero', style: Theme.of(context).textTheme.titleSmall),
                  DropdownButtonFormField<String>(
                    value: gen,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      filled: true,
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos os gêneros')),
                      DropdownMenuItem(value: 'feminino', child: Text('Feminino')),
                      DropdownMenuItem(value: 'masculino', child: Text('Masculino')),
                      DropdownMenuItem(value: 'trans', child: Text('Trans')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setM(() => gen = v);
                      }
                    },
                  ),
                  const Divider(height: 28),
                  Text('Tem local?', style: Theme.of(context).textTheme.titleSmall),
                  SegmentedButton<TriFilter>(
                    segments: const [
                      ButtonSegment(value: TriFilter.any, label: Text('Qualquer')),
                      ButtonSegment(value: TriFilter.yes, label: Text('Sim')),
                      ButtonSegment(value: TriFilter.no, label: Text('Não')),
                    ],
                    selected: {loc},
                    onSelectionChanged: (s) => setM(() => loc = s.first),
                  ),
                  const SizedBox(height: 16),
                  Text('Profissional?', style: Theme.of(context).textTheme.titleSmall),
                  SegmentedButton<TriFilter>(
                    segments: const [
                      ButtonSegment(value: TriFilter.any, label: Text('Qualquer')),
                      ButtonSegment(value: TriFilter.yes, label: Text('Sim')),
                      ButtonSegment(value: TriFilter.no, label: Text('Não')),
                    ],
                    selected: {prof},
                    onSelectionChanged: (s) => setM(() => prof = s.first),
                  ),
                  const Divider(height: 28),
                  Text('Valor da hora (R\$)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: (pxMin == null && pxMax == null),
                        onSelected: (_) => setM(() {
                          pxMin = null;
                          pxMax = null;
                          limitCtrl.clear();
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('Até 150'),
                        selected: pxMin == null && pxMax != null && (pxMax! - 150).abs() < 0.01,
                        onSelected: (_) => setM(() {
                          pxMin = null;
                          pxMax = 150;
                          limitCtrl.text = '150';
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('Até 350'),
                        selected: pxMin == null && pxMax != null && (pxMax! - 350).abs() < 0.01,
                        onSelected: (_) => setM(() {
                          pxMin = null;
                          pxMax = 350;
                          limitCtrl.text = '350';
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('350–650'),
                        selected:
                            pxMin != null && (pxMin! - 350).abs() < 0.01 && pxMax != null && (pxMax! - 650).abs() < 0.01,
                        onSelected: (_) => setM(() {
                          pxMin = 350;
                          pxMax = 650;
                          limitCtrl.clear();
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('650+'),
                        selected: pxMin != null && (pxMin! - 650).abs() < 0.01 && pxMax == null,
                        onSelected: (_) => setM(() {
                          pxMin = 650;
                          pxMax = null;
                          limitCtrl.clear();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ou um limite personalizado',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: limitCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Teto máximo (R\$/h)',
                            hintText: 'Ex.: 480',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.tonal(
                          onPressed: () {
                            final raw = limitCtrl.text.trim();
                            if (raw.isEmpty) {
                              setM(() {
                                pxMin = null;
                                pxMax = null;
                              });
                              return;
                            }
                            final n = int.tryParse(raw);
                            if (n == null || n <= 0) {
                              return;
                            }
                            setM(() {
                              pxMin = null;
                              pxMax = n.toDouble();
                            });
                          },
                          child: const Text('Aplicar'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  FilledButton(
                    onPressed: () {
                      applyCustomLimitFieldToState();
                      Navigator.pop(sheetCtx);
                      setState(() {
                        _maxDistanceKm = _snapDistanceToPreset(km);
                        _ageRange = ages;
                        _genderKey = gen;
                        _hasLocationFilter = loc;
                        _professionalFilter = prof;
                        _hourlyPriceMinBrl = pxMin;
                        _hourlyPriceMaxBrl = pxMax;
                      });
                      _load(immediate: true);
                    },
                    child: const Text('Ver resultados'),
                  ),
                  TextButton(onPressed: _resetFiltersNavigator(sheetCtx), child: const Text('Limpar tudo')),
                  const SizedBox(height: 12),
                  Text(
                    'API ${apiBaseUrl()}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(limitCtrl.dispose);
  }

  void Function() _resetFiltersNavigator(BuildContext sheetCtx) {
    return () {
      Navigator.pop(sheetCtx);
      _resetFilters();
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        centerTitle: false,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Seduce',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onPrimary,
                  ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: 'Sua conta',
              child: Material(
                color: cs.surface.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _openAccount,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: _accountAvatar(cs),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Pesquisar nome, cidade…',
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: cs.surface,
                  prefixIcon: Icon(Icons.search, size: 20, color: cs.outline),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          onPressed: () => _searchCtrl.clear(),
                          icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                          visualDensity: VisualDensity.compact,
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.45)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.45)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide(color: cs.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            onPressed: _openAccount,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : () => _load(immediate: true),
            icon: _loading
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            elevation: 0,
            shadowColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 12, 0),
                  child: Row(
                    children: [
                      const Spacer(),
                      if (_loading && _directory.isNotEmpty)
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                _exploreFiltersBlock(),
                _extrasRowFixed(),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
          Expanded(child: _buildGrid(context)),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    if (_loading && _directory.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Falha ao carregar a lista.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SelectableText(_error!, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => _load(immediate: true), child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }
    if (_directory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'Nenhum resultado com esse filtro.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _resetFilters, child: const Text('Mostrar todos')),
            ],
          ),
        ),
      );
    }

    final shown = _visibleDirectory();
    if (shown.isEmpty) {
      final q = _searchCtrl.text.trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.manage_search_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                q.isEmpty
                    ? 'Nenhum perfil corresponde aos filtros.'
                    : 'Nada encontrado para "$q".',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _searchCtrl.clear(),
                child: const Text('Limpar pesquisa'),
              ),
            ],
          ),
        ),
      );
    }

    if (_directoryMapMode) {
      return _DirectoryMapExplorer(
        entries: shown,
        onOpenEntry: (e) {
          final heroTag = 'dir-map-${e.key}';
          if (e.isAd) {
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => UserAdDetailScreen(
                  ad: e.ad!,
                  heroTag: heroTag,
                ),
              ),
            );
          } else {
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CompanionDetailScreen(
                  initial: e.companion!,
                  repo: _repo,
                  heroTag: heroTag,
                ),
              ),
            );
          }
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final e = shown[i];
        final heroTag = 'dir-thumb-${e.key}';
        return _DirectoryTile(
          entry: e,
          heroTag: heroTag,
          onTap: () {
            if (e.isAd) {
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => UserAdDetailScreen(
                    ad: e.ad!,
                    heroTag: heroTag,
                  ),
                ),
              );
            } else {
              final c = e.companion!;
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => CompanionDetailScreen(
                    initial: c,
                    repo: _repo,
                    heroTag: heroTag,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}

class _DirectoryMapExplorer extends StatefulWidget {
  const _DirectoryMapExplorer({
    required this.entries,
    required this.onOpenEntry,
  });

  final List<DirectoryEntry> entries;
  final void Function(DirectoryEntry entry) onOpenEntry;

  @override
  State<_DirectoryMapExplorer> createState() => _DirectoryMapExplorerState();
}

class _DirectoryMapExplorerState extends State<_DirectoryMapExplorer> {
  final MapController _mapController = MapController();

  LatLng? _userPos;
  bool _locating = true;
  String? _locHint;

  static const LatLng _fallbackCenter = LatLng(-23.5505, -46.6333);

  @override
  void initState() {
    super.initState();
    _resolveUserLocation();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _resolveUserLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() {
          _locating = false;
          _locHint = 'Ative a localização para ver onde você está no mapa.';
        });
        _scheduleFitCamera();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() {
          _locating = false;
          _locHint = 'Sem permissão de localização — o mapa mostra só os anúncios.';
        });
        _scheduleFitCamera();
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (!mounted) return;
      setState(() {
        _userPos = LatLng(p.latitude, p.longitude);
        _locating = false;
      });
      _scheduleFitCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _locHint = 'Não foi possível obter a sua posição.';
      });
      _scheduleFitCamera();
    }
  }

  void _scheduleFitCamera() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyCameraFit());
  }

  void _applyCameraFit() {
    if (!mounted) return;
    try {
      final markers =
          widget.entries.map(_directoryEntryLatLng).whereType<LatLng>().toList(growable: false);
      final points = <LatLng>[
        if (_userPos != null) _userPos!,
        ...markers,
      ];
      if (points.isEmpty) {
        _mapController.move(_fallbackCenter, 11);
        return;
      }
      if (points.length == 1) {
        _mapController.move(points.first, 13);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(56),
          maxZoom: 16,
        ),
      );
    } catch (_) {
      /* MapController ainda pode não estar ligado ao FlutterMap na primeira frame. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final markers = widget.entries.map(_directoryEntryLatLng).whereType<LatLng>().toList(growable: false);
    final mappedEntries =
        widget.entries.where((e) => _directoryEntryLatLng(e) != null).toList(growable: false);
    final bannerText = mappedEntries.isEmpty
        ? 'Nenhum resultado tem coordenadas no mapa — atualize o servidor ou os filtros.'
        : _locHint;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _userPos ?? (markers.isNotEmpty ? markers.first : _fallbackCenter),
            initialZoom: markers.isEmpty && _userPos == null ? 11 : 12,
            onMapReady: _applyCameraFit,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.seduce.seduce_mobile',
            ),
            MarkerLayer(
              markers: [
                if (_userPos != null)
                  Marker(
                    point: _userPos!,
                    width: 36,
                    height: 36,
                    child: Icon(Icons.my_location, color: cs.primary, size: 34),
                  ),
                for (final e in mappedEntries)
                  Marker(
                    point: _directoryEntryLatLng(e)!,
                    width: 44,
                    height: 44,
                    alignment: Alignment.bottomCenter,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onOpenEntry(e),
                        child: Icon(
                          Icons.location_on,
                          color: e.isAd ? Colors.deepOrange : cs.secondary,
                          size: 42,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (_locating)
          const Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('A localizar…'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (!_locating && bannerText != null && bannerText.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  bannerText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.entry,
    required this.heroTag,
    required this.onTap,
  });

  final DirectoryEntry entry;
  final Object heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              child: Image.network(
                entry.coverPhotoUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.broken_image_outlined, color: cs.outline, size: 40),
                ),
              ),
            ),
            if (entry.isAd)
              Positioned(
                top: 8,
                left: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'Anúncio',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        entry.subtitleLine(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
