import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

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
            'Ejemplo: flutter build apk '
            '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...',
          ),
        ),
      ),
    ));
    return;
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const KeywordManagerApp());
}

// ─────────────────────────────────────────────
// App
// ─────────────────────────────────────────────
class KeywordManagerApp extends StatelessWidget {
  const KeywordManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keyword Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BFA5),
          brightness: Brightness.dark,
        ),
      ),
      home: const KeywordListScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// Modelo — solo los campos que existen en la tabla
// ─────────────────────────────────────────────
class Keyword {
  final int id;
  final String term;
  final DateTime? scrapedAt;
  final DateTime? createdAt;

  const Keyword({
    required this.id,
    required this.term,
    this.scrapedAt,
    this.createdAt,
  });

  factory Keyword.fromMap(Map<String, dynamic> map) {
    return Keyword(
      id: map['id'] as int,
      term: map['term'] as String,
      scrapedAt: map['scraped_at'] != null
          ? DateTime.parse(map['scraped_at'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }
}

// ─────────────────────────────────────────────
// Pantalla principal
// ─────────────────────────────────────────────
class KeywordListScreen extends StatefulWidget {
  const KeywordListScreen({super.key});

  @override
  State<KeywordListScreen> createState() => _KeywordListScreenState();
}

class _KeywordListScreenState extends State<KeywordListScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  List<Keyword> _allKeywords = [];
  List<Keyword> _filtered = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadKeywords();
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── CRUD ──────────────────────────────────

  Future<void> _loadKeywords() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('keywords')          // ← tabla correcta
          .select()
          .order('id', ascending: false);

      _allKeywords = (data as List)
          .map((row) => Keyword.fromMap(row as Map<String, dynamic>))
          .toList();
      _applySearch();
    } on Exception catch (e) {
      _showSnack('Error al cargar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createKeyword(String term) async {
    try {
      await _supabase.from('keywords').insert({'term': term});
      await _loadKeywords();
    } on Exception catch (e) {
      _showSnack('Error al crear: $e');
    }
  }

  Future<void> _updateKeyword(int id, String newTerm) async {
    try {
      await _supabase
          .from('keywords')
          .update({'term': newTerm})
          .eq('id', id);
      await _loadKeywords();
    } on Exception catch (e) {
      _showSnack('Error al actualizar: $e');
    }
  }

  Future<void> _deleteKeyword(Keyword kw) async {
    final confirmed = await _confirmDialog(
      title: 'Eliminar keyword',
      content: '¿Eliminar "${kw.term}"?',
    );
    if (!confirmed) return;

    try {
      await _supabase.from('keywords').delete().eq('id', kw.id);
      _allKeywords.removeWhere((k) => k.id == kw.id);
      _applySearch();
    } on Exception catch (e) {
      _showSnack('Error al eliminar: $e');
    }
  }

  // ── UI helpers ────────────────────────────

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? List.from(_allKeywords)
          : _allKeywords
              .where((kw) => kw.term.toLowerCase().contains(query))
              .toList();
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirmDialog({
    required String title,
    required String content,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showTermDialog({Keyword? existing}) async {
    final controller = TextEditingController(text: existing?.term ?? '');
    final formKey = GlobalKey<FormState>();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Nueva keyword' : 'Editar keyword'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Término *',
              hintText: 'ej: flutter tutorial',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'El término es obligatorio' : null,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (submitted != true) return;
    final term = controller.text.trim();

    if (existing == null) {
      await _createKeyword(term);
    } else {
      await _updateKeyword(existing.id, term);
    }
  }

  // ── Build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyword Manager'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Buscar keyword…',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _applySearch();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadKeywords,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off,
                            size: 64,
                            color: colorScheme.onSurface.withOpacity(0.3)),
                        const SizedBox(height: 12),
                        Text(
                          _allKeywords.isEmpty
                              ? 'Sin keywords. Añade una con +'
                              : 'Sin resultados para esa búsqueda',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filtered.length,
                    itemBuilder: (_, index) {
                      final kw = _filtered[index];
                      return _KeywordTile(
                        keyword: kw,
                        dateFmt: _dateFmt,
                        onEdit: () => _showTermDialog(existing: kw),
                        onDelete: () => _deleteKeyword(kw),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTermDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Widget de fila
// ─────────────────────────────────────────────
class _KeywordTile extends StatelessWidget {
  final Keyword keyword;
  final DateFormat dateFmt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _KeywordTile({
    required this.keyword,
    required this.dateFmt,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scrapedLabel = keyword.scrapedAt != null
        ? 'Scrapeado: ${dateFmt.format(keyword.scrapedAt!.toLocal())}'
        : 'Sin scrapear';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          keyword.term,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          scrapedLabel,
          style: TextStyle(
            fontSize: 12,
            color: keyword.scrapedAt != null
                ? colorScheme.primary
                : colorScheme.onSurface.withOpacity(0.45),
          ),
        ),
        trailing: PopupMenuButton<_Action>(
          onSelected: (action) {
            if (action == _Action.edit) onEdit();
            if (action == _Action.delete) onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _Action.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Editar'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _Action.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Eliminar'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Action { edit, delete }