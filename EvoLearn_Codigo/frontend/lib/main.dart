import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/connectivity_service.dart';
import 'services/cache_service.dart';
import 'config.dart';
import 'providers/theme_provider.dart';
import 'providers/share_refresh_notifier.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive cache
  await CacheService.initialize();
  
  runApp(const EstudiaFacilApp());
}

class EstudiaFacilApp extends StatelessWidget {
  const EstudiaFacilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()..loadTheme()),
        ChangeNotifierProvider(create: (context) => ShareRefreshNotifier()),
        ChangeNotifierProvider(create: (context) => ConnectivityService()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          final api = ApiService(baseUrl: getBaseUrl());
          
          return MaterialApp(
            title: 'EvoLearn',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: SplashScreen(api: api),
          );
        },
      ),
    );
  }
}
