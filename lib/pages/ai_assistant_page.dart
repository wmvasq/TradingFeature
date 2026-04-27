import 'package:flutter/material.dart';
import '../services/trading_ai_service.dart';
import '../models/trading_models.dart';

/// Página del asistente de IA para consultas de trading
class AIAssistantPage extends StatefulWidget {
  final TradingAIService aiService;
  final TradingSignal? currentSignal;

  const AIAssistantPage({
    super.key,
    required this.aiService,
    this.currentSignal,
  });

  @override
  State<AIAssistantPage> createState() => _AIAssistantPageState();
}

class _AIAssistantPageState extends State<AIAssistantPage> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    setState(() {
      _messages.add(
        ChatMessage(
          role: MessageRole.assistant,
          content:
              '¡Hola! Soy tu asistente de trading de Bitcoin. Puedo ayudarte con:\n\n'
              '📊 Análisis de señales\n'
              '📈 Preguntas sobre la estrategia de Jaime Merino\n'
              '🔍 Interpretación de indicadores técnicos\n'
              '🧠 Psicología del trading\n\n'
              '¿En qué puedo ayudarte hoy?',
        ),
      );
    });
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    String userMessage = _controller.text.trim();
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(role: MessageRole.user, content: userMessage));
      _isLoading = true;
    });

    try {
      String response = await widget.aiService.ask(userMessage);

      setState(() {
        _messages.add(
          ChatMessage(role: MessageRole.assistant, content: response),
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: MessageRole.assistant,
            content: '❌ Error: $e',
            isError: true,
          ),
        );
        _isLoading = false;
      });
    }
  }

  void _quickQuestion(String question) {
    _controller.text = question;
    _sendMessage();
  }

  void _analyzeCurrentSignal() {
    if (widget.currentSignal == null) {
      _showNoSignalDialog();
      return;
    }

    _controller.text =
        'Explícame esta señal de trading en detalle: ${widget.currentSignal!.reason}';
    _sendMessage();
  }

  void _showNoSignalDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sin Señal'),
        content: Text(
          'No hay una señal actual para analizar. Genera una señal primero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.psychology, color: Colors.purple),
            SizedBox(width: 8),
            Text('Asistente IA'),
          ],
        ),
        actions: [
          if (widget.currentSignal != null)
            IconButton(
              icon: Icon(Icons.analytics),
              onPressed: _analyzeCurrentSignal,
              tooltip: 'Analizar señal actual',
            ),
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: () => _showHelp(),
            tooltip: 'Ayuda',
          ),
        ],
      ),
      body: Column(
        children: [
          // Preguntas rápidas
          _buildQuickQuestions(),

          // Lista de mensajes
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),

          // Indicador de carga
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  SizedBox(width: 16),
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(width: 12),
                  Text(
                    'Analizando...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

          // Input
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildQuickQuestions() {
    return Container(
      height: 80,
      padding: EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12),
        children: [
          _quickChip('¿Qué es el ADX?'),
          _quickChip('¿Cómo funciona el halving?'),
          _quickChip('¿Por qué no shortear Bitcoin?'),
          _quickChip('Interpreta mi señal'),
          _quickChip('Riesgo de esta operación'),
          _quickChip('Estrategia 40/30/20/10'),
        ],
      ),
    );
  }

  Widget _quickChip(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InputChip(
        label: Text(label, style: TextStyle(fontSize: 12)),
        onPressed: () => _quickQuestion(label),
        backgroundColor: Colors.purple.shade50,
        labelStyle: TextStyle(color: Colors.purple.shade800),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    bool isUser = msg.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.blue.shade600
              : msg.isError
              ? Colors.red.shade100
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Text(
          msg.content,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Escribe tu pregunta sobre trading...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          SizedBox(width: 8),
          FloatingActionButton(
            onPressed: _isLoading ? null : _sendMessage,
            mini: true,
            child: Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ayuda - Asistente IA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Puedo ayudarte con:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Explicación de señales generadas'),
            Text('• Conceptos de análisis técnico (EMA, ADX, etc.)'),
            Text('• Psicología del trading'),
            Text('• Estrategia de Jaime Merino'),
            Text('• Gestión de riesgo'),
            SizedBox(height: 12),
            Text(
              'IMPORTANTE:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            Text('Este es un asistente educativo. No es asesor financiero.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

enum MessageRole { user, assistant }

class ChatMessage {
  final MessageRole role;
  final String content;
  final bool isError;

  ChatMessage({
    required this.role,
    required this.content,
    this.isError = false,
  });
}
