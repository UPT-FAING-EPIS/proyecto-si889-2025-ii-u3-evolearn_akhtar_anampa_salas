import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';
import 'login_screen.dart';

class CoursesScreen extends StatefulWidget {
  final String tema;
  final List<Map<String, dynamic>> courses;
  final ApiService api;

  const CoursesScreen({super.key, required this.tema, required this.courses, required this.api});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  late List<String> _themes;
  late String _selectedTheme;
  late List<Map<String, dynamic>> _selectedCourses;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedTheme = widget.tema;
    _selectedCourses = List.from(widget.courses);
    _themes = [widget.tema];
    // NO guardar aquí porque ya se guardaron en _viewCourses -> getOrGenerateCourses
    // Solo cargar los temas guardados para mostrar opciones
    _loadSavedThemes();
  }

  Future<void> _loadSavedThemes() async {
    setState(() => _loading = true);
    try {
      final response = await widget.api.get('get_user_course_themes.php');
      if (response['success'] == true) {
        final temas = List<String>.from(response['temas'] ?? []);
        setState(() {
          _themes = temas.isNotEmpty ? temas : [widget.tema];
          if (!_themes.contains(widget.tema)) {
            _themes.insert(0, widget.tema);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading themes: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteCourse(int index) async {
    final course = _selectedCourses[index];
    final courseId = course['id'] as int?;
    
    try {
      if (courseId != null && courseId > 0) {
        // Eliminar de la BD
        await widget.api.post('delete_course.php', {'course_id': courseId});
      }
      
      // Eliminar de la lista local
      setState(() {
        _selectedCourses.removeAt(index);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Curso eliminado exitosamente'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _onThemeSelected(String tema) async {
    setState(() {
      _selectedTheme = tema;
      _loading = true;
    });

    try {
      if (tema == widget.tema) {
        // Si es el tema actual, usar cursos en memoria
        setState(() {
          _selectedCourses = List.from(widget.courses);
        });
      } else {
        // Si es otro tema, cargar desde API
        final response = await widget.api.get('get_courses_by_theme.php?tema=${Uri.encodeComponent(tema)}');
        if (response['success'] == true && response['courses'] != null) {
          setState(() {
            _selectedCourses = List<Map<String, dynamic>>.from(response['courses'] ?? []);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando cursos: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF121212)
          : Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF1976D2),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cursos Gratuitos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'Temas guardados',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.person_outline, color: Colors.white, size: 28),
            tooltip: 'Usuario',
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _goToProfile(context);
                  break;
                case 'logout':
                  _logout(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: Color(0xFF1976D2)),
                    SizedBox(width: 8),
                    Text('Mi Perfil'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Cerrar Sesión'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading && _themes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header con gradiente
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF1976D2),
                        const Color(0xFF1976D2).withOpacity(0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1976D2).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.school,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${_themes.length} ${_themes.length == 1 ? "tema" : "temas"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Botones de temas
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selecciona un tema:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF424242),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _themes.map((tema) {
                          final isSelected = tema == _selectedTheme;
                          return FilterChip(
                            label: Text(tema),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                _onThemeSelected(tema);
                              }
                            },
                            backgroundColor: Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[800]
                                : Colors.white,
                            selectedColor: const Color(0xFF1976D2),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey[700],
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF1976D2)
                                  : const Color(0xFF1976D2).withOpacity(0.3),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                // Contador de cursos
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${_selectedCourses.length} ${_selectedCourses.length == 1 ? "curso" : "cursos"}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // Lista de cursos con cards
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedCourses.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.school_outlined,
                                    size: 64,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No hay cursos para este tema',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _selectedCourses.length,
                              itemBuilder: (context, index) {
                                final course = _selectedCourses[index];
                                final nombre = (course['nombre'] ?? course['name'] ?? 'Curso sin nombre').toString();
                                final duracion = (course['duracion_horas'] ?? course['duration_hours'] ?? 0);
                                final url = (course['url'] ?? '').toString();

                                return TweenAnimationBuilder<double>(
                                  duration: Duration(milliseconds: 300 + (index * 50)),
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
                                    margin: const EdgeInsets.only(bottom: 16),
                                    child: Material(
                                      elevation: 2,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(16),
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? Colors.white.withOpacity(0.08)
                                              : Colors.white,
                                          border: Border.all(
                                            color: const Color(0xFFE0F7FA).withOpacity(0.8),
                                            width: 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.grey.withOpacity(0.1),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Header del curso
                                            Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE1F5FE).withOpacity(0.7),
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(16),
                                                  topRight: Radius.circular(16),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF01579B).withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: const Icon(
                                                      Icons.play_circle_outline,
                                                      color: Color(0xFF0277BD),
                                                      size: 28,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Text(
                                                      nombre,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600,
                                                        color: Color(0xFF0D47A1),
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                                                      onPressed: () {
                                                        showDialog(
                                                          context: context,
                                                          builder: (ctx) => AlertDialog(
                                                            title: const Text('Eliminar curso'),
                                                            content: const Text('¿Estás seguro de que deseas eliminar este curso?'),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () => Navigator.pop(ctx),
                                                                child: const Text('Cancelar'),
                                                              ),
                                                              TextButton(
                                                                onPressed: () {
                                                                  Navigator.pop(ctx);
                                                                  _deleteCourse(index);
                                                                },
                                                                child: const Text('Eliminar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                      tooltip: 'Eliminar este curso',
                                                      padding: const EdgeInsets.all(8),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            const Divider(height: 1),

                                            // Información del curso
                                            Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(8),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange.shade50,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Icon(
                                                          Icons.access_time,
                                                          size: 20,
                                                          color: Colors.orange.shade700,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        duracion > 0
                                                            ? '$duracion ${duracion == 1 ? "hora" : "horas"}'
                                                            : 'Duración variable',
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          color: Theme.of(context).brightness == Brightness.dark
                                                              ? Colors.grey[400]
                                                              : Colors.grey.shade700,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  const SizedBox(height: 16),

                                                  // Botón para abrir curso
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: ElevatedButton.icon(
                                                      onPressed: url.isNotEmpty
                                                          ? () => launchUrl(
                                                                Uri.parse(url),
                                                                mode: LaunchMode.externalApplication,
                                                              )
                                                          : null,
                                                      icon: const Icon(Icons.open_in_new, size: 20),
                                                      label: const Text(
                                                        'Ir al Curso',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFF1976D2),
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        elevation: 0,
                                                      ),
                                                    ),
                                                  ),

                                                  if (url.isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      url,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Theme.of(context).brightness == Brightness.dark
                                                            ? Colors.grey[600]
                                                            : Colors.grey.shade500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ],
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
              ],
            ),
    );
  }

  void _goToProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileScreen(api: widget.api)),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    widget.api.clearToken();
    await prefs.clear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
      (route) => false,
    );
  }
}