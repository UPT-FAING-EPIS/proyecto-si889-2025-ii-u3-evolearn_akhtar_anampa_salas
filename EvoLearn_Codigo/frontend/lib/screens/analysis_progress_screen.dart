import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../config.dart';
import 'summary_screen.dart';

class AnalysisProgressScreen extends StatefulWidget {
  final int jobId;
  final String displayName;

  const AnalysisProgressScreen({
    super.key,
    required this.jobId,
    required this.displayName,
  });

  @override
  State<AnalysisProgressScreen> createState() => _AnalysisProgressScreenState();
}

class _AnalysisProgressScreenState extends State<AnalysisProgressScreen> {
  Timer? _timer;
  String _status = 'pending';
  double _progress = 0.0;
  String _errorMessage = '';

  late final ApiService _apiService = ApiService(baseUrl: getBaseUrl());

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final result = await _apiService.getSummaryStatus(widget.jobId);
        final job = result['job'];

        if (!mounted) return;

        setState(() {
          _status = job['status'] ?? 'unknown';
          _progress = (job['progress'] ?? 0.0) / 100.0;
          _errorMessage = job['error_message'] ?? '';
        });

        if (_status == 'completed' || _status == 'failed') {
          _timer?.cancel();
          if (_status == 'completed') {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => SummaryScreen(
                  title: widget.displayName,
                  summaryText: job['summary_text'] ?? '',
                  api: _apiService,
                ),
              ),
            );
          }
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _status = 'failed';
          _errorMessage = 'No se pudo obtener el estado del análisis: $e';
        });
        _timer?.cancel();
      }
    });
  }

  String _getStatusMessage() {
    switch (_status) {
      case 'pending':
        return 'Iniciando análisis...';
      case 'processing':
        return 'Procesando documento... (${(_progress * 100).toStringAsFixed(0)}%)';
      case 'completed':
        return 'Análisis completado. Redirigiendo...';
      case 'failed':
        return 'El análisis ha fallado.';
      default:
        return 'Consultando estado...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis en Progreso'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              CircularProgressIndicator(
                value: _status == 'processing' ? _progress : null,
                strokeWidth: 6,
              ),
              const SizedBox(height: 24),
              Text(
                _getStatusMessage(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_status == 'failed' && _errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
