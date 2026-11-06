import 'dart:math';
import '../indicators.dart';
import '../models.dart';
import 'strategy.dart';

/// Smart Money Concepts:
/// 1. Estructura: BOS / CHoCH cuando una vela CIERRA más allá del último swing.
/// 2. Order block: la vela con el extremo del impulso que rompió la estructura.
/// 3. Entrada: primer retesteo del OB (sin mitigar) a favor de la estructura,
///    en zona de descuento/premium y con riesgo/beneficio mínimo.
class SmcStrategy implements Strategy {
  /// Velas a cada lado para confirmar un swing high/low.
  final int swingLength;
  final double minRiskReward;

  SmcStrategy({this.swingLength = 3, this.minRiskReward = 1.5});

  @override
  String get name => 'SMC';

  @override
  String get description =>
      'Estructura (BOS/CHoCH) + retesteo de Order Block en descuento/premium';

  @override
  int get minCandles => 50;

  @override
  StrategyResult evaluate(List<Candle> candles) {
    if (candles.length < minCandles) {
      return StrategyResult(
        status: SetupStatus.none,
        summary: 'Se necesitan al menos $minCandles velas',
      );
    }

    final structure = _analyzeStructure(candles);
    final levels = [
      for (final b in structure.breaks.reversed.take(4))
        PriceLevel(
          label: b.choch ? 'CHoCH' : 'BOS',
          price: b.price,
          fromIndex: b.swingIndex,
          toIndex: b.index,
          bias: b.direction,
        ),
    ];

    final trend = structure.trend;
    if (trend == null) {
      return StrategyResult(
        status: SetupStatus.none,
        summary: 'Sin estructura definida todavía',
        levels: levels,
      );
    }

    final isLong = trend == Direction.long;
    final last = candles.length - 1;
    final fvgZones = _unfilledFvgs(candles, trend).take(3).toList();

    // OBs del tramo actual de tendencia (desde el último CHoCH)
    final candidates =
        structure.orderBlocks
            .where(
              (ob) =>
                  ob.direction == trend && ob.createdAt >= structure.trendStart,
            )
            .map((ob) => _OrderBlockState.track(ob, candles))
            .where(
              (s) =>
                  !s.invalidated &&
                  (s.touchIndex == null || s.touchIndex == last),
            )
            .toList()
          // El más cercano al precio primero
          ..sort(
            (a, b) => isLong
                ? b.ob.top.compareTo(a.ob.top)
                : a.ob.bottom.compareTo(b.ob.bottom),
          );

    final structureCondition = Condition(
      'Estructura ${isLong ? 'alcista' : 'bajista'} '
      '(último ${structure.breaks.last.choch ? 'CHoCH' : 'BOS'})',
      true,
    );

    if (candidates.isEmpty) {
      return StrategyResult(
        status: SetupStatus.none,
        direction: trend,
        summary:
            'Order blocks mitigados o invalidados: esperar nueva estructura',
        conditions: [
          structureCondition,
          Condition(
            'Order block ${isLong ? 'alcista' : 'bajista'} sin mitigar',
            false,
          ),
        ],
        zones: fvgZones,
        levels: levels,
      );
    }

    final setup = candidates.first;
    final ob = setup.ob;
    final retestNow = setup.touchIndex == last;
    final lastCandle = candles[last];

    final buffer = atr(candles, 14) * 0.2;
    final double entry = retestNow
        ? lastCandle.close
        : (isLong ? ob.top : ob.bottom);
    final double stopLoss = isLong ? ob.bottom - buffer : ob.top + buffer;
    // Objetivo: la liquidez en el extremo del impulso
    final double takeProfit = isLong
        ? candles.sublist(ob.index).map((c) => c.high).reduce(max)
        : candles.sublist(ob.index).map((c) => c.low).reduce(min);

    final risk = (entry - stopLoss).abs();
    final reward = isLong ? takeProfit - entry : entry - takeProfit;
    final rr = risk > 0 && reward > 0 ? reward / risk : 0.0;

    final equilibrium = isLong
        ? (ob.bottom + takeProfit) / 2
        : (ob.top + takeProfit) / 2;
    final inDiscountPremium = isLong
        ? entry < equilibrium
        : entry > equilibrium;

    final retestCondition = Condition(
      retestNow
          ? 'Retesteo del order block en la última vela'
          : 'Retesteo del order block (pendiente)',
      retestNow,
    );
    final conditions = [
      structureCondition,
      retestCondition,
      Condition(
        isLong
            ? 'Precio en descuento (< 50% del impulso)'
            : 'Precio en premium (> 50% del impulso)',
        inDiscountPremium,
      ),
      Condition(
        'Riesgo/beneficio ≥ ${minRiskReward.toStringAsFixed(1)} '
        '(${rr.toStringAsFixed(2)})',
        rr >= minRiskReward,
      ),
      Condition('Impulso con FVG (desplazamiento)', ob.hasFvg, required: false),
      if (retestNow)
        Condition(
          'Vela de rechazo (cierra a favor)',
          isLong ? lastCandle.isBullish : lastCandle.isBearish,
          required: false,
        ),
    ];

    final requiredMet = conditions.where((c) => c.required).every((c) => c.met);
    final requiredExceptRetest = conditions
        .where((c) => c.required && c != retestCondition)
        .every((c) => c.met);

    final SetupStatus status;
    final String summary;
    if (requiredMet) {
      status = SetupStatus.entry;
      summary = isLong ? 'Entrada LONG' : 'Entrada SHORT';
    } else if (!retestNow && requiredExceptRetest) {
      status = SetupStatus.waiting;
      summary =
          'Esperando retesteo del OB en ${_fmt(ob.bottom)} – ${_fmt(ob.top)}';
    } else {
      status = SetupStatus.none;
      summary = 'Hay order block pero el setup no cumple las condiciones';
    }

    return StrategyResult(
      status: status,
      direction: trend,
      summary: summary,
      entry: entry,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      conditions: conditions,
      zones: [
        PriceZone(
          label: 'OB',
          top: ob.top,
          bottom: ob.bottom,
          startIndex: ob.index,
          bias: trend,
        ),
        ...fvgZones,
      ],
      levels: levels,
    );
  }

