import '../models/trading_models.dart';
import 'indicators_service.dart';
import 'market_data_service.dart';

/// Motor principal de generación de señales de trading
/// Implementa la estrategia de Jaime Merino (TradingLatino)
///
/// Lógica basada en:
/// - Cruces de EMAs (9, 20, 50, 200)
/// - Fuerza de tendencia (ADX > 25)
/// - Squeeze Momentum (explosión de volatilidad)
/// - Análisis multi-timeframe
class TradingSignalEngine {
  final TradingConfig config;
  final List<Candle> candles;
  final List<Candle> weeklyCandles; // Para análisis semanal
  final List<Candle> dailyCandles; // Para análisis diario

  // Caché de indicadores (evita recalcular)
  Map<String, List<double?>>? _cachedIndicators;
  DateTime? _lastCalculation;

  TradingSignalEngine({
    required this.config,
    required this.candles,
    this.weeklyCandles = const [],
    this.dailyCandles = const [],
  }) {
    // Validar que hay suficientes datos
    if (candles.length < config.emaLongPeriod) {
      throw ArgumentError(
        'Insuficientes datos. Se necesitan al menos ${config.emaLongPeriod} velas.',
      );
    }
  }

  // ============================================
  // MÉTODO PRINCIPAL: Generar señal
  // ============================================

  /// Genera una señal de trading basada en la estrategia de Merino
  TradingSignal generateSignal({String? marketCondition}) {
    // 1. Preparar datos de precios
    List<double> closes = candles.map((c) => c.close).toList();
    List<double> highs = candles.map((c) => c.high).toList();
    List<double> lows = candles.map((c) => c.low).toList();
    List<double> volumes = candles.map((c) => c.volume).toList();

    // 2. Calcular indicadores principales
    var indicators = _calculateAllIndicators();

    // 3. Evaluar condiciones técnicas
    SignalEvaluation evaluation = _evaluateSignalConditions(
      closes: closes,
      highs: highs,
      lows: lows,
      volumes: volumes,
      indicators: indicators,
    );

    // 4. Aplicar filtros de contexto (halving, ETF, etc.)
    evaluation = _applyMarketContextFilters(evaluation);

    // 5. Determinar tipo de señal y niveles
    return _buildSignalFromEvaluation(evaluation, closes.last);
  }

  // ============================================
  // CÁLCULO DE INDICADORES
  // ============================================

  Map<String, dynamic> _calculateAllIndicators() {
    List<double> closes = candles.map((c) => c.close).toList();
    List<double> highs = candles.map((c) => c.high).toList();
    List<double> lows = candles.map((c) => c.low).toList();

    // EMAs múltiples
    Map<String, List<double?>> emas =
        TechnicalIndicatorsService.calculateMultipleEMAs(closes, {
          'ema9': config.emaFastPeriod,
          'ema20': config.emaMediumPeriod,
          'ema50': config.emaSlowPeriod,
          'ema200': config.emaLongPeriod,
        });

    // ADX
    var adxData = TechnicalIndicatorsService.calculateADX(
      highs,
      lows,
      closes,
      config.adxPeriod,
    );

    // Squeeze Momentum
    List<double?> squeeze = TechnicalIndicatorsService.calculateSqueezeMomentum(
      highs,
      lows,
      closes,
    );

    // ATR (para stops dinámicos)
    var atrData = TechnicalIndicatorsService.calculateATR(
      highs,
      lows,
      closes,
      14,
    );

    // RSI (sobrecompra/sobreventa)
    List<double?> rsi = TechnicalIndicatorsService.calculateRSI(closes, 14);

    // MACD (confirmación de momentum)
    var macdData = TechnicalIndicatorsService.calculateMACD(closes);

    return {
      'emas': emas,
      'adx': adxData,
      'squeeze': squeeze,
      'atr': atrData,
      'rsi': rsi,
      'macd': macdData,
      'volumes': candles.map((c) => c.volume).toList(),
      'closes': closes,
    };
  }

  // ============================================
  // EVALUACIÓN DE CONDICIONES
  // ============================================

