import 'package:flutter/material.dart';

/// Modelo que representa una vela (candlestick) de datos OHLCV
class Candle {
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final DateTime timestamp;
  final String interval; // '1m', '5m', '15m', '1h', '4h', '1d', etc.

  Candle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.timestamp,
    required this.interval,
  });

  /// Crea una vela desde los datos de Binance API
  factory Candle.fromBinance(List<dynamic> data, String interval) {
    return Candle(
      open: double.parse(data[1]),
      high: double.parse(data[2]),
      low: double.parse(data[3]),
      close: double.parse(data[4]),
      volume: double.parse(data[5]),
      timestamp: DateTime.fromMillisecondsSinceEpoch(data[0]),
      interval: interval,
    );
  }

  /// Crea una vela desde datos de CoinGecko (formato diferente)
  factory Candle.fromCoinGecko(List<dynamic> data, String interval) {
    return Candle(
      open: (data[1] as num).toDouble(),
      high: (data[2] as num).toDouble(),
      low: (data[3] as num).toDouble(),
      close: (data[4] as num).toDouble(),
      volume: (data[5] as num? ?? 0).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch((data[0] as num).toInt()),
      interval: interval,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'volume': volume,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'interval': interval,
    };
  }

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      volume: (json['volume'] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      interval: json['interval'],
    );
  }

  @override
  String toString() {
    return 'Candle(${timestamp.toString().substring(0, 19)}, O:${open.toStringAsFixed(2)}, H:${high.toStringAsFixed(2)}, L:${low.toStringAsFixed(2)}, C:${close.toStringAsFixed(2)})';
  }
}

/// Enum para los tipos de señales de trading
enum SignalType {
  buy, // Señal de compra fuerte
  sell, // Señal de venta (Merino recomienda evitarla en BTC)
  hold, // Mantener posición actual
  strongBuy, // Compra fuerte (alta confianza)
  caution, // Precaución - señal débil
}

/// Modelo que representa una señal de trading generada
class TradingSignal {
  final String id;
  final SignalType type;
  final double confidence; // 0.0 a 1.0
  final String reason; // Explicación técnica de la señal
  final DateTime timestamp;
  final String timeframe; // '1h', '4h', '1d', etc.

  // Niveles sugeridos por la estrategia de Merino
  final double? entryPrice; // Precio de entrada recomendado
  final double? stopLoss; // Stop loss sugerido
  final double? takeProfit1; // Primer objetivo de ganancia
  final double? takeProfit2; // Segundo objetivo
  final double? takeProfit3; // Tercer objetivo

  // Datos técnicos que generaron la señal
  final Map<String, dynamic> technicalData;
  final bool isHalvingPeriod; // ¿Estamos cerca de un halving?
  final bool isEtfApproval; // ¿Hay aprobación de ETF?
  final String? marketCondition; // 'bullish', 'bearish', 'sideways'

  // Análisis de la señal
  final List<String> detailedReasons;
  final List<String> warnings;
  final double? atr;

  TradingSignal({
    required this.id,
    required this.type,
    required this.confidence,
    required this.reason,
    required this.timestamp,
    required this.timeframe,
    this.entryPrice,
    this.stopLoss,
    this.takeProfit1,
    this.takeProfit2,
    this.takeProfit3,
    required this.technicalData,
    this.isHalvingPeriod = false,
    this.isEtfApproval = false,
    this.marketCondition,
    this.detailedReasons = const [],
    this.warnings = const [],
    this.atr,
  });

  /// Determina si la señal es confiable para actuar
  bool get isReliable => confidence >= 0.7 && type == SignalType.buy;

