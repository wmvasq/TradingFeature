import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/trading_models.dart';

/// Servicio de IA para análisis de trading
/// Reutiliza la lógica de MiniMaxService pero con prompts especializados
///
/// FUNCIONALIDADES:
/// 1. Explicar señales de trading generadas
/// 2. Responder preguntas sobre estrategia de Merino
/// 3. Analizar sentimiento de noticias
/// 4. Dar recomendaciones personalizadas
class TradingAIService {
  static const String _apiKey = ''; // Misma API key de MiniMax
  static const String _baseUrl = 'https://api.minimax.io/v1';
  static const String _model = 'MiniMax-M2.7-highspeed';

  // System prompt exclusivo para trading
  static const String _tradingSystemPrompt = '''
Eres un analista experto en trading de Bitcoin y criptomonedas, especializado en la estrategia de Jaime Merino (TradingLatino).

Tu conocimiento incluye:
- Análisis técnico: EMAs, ADX, Squeeze Momentum, RSI, MACD
- Gestión de riesgo: 40/30/20/10 capital allocation
- Psicología del trading
- Ciclos de Bitcoin (halving, ETF spot)

Reglas de respuesta:
1. Sé conciso y directo (máximo 3 párrafos)
2. Usa emojis solo cuando sea apropiado (📈 📉 ⚠️ ✅)
3. Explica términos técnicos si el usuario es principiante
4. NUNCA des consejos financieros directos - solo análisis educativo
5. Si no sabes, dilo claramente

Formato preferido:
- Análisis: 2-3 puntos clave
- Riesgos: 1-2 advertencias
- Sugerencia: qué mirar a continuación

Contexto de la estrategia de Merino:
- Compra BTC a largo plazo en zonas de soporte (59k-61k post-halving)
- Evita shorting Bitcoin ("Short a Bitcoin no")
- Usa stop loss SIEMPRE
- Divide capital: 40% largo, 30% semanal, 20% diario, 10% futuros
- EMAs clave: 9, 20, 50, 200
- ADX > 25 = tendencia fuerte
''';

  /// Explica una señal de trading en lenguaje humano
  Future<String> explainSignal(
    TradingSignal signal, {
    bool detailed = false,
  }) async {
    String prompt = detailed
        ? '''Explica detalladamente esta señal de trading:

${signal.toString()}

Análisis técnico:
${_formatTechnicalData(signal.technicalData)}

Proporciona:
1. Interpretación de cada indicador
2. Por qué la confianza es ${(signal.confidence * 100).toStringAsFixed(0)}%
3. Posibles riesgos
4. Qué monitorear después de esta señal'''
        : '''Explica brevemente esta señal de Bitcoin:

Tipo: ${signal.type}
Razón: ${signal.reason}
Confianza: ${(signal.confidence * 100).toStringAsFixed(0)}%
Niveles: Entrada \$${signal.entryPrice?.toStringAsFixed(2) ?? 'N/A'}, SL \$${signal.stopLoss?.toStringAsFixed(2) ?? 'N/A'}

Máximo 3 frases, lenguaje claro.''';

    return await _callAI(
      messages: [
        {'role': 'system', 'content': _tradingSystemPrompt},
        {'role': 'user', 'content': prompt},
      ],
    );
  }

  /// Responde preguntas sobre la estrategia de Merino
  Future<String> answerStrategyQuestion(String question) async {
    return await _callAI(
      messages: [
        {'role': 'system', 'content': _tradingSystemPrompt},
        {'role': 'user', 'content': question},
      ],
    );
  }

  /// Analiza una noticia o evento de mercado
  Future<MarketSentiment> analyzeNewsSentiment(
    String headline,
    String? content,
  ) async {
    String text = headline + (content != null ? '\n\n$content' : '');

    final response = await _callAI(
      messages: [
        {'role': 'system', 'content': _tradingSystemPrompt},
        {
          'role': 'user',
          'content':
              '''
Analiza el sentimiento de esta noticia sobre Bitcoin/crypto:

"$text"

Responde SOLO en JSON con este formato:
{
  "sentiment": "positive|neutral|negative",
  "impact": "high|medium|low",
  "reason": "breve explicación",
  "action": "buy|sell|hold|monitor"
}
''',
        },
      ],
    );

    // Parsear JSON de respuesta
    try {
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        String jsonStr = response.substring(jsonStart, jsonEnd + 1);
        Map<String, dynamic> data = jsonDecode(jsonStr);
        return MarketSentiment.fromJson(data);
      }
    } catch (e) {
      // Fallback si no se puede parsear
    }

