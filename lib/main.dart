import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Las credenciales se inyectan en compilación (no quedan en el código)
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY'); // service_role

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Error: Debes definir SUPABASE_URL y SUPABASE_KEY\n'
            'Ejemplo: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...',
          ),
        ),
      ),
    ));
    return;
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const KeywordManagerApp());
}

class KeywordManagerApp extends StatelessWidget {
  const KeywordManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keyword Manager',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const KeywordListScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modelo simple
// ─────────────────────────────────────────────────────────────────────────────
class Keyword {
  final int id;
  final String keyword;
  final String? platform;
  final String? engine;
  final String? label;
  final bool scraping;
  final DateTime scrapedAt;

  Keyword({
    required this.id,
    required this.keyword,
    this.platform,
    this.engine,
    this.label,
    this.scraping = false,
    required this.scrapedAt,
  });

  factory Keyword.fromMap(Map<String, dynamic> map) {
    return Keyword(
      id: map['id'] as int,
      keyword: map['keyword'] as String,
      platform: map['platform'] as String?,
      engine: map['engine'] as String?,
      label: map['label'] as String?,
      scraping: map['scraping'] as bool? ?? false,
      scrapedAt: DateTime.parse(map['scraped_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'keyword': keyword,
      'platform': platform,
      'engine': engine,
      'label': label,
      // id, scraping, scraped_at no se envían en inserts/updates explícitos
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla principal – Lista con filtros y CRUD
// ─────────────────────────────────────────────────────────────────────────────
class KeywordListScreen extends StatefulWidget {
  const KeywordListScreen({super.key});

  @override
  State<KeywordListScreen> createState() => _KeywordListScreenState();
}

class _KeywordListScreenState extends State<KeywordListScreen> {
  final _supabase = Supabase.instance.client;

  // Filtros
  final _searchController = TextEditingController();
  String _filterLabel = '';
  String _filterPlatform = '';

  List<Keyword> _keywords = [];
  bool _loading = false;
  bool _hasMore = true;
  static const int _pageSize = 20;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadKeywords(reset: true);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _loadKeywords(reset: true);
  }

  Future<void> _loadKeywords({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      setState(() {
        _currentPage = 0;
        _keywords = [];
        _hasMore = true;
      });
    }
    if (!_hasMore) return;

    setState(() => _loading = true);

    try {
      var query = _supabase
          .from('keyword')
          .select()
          .order('id', ascending: false)
          .range(_currentPage * _pageSize, (_currentPage + 1) * _pageSize - 1);

      // Aplicar filtros
      final search = _searchController.text.trim();
      if (search.isNotEmpty) {
        query = query.ilike('keyword', '%$search%');
      }
      if (_filterLabel.isNotEmpty) {
        query = query.eq('label', _filterLabel);
      }
      if (_filterPlatform.isNotEmpty) {
        query = query.eq('platform', _filterPlatform);
      }

      final data = await query;
      final newKeywords = (data as List).map((e) => Keyword.fromMap(e)).toList();

      setState(() {
        if (reset) {
          _keywords = newKeywords;
        } else {
          _keywords.addAll(newKeywords);
        }
        _hasMore = newKeywords.length == _pageSize;
        _currentPage++;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e')),
        );
      }
    }
  }

  Future<void> _deleteKeyword(Keyword kw) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar keyword'),
        content: Text('¿Eliminar "${kw.keyword}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _supabase.from('keyword').delete().eq('id', kw.id);
      setState(() => _keywords.removeWhere((k) => k.id == kw.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  Future<void> _showEditDialog({Keyword? existing}) async {
    final formKey = GlobalKey<FormState>();
    final kwController = TextEditingController(text: existing?.keyword ?? '');
    final platformController = TextEditingController(text: existing?.platform ?? '');
    final labelController = TextEditingController(text: existing?.label ?? '');
    final engineController = TextEditingController(text: existing?.engine ?? '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? 'Nueva keyword' : 'Editar keyword'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: kwController,
                    decoration: const InputDecoration(labelText: 'Keyword *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: platformController,
                    decoration: const InputDecoration(labelText: 'Platform'),
                  ),
                  TextFormField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                  TextFormField(
                    controller: engineController,
                    decoration: const InputDecoration(labelText: 'Engine'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, {
                    'keyword': kwController.text.trim(),
                    'platform': platformController.text.trim().isEmpty ? null : platformController.text.trim(),
                    'label': labelController.text.trim().isEmpty ? null : labelController.text.trim(),
                    'engine': engineController.text.trim().isEmpty ? null : engineController.text.trim(),
                  });
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    try {
      if (existing == null) {
        // Insertar
        await _supabase.from('keyword').insert(result);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keyword creada')));
      } else {
        // Actualizar
        await _supabase.from('keyword').update(result).eq('id', existing.id);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keyword actualizada')));
      }
      _loadKeywords(reset: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filtrar por Label', style: Theme.of(context).textTheme.titleMedium),
              DropdownButtonFormField<String>(
                value: _filterLabel.isEmpty ? null : _filterLabel,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todos')),
                  ...['IG', 'FB', 'YT', 'TW'] // ejemplos, puedes obtenerlos dinámicamente
                      .map((l) => DropdownMenuItem(value: l, child: Text(l))),
                ],
                onChanged: (val) {
                  setState(() => _filterLabel = val ?? '');
                  _loadKeywords(reset: true);
                },
              ),
              const SizedBox(height: 12),
              Text('Filtrar por Platform', style: Theme.of(context).textTheme.titleMedium),
              DropdownButtonFormField<String>(
                value: _filterPlatform.isEmpty ? null : _filterPlatform,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todas')),
                  const DropdownMenuItem(value: 'facebook', child: Text('Facebook')),
                  const DropdownMenuItem(value: 'instagram', child: Text('Instagram')),
                ],
                onChanged: (val) {
                  setState(() => _filterPlatform = val ?? '');
                  _loadKeywords(reset: true);
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _filterLabel = '';
                    _filterPlatform = '';
                  });
                  _loadKeywords(reset: true);
                },
                child: const Text('Limpiar filtros'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keywords'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar keyword',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _loadKeywords(reset: true),
              child: _keywords.isEmpty && !_loading
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.builder(
                      itemCount: _keywords.length + (_loading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _keywords.length) {
                          _loadKeywords(); // carga más
                          return const Center(child: CircularProgressIndicator());
                        }
                        final kw = _keywords[index];
                        return Card(
                          child: ListTile(
                            title: Text(kw.keyword),
                            subtitle: Text(
                              'Label: ${kw.label ?? '-'} | Platform: ${kw.platform ?? '-'}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') _showEditDialog(existing: kw);
                                if (action == 'delete') _deleteKeyword(kw);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                                const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}