  /// Calcula el riesgo/recompensa basado en SL y TP1
  double? get riskRewardRatio {
    if (entryPrice == null || stopLoss == null || takeProfit1 == null)
      return null;
    double risk = (entryPrice! - stopLoss!).abs() / entryPrice!;
    double reward = (takeProfit1! - entryPrice!).abs() / entryPrice!;
    return reward / risk;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'confidence': confidence,
      'reason': reason,
      'timestamp': timestamp.toIso8601String(),
      'timeframe': timeframe,
      'entryPrice': entryPrice,
      'stopLoss': stopLoss,
      'takeProfit1': takeProfit1,
      'takeProfit2': takeProfit2,
      'takeProfit3': takeProfit3,
      'technicalData': technicalData,
      'isHalvingPeriod': isHalvingPeriod,
      'isEtfApproval': isEtfApproval,
      'marketCondition': marketCondition,
      'detailedReasons': detailedReasons,
      'warnings': warnings,
      'atr': atr,
    };
  }

  factory TradingSignal.fromJson(Map<String, dynamic> json) {
    return TradingSignal(
      id: json['id'],
      type: SignalType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => SignalType.hold,
      ),
      confidence: (json['confidence'] as num).toDouble(),
      reason: json['reason'],
      timestamp: DateTime.parse(json['timestamp']),
      timeframe: json['timeframe'],
      entryPrice: json['entryPrice']?.toDouble(),
      stopLoss: json['stopLoss']?.toDouble(),
      takeProfit1: json['takeProfit1']?.toDouble(),
      takeProfit2: json['takeProfit2']?.toDouble(),
      takeProfit3: json['takeProfit3']?.toDouble(),
      technicalData: Map<String, dynamic>.from(json['technicalData'] ?? {}),
      isHalvingPeriod: json['isHalvingPeriod'] ?? false,
      isEtfApproval: json['isEtfApproval'] ?? false,
      marketCondition: json['marketCondition'],
      detailedReasons: List<String>.from(json['detailedReasons'] ?? []),
      warnings: List<String>.from(json['warnings'] ?? []),
      atr: json['atr']?.toDouble(),
    );
  }

  @override
  String toString() {
    String emoji = type == SignalType.buy
        ? '🟢'
        : type == SignalType.sell
        ? '🔴'
        : type == SignalType.strongBuy
        ? '🚀'
        : '🟡';

    return '$emoji SEÑAL [${type.toString().toUpperCase()}] - Confianza: ${(confidence * 100).toStringAsFixed(1)}%\n'
        'Razón: $reason\n'
        'Entrada: \$${entryPrice?.toStringAsFixed(2) ?? "N/A"} | '
        'SL: \$${stopLoss?.toStringAsFixed(2) ?? "N/A"} | '
        'TP1: \$${takeProfit1?.toStringAsFixed(2) ?? "N/A"}';
  }
}

/// Modelo de configuración del sistema de trading
class TradingConfig {
  // Configuración de capital según estrategia Merino
  final double totalCapital; // Capital total asignado
  final double percentLongTerm; // % para largo plazo (40%)
  final double percentWeekly; // % para operaciones semanales (30%)
  final double percentDaily; // % para day trading (20%)
  final double percentFutures; // % para futuros (10%)

  // Configuración de indicadores
  final int emaFastPeriod; // EMA rápida (9)
  final int emaMediumPeriod; // EMA media (20)
  final int emaSlowPeriod; // EMA lenta (50)
  final int emaLongPeriod; // EMA muy lenta (200)
  final int adxPeriod; // Período ADX (14)
  final double adxThreshold; // Umbral ADX para tendencia fuerte (25)

  // Configuración de gestión de riesgo
  final double maxRiskPerTrade; // % máximo de riesgo por operación (2%)
  final double defaultStopLoss; // % SL por defecto (3%)
  final double riskRewardRatio; // Ratio mínimo riesgo/recompensa (3:1)
  final double maxDailyLoss; // % máximo de pérdida diaria (5%)

  // Configuración de timeframes
  final List<String> monitoredTimeframes; // ['15m', '1h', '4h', '1d']
  final String primaryTimeframe; // Timeframe principal para señales

  // Filtros de mercado
  final bool avoidHalvingPeriod; // Evitar operar 5 días antes/después halving
  final int halvingAvoidanceDays; // Días de evitación (5)

  TradingConfig({
    this.totalCapital = 10000.0,
    this.percentLongTerm = 0.40,
    this.percentWeekly = 0.30,
    this.percentDaily = 0.20,
    this.percentFutures = 0.10,
    this.emaFastPeriod = 9,
    this.emaMediumPeriod = 20,
    this.emaSlowPeriod = 50,
    this.emaLongPeriod = 200,
    this.adxPeriod = 14,
    this.adxThreshold = 25.0,
    this.maxRiskPerTrade = 0.02,
    this.defaultStopLoss = 0.03,
    this.riskRewardRatio = 3.0,
    this.maxDailyLoss = 0.05,
    this.monitoredTimeframes = const ['15m', '1h', '4h', '1d'],
    this.primaryTimeframe = '1h',
    this.avoidHalvingPeriod = true,
    this.halvingAvoidanceDays = 5,
  });

  /// Calcula el monto de capital disponible por tipo de trading
  Map<String, double> get capitalAllocation {
    return {
      'longTerm': totalCapital * percentLongTerm,
      'weekly': totalCapital * percentWeekly,
      'daily': totalCapital * percentDaily,
      'futures': totalCapital * percentFutures,
    };
  }

  /// Capital asignado a trading diario (el más activo)
  double get activeTradingCapital => totalCapital * percentDaily;