  // ============================================
  // Estructura de mercado
  // ============================================

  _Structure _analyzeStructure(List<Candle> c) {
    final L = swingLength;
    final breaks = <_Break>[];
    final orderBlocks = <_OrderBlock>[];
    _Swing? swingHigh;
    _Swing? swingLow;
    Direction? trend;
    var trendStart = 0;

    for (var i = 0; i < c.length; i++) {
      // Un pivote en p se confirma cuando ya hay L velas a su derecha
      final p = i - L;
      if (p >= L) {
        if (_isPivot(c, p, L, high: true)) swingHigh = _Swing(p, c[p].high);
        if (_isPivot(c, p, L, high: false)) swingLow = _Swing(p, c[p].low);
      }

      if (swingHigh != null && c[i].close > swingHigh.price) {
        final choch = trend == Direction.short;
        if (choch || trend == null) trendStart = i;
        breaks.add(
          _Break(i, swingHigh.index, swingHigh.price, Direction.long, choch),
        );
        orderBlocks.add(
          _OrderBlock.fromImpulse(c, swingHigh.index, i, Direction.long),
        );
        trend = Direction.long;
        swingHigh = null;
      } else if (swingLow != null && c[i].close < swingLow.price) {
        final choch = trend == Direction.long;
        if (choch || trend == null) trendStart = i;
        breaks.add(
          _Break(i, swingLow.index, swingLow.price, Direction.short, choch),
        );
        orderBlocks.add(
          _OrderBlock.fromImpulse(c, swingLow.index, i, Direction.short),
        );
        trend = Direction.short;
        swingLow = null;
      }
    }

    return _Structure(trend, trendStart, breaks, orderBlocks);
  }