  SignalEvaluation _evaluateSignalConditions({
    required List<double> closes,
    required List<double> highs,
    required List<double> lows,
    required List<double> volumes,
    required Map<String, dynamic> indicators,
  }) {
    // Obtener últimos valores (offset 0 = vela actual, 1 = anterior, etc.)
    int lastIndex = closes.length - 1;

    // --- EMAs ---
    List<double?> ema9 = indicators['emas']['ema9']!;
    List<double?> ema20 = indicators['emas']['ema20']!;
    List<double?> ema50 = indicators['emas']['ema50']!;
    List<double?> ema200 = indicators['emas']['ema200']!;

    double? currentEma9 = ema9[lastIndex];
    double? currentEma20 = ema20[lastIndex];
    double? currentEma50 = ema50[lastIndex];
    double? currentEma200 = ema200[lastIndex];

    // --- ADX ---
    List<double?> adx = indicators['adx']['ADX']!;
    List<double?> plusDI = indicators['adx']['+DI']!;
    List<double?> minusDI = indicators['adx']['-DI']!;

    double? currentADX = adx[lastIndex];
    double? currentPlusDI = plusDI[lastIndex];
    double? currentMinusDI = minusDI[lastIndex];

    // --- Squeeze ---
    List<double?> squeeze = indicators['squeeze'];
    double? currentSqueeze = squeeze[lastIndex];

    // --- Volumen ---
    double currentVolume = volumes[lastIndex];
    double avgVolume =
        volumes.take(lastIndex).reduce((a, b) => a + b) /
        (lastIndex > 0 ? lastIndex : 1);

    // --- RSI ---
    List<double?> rsi = indicators['rsi'];
    double? currentRSI = rsi[lastIndex];

    // --- MACD ---
    List<double?> macdLine = indicators['macd']['MACD']!;
    List<double?> histogram = indicators['macd']['Histogram']!;
    double? currentMACD = macdLine[lastIndex];
    double? currentHistogram = histogram[lastIndex];

    // ============================================
    // EVALUAR CONDICIONES ALCISTAS (COMPRA)
    // ============================================

    // CONDICION 1: EMAs alineadas alcistas (Fuerte tendencia)
    bool emasAligned =
        currentEma9 != null &&
        currentEma20 != null &&
        currentEma50 != null &&
        currentEma200 != null &&
        currentEma9! > currentEma20! &&
        currentEma20! > currentEma50! &&
        currentEma50! > currentEma200!; // Por encima de EMA200 = bull market

    // CONDICION 2: Tendencia fuerte (ADX > 25)
    bool strongTrend = currentADX != null && currentADX! > config.adxThreshold;

    // CONDICION 3: Momentum positivo
    bool positiveMomentum = currentSqueeze != null && currentSqueeze! > 0;

    // CONDICION 4: +DI > -DI (directional movement alcista)
    bool dmBullish =
        currentPlusDI != null &&
        currentMinusDI != null &&
        currentPlusDI! > currentMinusDI!;

    // CONDICION 5: Volumen confirmando (creciendo)
    bool volumeConfirming =
        currentVolume > avgVolume * 1.2; // 20% above average

    // CONDICION 6: RSI no sobrecomprado (evitar comprar en máximos)
    bool rsiOk =
        currentRSI == null || currentRSI < 70; // < 70 = No sobrecomprado

    // CONDICION 7: MACD positivo o cruce alcista reciente
    bool macdBullish = currentMACD != null && currentMACD > 0;

    // Calcular score (0-1)
    double score = 0.0;
    List<String> reasons = [];
    List<String> warnings = [];

    // Puntuar cada condición
    if (emasAligned) {
      score += 0.30;
      reasons.add('EMAs alineadas alcistas (EMA9>20>50>200)');
    } else {
      warnings.add('EMAs no están alineadas correctamente');
    }

    if (strongTrend) {
      score += 0.25;
      reasons.add(
        'ADX > ${config.adxThreshold.toStringAsFixed(1)} (tendencia fuerte)',
      );
    } else if (currentADX != null && currentADX > 20) {
      score += 0.10; // Tendencia moderada
      reasons.add('ADX moderado (${currentADX.toStringAsFixed(1)})');
    } else {
      warnings.add(
        'ADX débil (${currentADX?.toStringAsFixed(1) ?? 'N/A'}) - tendencia no clara',
      );
    }

    if (positiveMomentum) {
      score += 0.20;
      reasons.add('Squeeze Momentum positivo (explosión alcista)');
    } else if (currentSqueeze != null && currentSqueeze == 0) {
      reasons.add('Squeeze detectado pero sin explosión aún');
    }

    if (dmBullish) {
      score += 0.10;
      reasons.add('+DI > -DI (momentum direccional alcista)');
    }

    if (volumeConfirming) {
      score += 0.05;
      reasons.add('Volumen 20% superior al promedio');
    } else {
      warnings.add('Volumen bajo - falta confirmación');
    }

    if (rsiOk) {
      score += 0.05;
      if (currentRSI != null && currentRSI < 30) {
        reasons.add(
          'RSI en zona de sobreventa (${currentRSI.toStringAsFixed(1)}) - oportunidad',
        );
      } else if (currentRSI != null) {
        reasons.add('RSI normal (${currentRSI.toStringAsFixed(1)})');
      }
    } else {
      warnings.add(
        'RSI en sobrecompra (${currentRSI?.toStringAsFixed(1)}) - riesgo',
      );
    }

    if (macdBullish) {
      score += 0.05;
      reasons.add('MACD positivo');
    }

    // Score final limitado a 1.0
    score = score.clamp(0.0, 1.0);

    // Determinar señal basada en score
    SignalType signalType;
    String primaryReason;

    if (score >= 0.75) {
      signalType = SignalType.strongBuy;
      primaryReason = 'Señal fuerte de compra - múltiples confirmadores';
    } else if (score >= 0.60) {
      signalType = SignalType.buy;
      primaryReason = 'Señal de compra - condiciones alcistas';
    } else if (score >= 0.40) {
      signalType = SignalType.hold;
      primaryReason = 'Mercado en transición - esperar confirmación';
    } else {
      signalType = SignalType.hold;
      primaryReason = 'Condiciones no favorables - no comprar';
    }

    return SignalEvaluation(
      type: signalType,
      confidence: score,
      primaryReason: primaryReason,
      detailedReasons: reasons,
      warnings: warnings,
      indicators: {
        'ADX': currentADX,
        '+DI': currentPlusDI,
        '-DI': currentMinusDI,
        'EMA9': currentEma9,
        'EMA20': currentEma20,
        'EMA50': currentEma50,
        'EMA200': currentEma200,
        'Squeeze': currentSqueeze,
        'RSI': currentRSI,
        'MACD': currentMACD,
        'Volume': currentVolume,
        'AvgVolume': avgVolume,
      },
      lastClose: closes.last,
      atr: indicators['atr']['ATR']?[lastIndex],
    );
  }

