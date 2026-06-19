import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

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
    };
  }
}

class KeywordListScreen extends StatefulWidget {
  const KeywordListScreen({super.key});

  @override
  State<KeywordListScreen> createState() => _KeywordListScreenState();
}

class _KeywordListScreenState extends State<KeywordListScreen> {
  final _supabase = Supabase.instance.client;

  final _searchController = TextEditingController();
  String _filterLabel = '';
  String _filterPlatform = '';

  List<Keyword> _allKeywords = [];      // todas las keywords cargadas
  List<Keyword> _filteredKeywords = []; // resultado del filtro local
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadAllKeywords();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllKeywords() async {
    setState(() => _loading = true);
    try {
      // Cargar todas las keywords de una vez (admin local, pocos datos)
      final data = await _supabase
          .from('keyword')
          .select()
          .order('id', ascending: false);

      _allKeywords = (data as List).map((e) => Keyword.fromMap(e)).toList();
      _applyFilters();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final search = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredKeywords = _allKeywords.where((kw) {
        if (search.isNotEmpty && !kw.keyword.toLowerCase().contains(search)) {
          return false;
        }
        if (_filterLabel.isNotEmpty && kw.label != _filterLabel) {
          return false;
        }
        if (_filterPlatform.isNotEmpty && kw.platform != _filterPlatform) {
          return false;
        }
        return true;
      }).toList();
    });
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
      _allKeywords.removeWhere((k) => k.id == kw.id);
      _applyFilters();
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
        await _supabase.from('keyword').insert(result);
      } else {
        await _supabase.from('keyword').update(result).eq('id', existing.id);
      }
      _loadAllKeywords(); // recargar todo tras cambio
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
                  ...['IG', 'FB', 'YT', 'TW']
                      .map((l) => DropdownMenuItem(value: l, child: Text(l))),
                ],
                onChanged: (val) {
                  setState(() => _filterLabel = val ?? '');
                  _applyFilters();
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
                  _applyFilters();
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
                  _applyFilters();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filteredKeywords.isEmpty
              ? const Center(child: Text('Sin resultados'))
              : RefreshIndicator(
                  onRefresh: _loadAllKeywords,
                  child: ListView.builder(
                    itemCount: _filteredKeywords.length,
                    itemBuilder: (context, index) {
                      final kw = _filteredKeywords[index];
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}