  bool _isPivot(List<Candle> c, int p, int L, {required bool high}) {
    for (var k = p - L; k <= p + L; k++) {
      if (k == p) continue;
      if (high ? c[k].high > c[p].high : c[k].low < c[p].low) return false;
    }
    return true;
  }

  /// FVGs a favor de [direction] que el precio aún no ha llenado, más recientes primero.
  List<PriceZone> _unfilledFvgs(List<Candle> c, Direction direction) {
    final result = <PriceZone>[];
    for (var k = c.length - 1; k >= 2; k--) {
      final isLong = direction == Direction.long;
      final top = isLong ? c[k].low : c[k - 2].low;
      final bottom = isLong ? c[k - 2].high : c[k].high;
      if (top <= bottom) continue;

      var filled = false;
      for (var j = k + 1; j < c.length && !filled; j++) {
        filled = isLong ? c[j].low <= bottom : c[j].high >= top;
      }
      if (!filled) {
        result.add(
          PriceZone(
            label: 'FVG',
            top: top,
            bottom: bottom,
            startIndex: k - 1,
            bias: direction,
          ),
        );
      }
    }
    return result;
  }

  static String _fmt(double v) => v.toStringAsFixed(v >= 100 ? 2 : 4);
}

class _Swing {
  final int index;
  final double price;
  const _Swing(this.index, this.price);
}

class _Break {
  final int index;
  final int swingIndex;
  final double price;
  final Direction direction;
  final bool choch;
  const _Break(
    this.index,
    this.swingIndex,
    this.price,
    this.direction,
    this.choch,
  );
}

class _OrderBlock {
  final int index;
  final int createdAt;
  final double top;
  final double bottom;
  final Direction direction;
  final bool hasFvg;

  const _OrderBlock(
    this.index,
    this.createdAt,
    this.top,
    this.bottom,
    this.direction,
    this.hasFvg,
  );

  /// OB = vela con el mínimo (long) o máximo (short) entre el swing roto y la
  /// vela que lo rompió.
  factory _OrderBlock.fromImpulse(
    List<Candle> c,
    int swingIndex,
    int breakIndex,
    Direction direction,
  ) {
    final isLong = direction == Direction.long;
    var m = swingIndex;
    for (var k = swingIndex; k < breakIndex; k++) {
      if (isLong ? c[k].low < c[m].low : c[k].high > c[m].high) m = k;
    }

    var hasFvg = false;
    for (var k = m + 2; k <= breakIndex && !hasFvg; k++) {
      hasFvg = isLong ? c[k].low > c[k - 2].high : c[k].high < c[k - 2].low;
    }

    return _OrderBlock(m, breakIndex, c[m].high, c[m].low, direction, hasFvg);
  }
}

class _OrderBlockState {
  final _OrderBlock ob;
  final int? touchIndex;
  final bool invalidated;

  const _OrderBlockState(this.ob, this.touchIndex, this.invalidated);

  /// Recorre las velas posteriores al OB: primer toque y si un cierre lo invalidó.
  factory _OrderBlockState.track(_OrderBlock ob, List<Candle> c) {
    final isLong = ob.direction == Direction.long;
    int? touch;
    for (var k = ob.createdAt + 1; k < c.length; k++) {
      if (isLong ? c[k].close < ob.bottom : c[k].close > ob.top) {
        return _OrderBlockState(ob, touch ?? k, true);
      }
      if (touch == null &&
          (isLong ? c[k].low <= ob.top : c[k].high >= ob.bottom)) {
        touch = k;
      }
    }
    return _OrderBlockState(ob, touch, false);
  }
}

class _Structure {
  final Direction? trend;
  final int trendStart;
  final List<_Break> breaks;
  final List<_OrderBlock> orderBlocks;

  const _Structure(this.trend, this.trendStart, this.breaks, this.orderBlocks);
}