    return MarketSentiment(
      sentiment: Sentiment.neutral,
      impact: Impact.medium,
      reason: 'No se pudo analizar completamente',
      action: 'monitor',
    );
  }

  /// Da recomendación de trading basada en perfil de riesgo
  Future<TradingRecommendation> getRecommendation({
    required TradingSignal signal,
    required RiskProfile profile,
    required double availableCapital,
  }) async {
    String prompt =
        '''
Perfil de trader: ${profile.toString()}
Capital disponible: \$${availableCapital}
Señal: ${signal.type} con ${(signal.confidence * 100).toStringAsFixed(0)}% de confianza

Considerando la estrategia de Merino (40/30/20/10):
- ¿Qué porcentaje del capital asignar?
- ¿Es adecuada esta señal para mi perfil?
- ¿Qué niveles de SL/TP sugerir?

Responde en JSON:
{
  "allocation": "porcentaje sugerido (0-100)",
  "riskLevel": "low|medium|high",
  "adjustedSL": "porcentaje o null",
  "advice": "consejo breve (max 50 palabras)"
}
''';

    final response = await _callAI(
      messages: [
        {'role': 'system', 'content': _tradingSystemPrompt},
        {'role': 'user', 'content': prompt},
      ],
    );

    try {
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        String jsonStr = response.substring(jsonStart, jsonEnd + 1);
        Map<String, dynamic> data = jsonDecode(jsonStr);
        return TradingRecommendation.fromJson(data);
      }
    } catch (e) {
      // Fallback a recomendación conservadora
    }

    return TradingRecommendation(
      allocation: 0.0,
      riskLevel: RiskLevel.medium,
      adjustedSL: null,
      advice: 'No tomar acción hasta confirmar señal',
    );
  }

  /// Pregunta general sobre trading de Bitcoin
  Future<String> ask(String question) async {
    return await _callAI(
      messages: [
        {'role': 'system', 'content': _tradingSystemPrompt},
        {'role': 'user', 'content': question},
      ],
    );
  }

  // ============================================
  // MÉTODO BASE PARA LLAMAR A API
  // ============================================

  Future<String> _callAI({required List<Map<String, String>> messages}) async {
    try {
      final uri = Uri.parse('$_baseUrl/chat/completions');
      final body = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': 0.7,
        'top_p': 0.9,
      });

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
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
            return message['content'].toString();
          }
        }
        return 'Error: Respuesta vacía de IA';
      } else {
        return 'Error API ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      return 'Error de conexión: $e';
    }
  }

  // ============================================
  // UTILIDADES DE FORMATEO
  // ============================================

  String _formatTechnicalData(Map<String, dynamic> data) {
    StringBuffer sb = StringBuffer();

    data.forEach((key, value) {
      if (value is double?) {
        sb.writeln('$key: ${value?.toStringAsFixed(4) ?? 'null'}');
      } else {
        sb.writeln('$key: $value');
      }
    });

    return sb.toString();
  }
}

// ============================================
// MODELOS DE RESPUESTA DE IA
// ============================================

enum Sentiment { positive, neutral, negative }

enum Impact { high, medium, low }

enum RiskLevel { low, medium, high }

class MarketSentiment {
  final Sentiment sentiment;
  final Impact impact;
  final String reason;
  final String action; // 'buy', 'sell', 'hold', 'monitor'

  MarketSentiment({
    required this.sentiment,
    required this.impact,
    required this.reason,
    required this.action,
  });

  factory MarketSentiment.fromJson(Map<String, dynamic> json) {
    return MarketSentiment(
      sentiment: Sentiment.values.firstWhere(
        (e) => e.toString().split('.').last == json['sentiment'],
        orElse: () => Sentiment.neutral,
      ),
      impact: Impact.values.firstWhere(
        (e) => e.toString().split('.').last == json['impact'],
        orElse: () => Impact.medium,
      ),
      reason: json['reason'] ?? '',
      action: json['action'] ?? 'monitor',
    );
  }
}

class TradingRecommendation {
  final double allocation; // 0.0 a 1.0 (porcentaje del capital)
  final RiskLevel riskLevel;
  final double? adjustedSL; // SL ajustado (si es null, usar el de la señal)
  final String advice;

  TradingRecommendation({
    required this.allocation,
    required this.riskLevel,
    this.adjustedSL,
    required this.advice,
  });

  factory TradingRecommendation.fromJson(Map<String, dynamic> json) {
    return TradingRecommendation(
      allocation: (json['allocation'] as num?)?.toDouble() ?? 0.0,
      riskLevel: RiskLevel.values.firstWhere(
        (e) => e.toString().split('.').last == json['riskLevel'],
        orElse: () => RiskLevel.medium,
      ),
      adjustedSL: json['adjustedSL']?.toDouble(),
      advice: json['advice'] ?? '',
    );
  }
}

enum RiskProfile { conservative, moderate, aggressive, dayTrader }

extension RiskProfileExtension on RiskProfile {
  String get description {
    switch (this) {
      case RiskProfile.conservative:
        return 'Conservador: Prioriza preservación de capital, opera solo señales muy fuertes (confianza >80%)';
      case RiskProfile.moderate:
        return 'Moderado: Balance entre seguridad y oportunidad (confianza >60%)';
      case RiskProfile.aggressive:
        return 'Agresivo: Busca maximizar ganancias, acepta mayor riesgo (confianza >50%)';
      case RiskProfile.dayTrader:
        return 'Day Trader: Opera múltiples veces al día, gestión estricta de riesgo por operación';
    }
  }

  double get minConfidence {
    switch (this) {
      case RiskProfile.conservative:
        return 0.80;
      case RiskProfile.moderate:
        return 0.60;
      case RiskProfile.aggressive:
        return 0.50;
      case RiskProfile.dayTrader:
        return 0.55;
    }
  }
}