  // ============================================
  // FILTROS DE CONTEXTO DE MERCADO
  // ============================================

  SignalEvaluation _applyMarketContextFilters(SignalEvaluation evaluation) {
    // Filtrar durante período de halving (Merino recomienda no operar)
    if (config.avoidHalvingPeriod && _isNearHalving()) {
      return evaluation.copyWith(
        type: SignalType.hold,
        confidence: evaluation.confidence * 0.3, // Reducir confianza
        warnings: [
          ...evaluation.warnings,
          '⚠️ Cerca de halving - evitar operaciones',
        ],
      );
    }

    // Ajustar confianza según condiciones macro
    if (evaluation.indicators['ADX'] != null &&
        (evaluation.indicators['ADX'] as double) > 40) {
      // ADX muy alto = tendencia muy fuerte, mayor confianza
      return evaluation.copyWith(
        confidence: (evaluation.confidence + 0.1).clamp(0.0, 1.0),
        warnings: [
          ...evaluation.warnings,
          '🔥 Tendencia extremadamente fuerte',
        ],
      );
    }

    return evaluation;
  }

  /// Verifica si estamos cerca de un halving de Bitcoin
  /// Aproximación: Cada ~4 años (210,000 bloques)
  bool _isNearHalving() {
    // Fechas aproximadas de halving (históricas y futuras)
    // Basado en ~4 años ciclo
    DateTime now = DateTime.now();

    // Próximo halving estimado: Abril 2024 (pasado)
    // Siguiente: ~2028
    // Este es un placeholder - en producción usarías una API de halving countdown
    DateTime lastHalving = DateTime(2024, 4, 20); // Aproximado
    Duration timeSinceHalving = now.difference(lastHalving);

    // Evitar operar 90 días antes y 90 días después del halving
    // (Merino dijo "5 días" pero podrías extenderlo)
    bool nearHalving =
        timeSinceHalving.inDays.abs() < config.halvingAvoidanceDays;

    return nearHalving;
  }

  // ============================================
  // CONSTRUIR SEÑAL FINAL
  // ============================================

