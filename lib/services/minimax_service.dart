import 'dart:convert';
import 'package:http/http.dart' as http;
import '../db_helper.dart';

class MiniMaxService {
  final DBHelper _dbHelper = DBHelper();

  Future<String> _getConfig(String key, String defaultValue) async {
    return await _dbHelper.getAppConfigOrDefault(key, defaultValue);
  }

  Future<String> get apiKey async => await _getConfig('minimax_api_key', '');
  Future<String> get baseUrl async => await _getConfig('minimax_base_url', 'https://api.minimax.io/v1');
  Future<String> get model async => await _getConfig('minimax_model', 'MiniMax-M2.7-highspeed');

  static const List<String> topics = [
    'Naturaleza',
    'Informática',
    'Viajes',
    'Comida',
    'Deportes',
    'Cine',
    'Música',
    'Ciencia',
    'Historia',
    'Salud',
  ];

  static const String _systemPrompt =
      '''Eres un profesor de inglés conversacional. 
Tu objetivo es ayudar al estudiante a practicar inglés en un tema específico.
Reglas:
1. Genera una frase breve y sencilla para iniciar la conversación sobre el tema
2. Cuando el estudiante responda, evalúa su respuesta en una escala del 0 al 1
3. Proporciona feedback constructivo
4. Si hay errores gramaticales o de formulación, sugiere la respuesta correcta
5. Genera la siguiente pregunta para continuar la conversación
6. Después de 5 intercambios, indica que la sesión ha terminado

Formato de respuesta (JSON):
{
  "student_text": "texto del estudiante",
  "score": 0.0-1.0,
  "feedback": "comentario breve",
  "suggestion": "sugerencia si hay errores (si no hay errores, poner null)",
  "ai_message": "tu siguiente frase/pregunta",
  "session_complete": false
}''';

  Future<String> startConversation(String topic) async {
    final response = await _callAPI(
      messages: [
        {
          'role': 'system',
          'content':
              '$_systemPrompt\n\nEl tema de hoy es: $topic.\nInicia la conversación con una frase introductoria.',
        },
      ],
    );
    return response;
  }

  Future<String> evaluateAndContinue(
    String topic,
    String userResponse,
    List<String> history,
  ) async {
    final historyText = history.isNotEmpty
        ? 'Historial de la conversación:\n${history.join('\n')}'
        : '';

    final response = await _callAPI(
      messages: [
        {
          'role': 'system',
          'content':
              '$_systemPrompt\n\nEl tema de hoy es: $topic.\n$historyText',
        },
        {'role': 'user', 'content': userResponse},
      ],
    );
    return response;
  }

  Future<String> _callAPI({required List<Map<String, String>> messages}) async {
    try {
      final apiKeyValue = await apiKey;
      final baseUrlValue = await baseUrl;
      final modelValue = await model;
      
      if (apiKeyValue.isEmpty) {
        return 'Error: API Key not configured. Please set it in Settings.';
      }

      final uri = Uri.parse('$baseUrlValue/chat/completions');
      final body = jsonEncode({'model': modelValue, 'messages': messages});

      final http.Response response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKeyValue',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final message = choices[0]['message'];
          if (message != null && message['content'] != null) {
            final content = message['content'].toString();
            if (content.isNotEmpty) {
              return content;
            }
          }
        }
        return 'Error: Empty response from API. Response: ${data.toString()}';
      } else {
        final errorBody = response.body;
        return 'API Error ${response.statusCode}: $errorBody';
      }
    } catch (e) {
      return 'Network Error: $e';
    }
  }

  String getLastError(String apiKeyPreview) {
    if (apiKeyPreview.isEmpty) {
      return 'API Key not configured';
    }
    return 'API Key format: ${apiKeyPreview.substring(0, apiKeyPreview.length < 10 ? apiKeyPreview.length : 10)}...';
  }

  Map<String, dynamic>? parseResponse(String response) {
    try {
      final start = response.indexOf('{');
      final end = response.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        final jsonStr = response.substring(start, end + 1);
        return jsonDecode(jsonStr);
      }
    } catch (e) {
      // Si falla el parseo, devolver null
    }
    return null;
  }
}
