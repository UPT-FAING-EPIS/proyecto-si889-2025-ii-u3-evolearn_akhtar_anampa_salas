import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import '../services/api_service.dart'; // <-- Ensure import

class QuizScreen extends StatefulWidget {
  final String sourceName;
  final ApiService api; // <-- Add api field
  final String fsPath;
  final int numQuestions;

  const QuizScreen({
    super.key,
    required this.sourceName,
    required this.api, // <-- Require api in constructor
    required this.fsPath,
    this.numQuestions = 6,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<_Question> _questions = [];
  final Map<int, int> _answers = {}; // question index -> answer index
  bool _submitted = false;
  int _score = 0;
  bool _reviewMode = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuiz(); // Load real questions from backend
  }

  // Load questions from backend based on summary
  Future<void> _loadQuiz() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch summary text first
      final details = await widget.api.fetchSummaryDetails(
        fsPath: widget.fsPath,
      );
      final summaryText = details['summary_text'] as String?;
      if (summaryText == null || summaryText.isEmpty) {
        throw Exception('Resumen vacío o no disponible');
      }
      // Generate quiz via backend with selected number of questions
      final q = await widget.api.generateQuizFromSummary(summaryText, numQuestions: widget.numQuestions);
      _questions = q.map((m) {
        final Map<String, dynamic> mm = Map<String, dynamic>.from(m);
        final String text = (mm['text'] as String?) ?? (mm['question'] as String?) ?? 'Pregunta';
        List<String> options = (mm['options'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
        if (options.length < 4) {
          for (int i = options.length; i < 4; i++) {
            options.add('Opción ${i + 1}');
          }
        } else if (options.length > 4) {
          options = options.take(4).toList();
        }
        final int correct = (mm['correct_index'] is int)
            ? mm['correct_index'] as int
            : (mm['correctIndex'] as int?) ?? 0;
        return _Question(text, options, correct.clamp(0, 3));
      }).toList();
      setState(() {
        _answers.clear();
        _submitted = false;
        _reviewMode = false;
        _score = 0;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Generate placeholder questions (now triggers reload)
  void _generateQuestions() {
    _loadQuiz();
  }


  void _submit() {
    int correctCount = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_answers.containsKey(i) && _answers[i] == _questions[i].correctIndex) {
        correctCount++;
      }
    }
    setState(() {
      _score = correctCount;
      _submitted = true;
      _reviewMode = false; // Ensure review mode is off when submitting
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Show back arrow unless on results screen before review
        leading: _submitted && !_reviewMode
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text('Cuestionario: ${widget.sourceName}'),
        actions: [ // <-- Added actions block
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) async {
              if (value == 'profile') {
                // Pass api
                Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileScreen(api: widget.api)));
              } else if (value == 'logout') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                // Clear token in ApiService instance as well
                widget.api.clearToken();
                if (context.mounted) {
                  // Pass api
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
        child: _submitted && !_reviewMode
            ? _buildResultsView() // Show results
            : _buildQuestionsView(), // Show questions or review
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // Helper widget for results view
  Widget _buildResultsView() {
    final percentage = ((_score / _questions.length) * 100).toStringAsFixed(1);
    final isPassed = _score >= (_questions.length * 0.6);
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final successColor = Colors.green;
    final warningColor = Colors.orange;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Result icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPassed ? successColor.shade100 : warningColor.shade100,
                ),
                child: Icon(
                  isPassed ? Icons.check_circle : Icons.star,
                  size: 60,
                  color: isPassed ? successColor : warningColor,
                ),
              ),
              const SizedBox(height: 24),
              // Score text
              Text(
                'Resultado',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ) ?? const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // Score number
              Text(
                '$_score/${_questions.length}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ) ?? TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              // Percentage
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$percentage%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ) ?? TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Message
              Text(
                isPassed
                    ? '¡Excelente trabajo! 🎉'
                    : 'Sigue practicando 💪',
                style: Theme.of(context).textTheme.bodyLarge ?? const TextStyle(
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // Action buttons
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ver Revisión button
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _reviewMode = true),
                        icon: const Icon(Icons.visibility, size: 20),
                        label: const Text('Ver Revisión', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Intentar Nuevamente button
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? Colors.grey[700]! : Colors.grey[600]!).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _generateQuestions,
                        icon: const Icon(Icons.refresh, size: 20),
                        label: const Text('Intentar Nuevamente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: isDark ? Colors.grey[700] : Colors.grey[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Regresar button
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, size: 20, color: primaryColor),
                      label: Text('Regresar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primaryColor)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

 // Helper widget for questions/review view
  Widget _buildQuestionsView() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Generando ${widget.numQuestions} preguntas...',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error: $_error',
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadQuiz,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Respondidas: ${_answers.length} de ${_questions.length}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600) ??
                        const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    '${((_answers.length / _questions.length) * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ) ?? TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _answers.length / _questions.length,
                  minHeight: 6,
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[700]
                      : Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _questions.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemBuilder: (ctx, i) {
              final q = _questions[i];
              final currentAnswer = _answers[i];

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question number and text
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(context).primaryColor.withOpacity(0.2),
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              q.text,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Options
                      ...List.generate(q.options.length, (optIndex) {
                        final isSelected = currentAnswer == optIndex;
                        final isCorrect = q.correctIndex == optIndex;
                        final primaryColor = Theme.of(context).primaryColor;
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        
                        Color backgroundColor = isDark ? Colors.grey[900]! : Colors.white;
                        Color borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
                        Color? textColor;

                        if (_reviewMode) {
                          if (isCorrect) {
                            backgroundColor = Colors.green.shade50;
                            borderColor = Colors.green;
                          } else if (isSelected && !isCorrect) {
                            backgroundColor = Colors.red.shade50;
                            borderColor = Colors.red;
                          }
                        } else if (isSelected) {
                          backgroundColor = primaryColor.withOpacity(0.15);
                          borderColor = primaryColor;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: borderColor, width: 2),
                              borderRadius: BorderRadius.circular(10),
                              color: backgroundColor,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _reviewMode
                                    ? null
                                    : () => setState(() => _answers[i] = optIndex),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: borderColor,
                                            width: 2,
                                          ),
                                          color: isSelected ? borderColor : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.white),
                                        ),
                                        child: isSelected
                                            ? const Icon(Icons.check,
                                                size: 12, color: Colors.white)
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          q.options[optIndex],
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                      if (_reviewMode) ...[
                                        const SizedBox(width: 8),
                                        if (isCorrect)
                                          const Icon(Icons.check_circle,
                                              color: Colors.green, size: 20)
                                        else if (isSelected && !isCorrect)
                                          const Icon(Icons.cancel,
                                              color: Colors.red, size: 20),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Helper widget for the bottom navigation bar
  Widget? _buildBottomBar() {
    if (_submitted) {
      // Show "Exit Review" button only in review mode
      return _reviewMode
          ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _reviewMode = false),
                  icon: const Icon(Icons.close),
                  label: const Text('Salir de Revisión'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]
                        : Colors.grey[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            )
          : null; // Nothing needed after results shown, before review
    } else {
      // Show "Submit" button before submission
      final allAnswered = _answers.length == _questions.length;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            // Enable only when all questions are answered
            onPressed: (!_loading && _error == null && allAnswered) ? _submit : null,
            icon: const Icon(Icons.check),
            label: Text(
              '${_answers.length}/${_questions.length} - Enviar',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              disabledForegroundColor: Colors.grey[600],
            ),
          ),
        ),
      );
    }
  }
} // End of _QuizScreenState

// Simple class for Question data
class _Question {
  final String text;
  final List<String> options;
  final int correctIndex;
  _Question(this.text, this.options, this.correctIndex);
}