  TradingSignal _buildSignalFromEvaluation(
    SignalEvaluation evaluation,
    double currentPrice,
  ) {
    String id = 'SIG-${DateTime.now().millisecondsSinceEpoch}';

    // Calcular niveles de trade si es señal de compra
    double? entryPrice;
    double? stopLoss;
    double? takeProfit1;
    double? takeProfit2;
    double? takeProfit3;

    if (evaluation.type == SignalType.buy ||
        evaluation.type == SignalType.strongBuy) {
      // Estrategia de Merino:
      // - Entrada: Precio actual o con ligero descuento (1-2%)
      entryPrice = currentPrice;

      // Stop Loss: Basado en ATR (1.5x ATR) o % fijo (3%)
      double? atr = evaluation.atr;
      if (atr != null && atr > 0) {
        stopLoss = currentPrice - (atr * 1.5);
      } else {
        stopLoss = currentPrice * (1 - config.defaultStopLoss);
      }

      // Take Profits: Escalonados (Risk:Reward 1:3 mínimo)
      double riskPerShare = currentPrice - stopLoss!;

      // TP1: 1:1.5 → cubre comisiones + pequeño profit
      takeProfit1 = currentPrice + (riskPerShare * 1.5);

      // TP2: 1:2.5
      takeProfit2 = currentPrice + (riskPerShare * 2.5);

      // TP3: 1:4 (objetivo principal)
      takeProfit3 = currentPrice + (riskPerShare * 4.0);
    }

    return TradingSignal(
      id: id,
      type: evaluation.type,
      confidence: evaluation.confidence,
      reason: evaluation.primaryReason,
      timestamp: DateTime.now(),
      timeframe: config.primaryTimeframe,
      entryPrice: entryPrice,
      stopLoss: stopLoss,
      takeProfit1: takeProfit1,
      takeProfit2: takeProfit2,
      takeProfit3: takeProfit3,
      technicalData: evaluation.indicators,
      marketCondition: evaluation.indicators['marketCondition'] as String?,
    );
  }

  // ============================================
  // ANÁLISIS ADICIONAL
  // ============================================

  /// Evalúa la tendencia principal usando múltiples timeframes
  /// Retorna: 'bullish', 'bearish', 'neutral'
  String analyzeMultiTimeframeTrend() {
    int bullishCount = 0;
    int bearishCount = 0;

    // Analizar velas del timeframe principal
    if (_isBullish(candles))
      bullishCount++;
    else
      bearishCount++;

    // Analizar diario
    if (dailyCandles.isNotEmpty) {
      if (_isBullish(dailyCandles))
        bullishCount++;
      else
        bearishCount++;
    }

    // Analizar semanal
    if (weeklyCandles.isNotEmpty) {
      if (_isBullish(weeklyCandles))
        bullishCount++;
      else
        bearishCount++;
    }

    if (bullishCount > bearishCount) return 'bullish';
    if (bearishCount > bullishCount) return 'bearish';
    return 'neutral';
  }

  bool _isBullish(List<Candle> candles) {
    if (candles.length < 50) return false;
    List<double> closes = candles.map((c) => c.close).toList();
    var emas = TechnicalIndicatorsService.calculateMultipleEMAs(closes, {
      'ema20': 20,
      'ema50': 50,
    });
    return TechnicalIndicatorsService.areEMAsAlignedBullish(
      emaFast: emas['ema20']!,
      emaMedium: emas['ema50']!,
      emaSlow: emas['ema50']!, // reutilizar como referencia
    );
  }

  /// Calcula el riesgo de la operación (en % del capital)
  double calculateRiskPercentage(
    double entryPrice,
    double stopLoss,
    double capital,
  ) {
    double riskPerShare = (entryPrice - stopLoss).abs();
    double riskPercent = riskPerShare / entryPrice;
    return riskPercent * 100; // En porcentaje
  }

  /// Verifica si se debe evitar operar (filtros de seguridad)
  bool shouldAvoidTrading() {
    // 1. Volatilidad extrema (ATR muy alto)
    // 2. Noticias importantes (requeriría API de noticias)
    // 3. Fin de semana (mercado más lento)
    // 4. Horario de bajo volumen

    DateTime now = DateTime.now();
    // Evitar operar viernes por la tarde (fin de semana crypto)
    if (now.weekday == 5 && now.hour > 20) return true;

    return false;
  }
}

/// Clase auxiliar para evaluación intermedia
class SignalEvaluation {
  final SignalType type;
  final double confidence;
  final String primaryReason;
  final List<String> detailedReasons;
  final List<String> warnings;
  final Map<String, dynamic> indicators;
  final double lastClose;
  final double? atr;

  SignalEvaluation({
    required this.type,
    required this.confidence,
    required this.primaryReason,
    required this.detailedReasons,
    required this.warnings,
    required this.indicators,
    required this.lastClose,
    this.atr,
  });

  SignalEvaluation copyWith({
    SignalType? type,
    double? confidence,
    String? primaryReason,
    List<String>? detailedReasons,
    List<String>? warnings,
    Map<String, dynamic>? indicators,
    double? lastClose,
    double? atr,
  }) {
    return SignalEvaluation(
      type: type ?? this.type,
      confidence: confidence ?? this.confidence,
      primaryReason: primaryReason ?? this.primaryReason,
      detailedReasons: detailedReasons ?? this.detailedReasons,
      warnings: warnings ?? this.warnings,
      indicators: indicators ?? this.indicators,
      lastClose: lastClose ?? this.lastClose,
      atr: atr ?? this.atr,
    );
  }
}
