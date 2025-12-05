import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'courses_screen.dart';

class CoursesTopicsTab extends StatefulWidget {
  final ApiService api;
  const CoursesTopicsTab({super.key, required this.api});

  @override
  State<CoursesTopicsTab> createState() => _CoursesTopicsTabState();
}

class _CoursesTopicsTabState extends State<CoursesTopicsTab> with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _generating = false;
  String? _error;
  final List<String> _topics = [];
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadTopics();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<List<String>> _extractSummaryTopics() async {
    try {
      final dirs = await widget.api.listDirectories();
      if (dirs['mode'] != 'fs') {
        return [];
      }
      final Map<String, dynamic>? fsTree = dirs['fs_tree'] as Map<String, dynamic>?;
      final Set<String> paths = {' '};
      void walk(Map<String, dynamic>? node) {
        if (node == null) return;
        final path = (node['path'] as String?) ?? '';
        paths.add(path);
        final children = (node['directories'] as List<dynamic>?) ?? [];
        for (final child in children) {
          if (child is Map<String, dynamic>) walk(child);
        }
      }
      walk(fsTree);

      final List<String> topicsFound = [];
      for (final p in paths) {
        final effectivePath = (p.trim().isEmpty) ? null : p.trim();
        final docsResp = await widget.api.listDocuments(path: effectivePath);
        final docs = (docsResp['fs_documents'] as List<dynamic>? ?? []);
        for (final d in docs) {
          if (d is Map<String, dynamic>) {
            final type = (d['type'] as String?) ?? '';
            if (type == 'summary') {
              final path = (d['path'] as String?) ?? (d['name'] as String?);
              if (path == null || path.isEmpty) continue;
              try {
                final details = await widget.api.fetchSummaryDetails(fsPath: path);
                final raw = (details['summary_text'] as String?) ?? '';
                final jsonData = jsonDecode(raw) as Map<String, dynamic>;
                final topics = (jsonData['summary']?['topics'] as List<dynamic>? ?? []);
                for (final t in topics) {
                  if (t is Map<String, dynamic>) {
                    final title = (t['title'] as String?)?.trim();
                    if (title != null && title.isNotEmpty && !topicsFound.contains(title)) {
                      topicsFound.add(title);
                    }
                  }
                }
              } catch (_) {}
            }
          }
        }
      }
      return topicsFound;
    } catch (_) {
      return [];
    }
  }

  Future<void> _generateCoursesForTopics() async {
    if (!mounted) return;
    setState(() => _generating = true);
    try {
      final summaryTopics = await _extractSummaryTopics();
      if (summaryTopics.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay temas en los resúmenes para generar cursos')),
        );
        setState(() => _generating = false);
        return;
      }

      // Generate courses for each topic
      for (final tema in summaryTopics) {
        try {
          final coursesResp = await widget.api.get('get_courses.php?tema=${Uri.encodeComponent(tema)}');
          final courses = (coursesResp['courses'] as List<dynamic>? ?? [])
              .map((c) => Map<String, dynamic>.from(c as Map))
              .toList();
          
          // Save courses
          final saveResp = await widget.api.post('save_courses.php', {
            'tema': tema,
            'courses': courses,
          });
          
          if (saveResp['success'] != true) {
            throw Exception('Failed to save courses');
          }
        } catch (_) {}
      }

      // Reload topics
      if (!mounted) return;
      setState(() => _generating = false);
      await _loadTopics();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cursos generados exitosamente')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _loadTopics() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _topics.clear();
    });
    try {
      await widget.api.ensureAuth();
      
      // Get saved course themes from database
      final resp = await widget.api.get('get_user_course_themes.php');
      final themes = (resp['temas'] as List<dynamic>? ?? [])
          .map((t) => (t as String).trim())
          .where((t) => t.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _topics.addAll(themes);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCourses(String tema) async {
    try {
      // Load courses from database for this theme
      final data = await widget.api.get('get_courses_by_theme.php?tema=${Uri.encodeComponent(tema)}');
      final courses = (data['courses'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CoursesScreen(tema: tema, courses: courses, api: widget.api),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar cursos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Cargando cursos...',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
            ),
          ],
        ),
      );
    }
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Error al cargar cursos',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadTopics,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_topics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 80, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text(
                'No hay cursos disponibles',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Genera resúmenes de PDFs para descubrir cursos relacionados',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _generating ? null : _generateCoursesForTopics,
                icon: _generating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
                label: Text(_generating ? 'Generando...' : 'Generar Cursos'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1976D2).withOpacity(0.05),
            Colors.white,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Encabezado estético centrado
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1976D2).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.school,
                      size: 48,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Mis Cursos',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_topics.length} ${_topics.length == 1 ? "tema disponible" : "temas disponibles"}',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            
            // Lista de temas con animación
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _topics.length,
                itemBuilder: (context, i) {
                  final tema = _topics[i];
                  return TweenAnimationBuilder<double>(
                    duration: Duration(milliseconds: 300 + (i * 50)),
                    tween: Tween(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: Opacity(
                          opacity: value,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _openCourses(tema),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  const Color(0xFF1976D2).withOpacity(0.02),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0xFF1976D2).withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1976D2).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.menu_book,
                                    color: Color(0xFF1976D2),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    tema,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF212121),
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 18,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}