import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'directories_screen.dart';
import 'shared_screen.dart';
import 'courses_topics_tab.dart';

class MainTabsScreen extends StatefulWidget {
  final ApiService api;
  const MainTabsScreen({super.key, required this.api});

  @override
  State<MainTabsScreen> createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Colores más contrastantes para mejor visibilidad
    final activeColor = const Color(0xFF1976D2); // Azul brillante
    final inactiveColor = Colors.grey.shade500; // Gris medio

    final pages = [
      DirectoriesScreen(api: widget.api),
      SharedScreen(api: widget.api),
      CoursesTopicsTab(api: widget.api),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedItemColor: activeColor,
        unselectedItemColor: inactiveColor,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.folder),
            label: 'Carpetas',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.folder_shared),
            label: 'Compartidos',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Cursos',
          ),
        ],
      ),
    );
  }
}