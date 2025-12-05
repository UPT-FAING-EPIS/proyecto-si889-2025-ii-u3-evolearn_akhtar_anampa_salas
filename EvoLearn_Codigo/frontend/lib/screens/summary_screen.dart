import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'courses_screen.dart';
import '../services/api_service.dart';

class SummaryScreen extends StatefulWidget {
  final String title;
  final String summaryText;
  final ApiService api;

  const SummaryScreen({
    super.key,
    required this.title,
    required this.summaryText,
    required this.api,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: Text('Resumen de ${widget.title}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.school),
            tooltip: 'Ver Cursos',
            onPressed: () => _viewCourses(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) async {
              if (value == 'profile') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(api: widget.api)));
              } else if (value == 'logout') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                widget.api.clearToken();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => LoginScreen(api: widget.api)),
                    (route) => false,
                  );
                }
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Ver perfil'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Markdown(
          data: widget.summaryText,
          selectable: true,
          softLineBreak: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            // Título principal (H1) - Grande y destacado
            h1: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF64B5F6)  // Azul claro para tema oscuro
                  : const Color(0xFF1976D2), // Azul para tema claro
              height: 1.3,
            ),
            // Subtítulos (H2) - Medianos y destacados
            h2: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[300]
                  : const Color(0xFF424242),
              height: 1.4,
            ),
            // Subtítulos menores (H3)
            h3: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : const Color(0xFF616161),
              height: 1.3,
            ),
            // Texto normal - tamaño cómodo para lectura
            p: TextStyle(
              fontSize: 16,
              height: 1.6,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[200]
                  : const Color(0xFF212121),
            ),
            // Listas con buen espaciado
            listBullet: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[200]
                  : Colors.black,
            ),
            // Tablas con bordes
            tableBorder: TableBorder.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[700]!
                  : Colors.grey[300]!,
              width: 1,
            ),
            tableHead: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[100]
                  : const Color(0xFF212121),
            ),
            tableBody: TextStyle(
              fontSize: 14,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[200]
                  : const Color(0xFF424242),
            ),
            // Links en color azul consistente
            a: const TextStyle(
              color: Color(0xFF1976D2),
              decoration: TextDecoration.underline,
            ),
            code: TextStyle(
              fontSize: 14,
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[200]
                  : Colors.grey[800],
              fontFamily: 'monospace',
            ),
            codeblockDecoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[850]
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[700]!
                    : Colors.grey[300]!,
              ),
            ),
            // Espaciado entre bloques
            blockSpacing: 12.0,
            listIndent: 24.0,
          ),
        ),
      ),
    );
  }

  Future<void> _viewCourses(BuildContext context) async {
    if (!mounted) return;

    _showLoadingDialog(context, 'Buscando cursos para tu tema...');

    try {
      // Extraer tema del resumen (buscar el primer título H1 en Markdown)
      String tema = '';
      final lines = widget.summaryText.split('\n');
      for (final line in lines) {
        if (line.trim().startsWith('# ')) {
          tema = line.trim().substring(2).trim();
          // Remover emojis del inicio
          tema = tema.replaceFirst(
            RegExp(r'^[\u{1F300}-\u{1F9FF}]\s*', unicode: true),
            '',
          );
          break;
        }
      }

      if (tema.isEmpty) {
        tema = widget.title;
      }

      // FLUJO INTELIGENTE: Intentar cargar cursos guardados PRIMERO
      // Si no existen, generar nuevos automáticamente
      final data = await widget.api.getOrGenerateCourses(tema);
      final courses = (data['courses'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final source = data['source'] ?? 'unknown'; // 'database', 'generated', o 'none'

      if (!mounted) return;
      Navigator.pop(context); // Cerrar loading dialog

      if (courses.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se encontraron cursos para: $tema')),
          );
        }
        return;
      }

      // Log del origen de los cursos
      String sourceMsg = '';
      if (source == 'database') {
        sourceMsg = '✅ Cursos guardados encontrados';
      } else if (source == 'generated') {
        sourceMsg = '✨ Nuevos cursos generados';
      }
      
      if (sourceMsg.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sourceMsg),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Abrir pantalla de cursos
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CoursesScreen(
            tema: tema,
            courses: courses,
            api: widget.api,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar cursos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animación de icono con pulso
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.0, end: 1.1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeInOut,
                  onEnd: () {},
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor.withOpacity(0.2),
                          Theme.of(context).primaryColor.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.menu_book,
                        size: 40,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Texto principal con animación
                ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withOpacity(0.7),
                      ],
                    ).createShader(bounds);
                  },
                  child: Text(
                    'Buscando cursos...',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Subtítulo descriptivo
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                
                // Barra de progreso lineal animada
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Puntos animados de progreso
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (index) => TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.4, end: 1.0),
                      duration: Duration(milliseconds: 600 + (index * 200)),
                      curve: Curves.easeInOut,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Texto auxiliar motivador
                Text(
                  'Esto puede tomar unos segundos...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}