  Map<String, dynamic> toJson() {
    return {
      'totalCapital': totalCapital,
      'percentLongTerm': percentLongTerm,
      'percentWeekly': percentWeekly,
      'percentDaily': percentDaily,
      'percentFutures': percentFutures,
      'emaFastPeriod': emaFastPeriod,
      'emaMediumPeriod': emaMediumPeriod,
      'emaSlowPeriod': emaSlowPeriod,
      'emaLongPeriod': emaLongPeriod,
      'adxPeriod': adxPeriod,
      'adxThreshold': adxThreshold,
      'maxRiskPerTrade': maxRiskPerTrade,
      'defaultStopLoss': defaultStopLoss,
      'riskRewardRatio': riskRewardRatio,
      'maxDailyLoss': maxDailyLoss,
      'monitoredTimeframes': monitoredTimeframes,
      'primaryTimeframe': primaryTimeframe,
      'avoidHalvingPeriod': avoidHalvingPeriod,
      'halvingAvoidanceDays': halvingAvoidanceDays,
    };
  }

  factory TradingConfig.fromJson(Map<String, dynamic> json) {
    return TradingConfig(
      totalCapital: (json['totalCapital'] as num).toDouble(),
      percentLongTerm: (json['percentLongTerm'] as num).toDouble(),
      percentWeekly: (json['percentWeekly'] as num).toDouble(),
      percentDaily: (json['percentDaily'] as num).toDouble(),
      percentFutures: (json['percentFutures'] as num).toDouble(),
      emaFastPeriod: json['emaFastPeriod'],
      emaMediumPeriod: json['emaMediumPeriod'],
      emaSlowPeriod: json['emaSlowPeriod'],
      emaLongPeriod: json['emaLongPeriod'],
      adxPeriod: json['adxPeriod'],
      adxThreshold: (json['adxThreshold'] as num).toDouble(),
      maxRiskPerTrade: (json['maxRiskPerTrade'] as num).toDouble(),
      defaultStopLoss: (json['defaultStopLoss'] as num).toDouble(),
      riskRewardRatio: (json['riskRewardRatio'] as num).toDouble(),
      maxDailyLoss: (json['maxDailyLoss'] as num).toDouble(),
      monitoredTimeframes: List<String>.from(json['monitoredTimeframes']),
      primaryTimeframe: json['primaryTimeframe'],
      avoidHalvingPeriod: json['avoidHalvingPeriod'],
      halvingAvoidanceDays: json['halvingAvoidanceDays'],
    );
  }

  TradingConfig copyWith({
    double? totalCapital,
    double? percentLongTerm,
    double? percentWeekly,
    double? percentDaily,
    double? percentFutures,
    int? emaFastPeriod,
    int? emaMediumPeriod,
    int? emaSlowPeriod,
    int? emaLongPeriod,
    int? adxPeriod,
    double? adxThreshold,
    double? maxRiskPerTrade,
    double? defaultStopLoss,
    double? riskRewardRatio,
    double? maxDailyLoss,
    List<String>? monitoredTimeframes,
    String? primaryTimeframe,
    bool? avoidHalvingPeriod,
    int? halvingAvoidanceDays,
  }) {
    return TradingConfig(
      totalCapital: totalCapital ?? this.totalCapital,
      percentLongTerm: percentLongTerm ?? this.percentLongTerm,
      percentWeekly: percentWeekly ?? this.percentWeekly,
      percentDaily: percentDaily ?? this.percentDaily,
      percentFutures: percentFutures ?? this.percentFutures,
      emaFastPeriod: emaFastPeriod ?? this.emaFastPeriod,
      emaMediumPeriod: emaMediumPeriod ?? this.emaMediumPeriod,
      emaSlowPeriod: emaSlowPeriod ?? this.emaSlowPeriod,
      emaLongPeriod: emaLongPeriod ?? this.emaLongPeriod,
      adxPeriod: adxPeriod ?? this.adxPeriod,
      adxThreshold: adxThreshold ?? this.adxThreshold,
      maxRiskPerTrade: maxRiskPerTrade ?? this.maxRiskPerTrade,
      defaultStopLoss: defaultStopLoss ?? this.defaultStopLoss,
      riskRewardRatio: riskRewardRatio ?? this.riskRewardRatio,
      maxDailyLoss: maxDailyLoss ?? this.maxDailyLoss,
      monitoredTimeframes: monitoredTimeframes ?? this.monitoredTimeframes,
      primaryTimeframe: primaryTimeframe ?? this.primaryTimeframe,
      avoidHalvingPeriod: avoidHalvingPeriod ?? this.avoidHalvingPeriod,
      halvingAvoidanceDays: halvingAvoidanceDays ?? this.halvingAvoidanceDays,
    );
  }
}
