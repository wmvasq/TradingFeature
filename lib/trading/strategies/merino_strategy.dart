import 'dart:math';
import '../indicators.dart';
import '../models.dart';
import 'strategy.dart';

/// Estrategia de Jaime Merino (TradingLatino), versión mecánica:
/// 1. Tendencia: precio y EMA 10 del mismo lado de la EMA 55.
/// 2. Fuerza: ADX por encima de 23.
/// 3. Entrada en el retroceso: el precio vuelve a la EMA 10, el ADX pierde
///    pendiente (la corrección se agota) y el Squeeze Momentum gira a favor.
class MerinoStrategy implements Strategy {
  final int fastPeriod;
  final int slowPeriod;
  final int adxPeriod;
  final double adxLevel;

  /// Velas hacia atrás en las que se busca el toque a la EMA 10.
  final int pullbackLookback;

  /// Velas para medir la pendiente del ADX.
  final int slopeLookback;
  final double targetRiskReward;
  final bool allowShorts;

  MerinoStrategy({
    this.fastPeriod = 10,
    this.slowPeriod = 55,
    this.adxPeriod = 14,
    this.adxLevel = 23,
    this.pullbackLookback = 5,
    this.slopeLookback = 2,
    this.targetRiskReward = 2,
    this.allowShorts = true,
  });

  @override
  String get name => 'Merino';

  @override
  String get description =>
      'EMA 10/55 + ADX 23 + Squeeze Momentum: retroceso a favor de la tendencia';

  @override
  int get minCandles => 100;

  @override
  StrategyResult evaluate(List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult(
        status: SetupStatus.none,
        summary: 'Se necesitan al menos $minCandles velas',
      );
    }

    final closes = candles.map((c) => c.close).toList();
    final emaFast = ema(closes, fastPeriod);
    final emaSlow = ema(closes, slowPeriod);
    final adxValues = adx(candles, adxPeriod);
    final momentum = squeezeMomentum(candles);
    final lines = [
      IndicatorLine('EMA $fastPeriod', emaFast, 0xFF2196F3),
      IndicatorLine('EMA $slowPeriod', emaSlow, 0xFFFF9800),
    ];

    final n = candles.length - 1;
    final last = candles[n];
    final fast = emaFast[n]!;
    final slow = emaSlow[n]!;

    final Direction? trend = last.close > slow && fast > slow
        ? Direction.long
        : last.close < slow && fast < slow
        ? Direction.short
        : null;

    if (trend == null) {
      return StrategyResult(
        status: SetupStatus.none,
        summary: 'Sin tendencia clara: el precio está entre las EMAs',
        conditions: [
          Condition(
            'Tendencia definida por EMA $fastPeriod/$slowPeriod',
            false,
          ),
        ],
        lines: lines,
      );
    }
    if (trend == Direction.short && !allowShorts) {
      return StrategyResult(
        status: SetupStatus.none,
        direction: trend,
        summary: 'Tendencia bajista: la estrategia solo opera largos',
        lines: lines,
      );
    }

    final isLong = trend == Direction.long;
    final adxNow = adxValues[n]!;
    final adxPrev = adxValues[n - slopeLookback]!;
    final momNow = momentum[n]!;
    final momPrev = momentum[n - 1]!;

    var pullback = false;
    for (var k = n - pullbackLookback + 1; k <= n && !pullback; k++) {
      pullback = isLong
          ? candles[k].low <= emaFast[k]!
          : candles[k].high >= emaFast[k]!;
    }

    final trendCondition = Condition(
      isLong
          ? 'Tendencia alcista: precio y EMA $fastPeriod sobre EMA $slowPeriod'
          : 'Tendencia bajista: precio y EMA $fastPeriod bajo EMA $slowPeriod',
      true,
    );
    final strengthCondition = Condition(
      'ADX > ${adxLevel.toStringAsFixed(0)} (${adxNow.toStringAsFixed(1)})',
      adxNow > adxLevel,
    );
    final pullbackCondition = Condition(
      'Retroceso a la EMA $fastPeriod en las últimas $pullbackLookback velas',
      pullback,
    );
    final slopeCondition = Condition(
      'ADX con pendiente negativa: la corrección pierde fuerza '
      '(${adxPrev.toStringAsFixed(1)} → ${adxNow.toStringAsFixed(1)})',
      adxNow < adxPrev,
    );
    // A favor, o en contra pero perdiendo fuerza (el histograma gira)
    final momentumCondition = Condition(
      'Squeeze Momentum a favor o perdiendo fuerza en contra '
      '(${_fmt(momPrev)} → ${_fmt(momNow)})',
      isLong ? momNow > 0 || momNow > momPrev : momNow < 0 || momNow < momPrev,
    );
    final conditions = [
      trendCondition,
      strengthCondition,
      pullbackCondition,
      slopeCondition,
      momentumCondition,
      Condition(
        isLong
            ? 'La vela cierra sobre la EMA $fastPeriod'
            : 'La vela cierra bajo la EMA $fastPeriod',
        isLong ? last.close > fast : last.close < fast,
        required: false,
      ),
    ];

    if (!strengthCondition.met) {
      return StrategyResult(
        status: SetupStatus.none,
        direction: trend,
        summary:
            'ADX bajo ${adxLevel.toStringAsFixed(0)}: la tendencia no tiene fuerza',
        conditions: conditions,
        lines: lines,
      );
    }

    final allMet = conditions.where((c) => c.required).every((c) => c.met);
    if (!allMet) {
      final waitingFor = !pullback
          ? 'retroceso a la EMA $fastPeriod (${_fmt(fast)})'
          : !slopeCondition.met
          ? 'que el ADX pierda pendiente'
          : 'que el momentum en contra pierda fuerza';
      return StrategyResult(
        status: SetupStatus.waiting,
        direction: trend,
        summary:
            'Tendencia ${isLong ? 'alcista' : 'bajista'} con fuerza: esperando $waitingFor',
        conditions: conditions,
        lines: lines,
      );
    }

    // SL detrás del extremo del retroceso; TP a R:R fijo
    final recent = candles.sublist(n - 2 * pullbackLookback + 1);
    final buffer = atr(candles, 14) * 0.2;
    final entry = last.close;
    final stopLoss = isLong
        ? recent.map((c) => c.low).reduce(min) - buffer
        : recent.map((c) => c.high).reduce(max) + buffer;
    final takeProfit = entry + (entry - stopLoss) * targetRiskReward;

    return StrategyResult(
      status: SetupStatus.entry,
      direction: trend,
      summary: isLong ? 'Entrada LONG' : 'Entrada SHORT',
      entry: entry,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      conditions: conditions,
      lines: lines,
    );
  }

  static String _fmt(double v) =>
      v.toStringAsFixed(v.abs() >= 100 ? 1 : (v.abs() >= 1 ? 2 : 4));
}
