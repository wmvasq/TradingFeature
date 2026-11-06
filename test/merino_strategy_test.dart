import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:myenglishtool/trading/indicators.dart';
import 'package:myenglishtool/trading/models.dart';
import 'package:myenglishtool/trading/strategies/merino_strategy.dart';

List<Candle> candlesFromCloses(List<double> closes, {double wick = 0.3}) {
  final start = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < closes.length; i++)
      Candle(
        openTime: start.add(Duration(hours: i)),
        open: i == 0 ? closes[0] : closes[i - 1],
        high:
            [
              i == 0 ? closes[0] : closes[i - 1],
              closes[i],
            ].reduce((a, b) => a > b ? a : b) +
            wick,
        low:
            [
              i == 0 ? closes[0] : closes[i - 1],
              closes[i],
            ].reduce((a, b) => a < b ? a : b) -
            wick,
        close: closes[i],
        volume: 1,
      ),
  ];
}

/// Tendencia en escalera: [up] velas subiendo de a [step], 1 vela de respiro.
List<double> staircase(int count, {double start = 100, double step = 1}) {
  final out = <double>[start];
  for (var i = 1; i < count; i++) {
    out.add(out.last + (i % 4 == 0 ? -step * 0.5 : step));
  }
  return out;
}

void main() {
  group('indicadores', () {
    test('EMA: semilla SMA y suavizado', () {
      final values = <double>[1, 2, 3, 4, 5];
      final e = ema(values, 3);
      expect(e.take(2), [null, null]);
      expect(e[2], closeTo(2, 1e-9)); // SMA(1,2,3)
      expect(e[3], closeTo(3, 1e-9)); // (4-2)*0.5+2
      expect(e[4], closeTo(4, 1e-9));
    });

    test('ADX alto en tendencia limpia y bajo en rango', () {
      final trend = candlesFromCloses(staircase(120));
      final range = candlesFromCloses(
        List.generate(120, (i) => 100 + 3 * sin(i * 0.9) + 1.5 * sin(i * 2.3)),
      );
      expect(adx(trend, 14).last!, greaterThan(40));
      expect(adx(range, 14).last!, lessThan(20));
    });

    test('Squeeze Momentum: positivo subiendo, negativo bajando', () {
      final up = candlesFromCloses(staircase(80));
      final down = candlesFromCloses(staircase(80, start: 300, step: -1));
      expect(squeezeMomentum(up).last!, greaterThan(0));
      expect(squeezeMomentum(down).last!, lessThan(0));
    });
  });

  group('Merino', () {
    final merino = MerinoStrategy();

    test('rango lateral → sin entrada', () {
      final candles = candlesFromCloses(
        List.generate(150, (i) => 100 + (i % 6 < 3 ? 1.0 : -1.0)),
      );
      expect(merino.evaluate(candles).status, SetupStatus.none);
    });

    test('tendencia sin retroceso → esperando', () {
      final result = merino.evaluate(candlesFromCloses(staircase(150)));
      expect(result.direction, Direction.long);
      expect(result.status, SetupStatus.waiting);
    });

    test('retroceso a la EMA 10 que se agota → entrada long', () {
      final closes = staircase(150);
      final top = closes.last;
      // Corrección de 4 velas hasta la EMA 10 y vela de giro
      closes.addAll([top - 2, top - 3.5, top - 4.5, top - 5, top - 4]);
      final result = merino.evaluate(candlesFromCloses(closes));
      expect(
        result.status,
        SetupStatus.entry,
        reason: result.conditions
            .map((c) => '${c.met ? '✓' : '✗'} ${c.label}')
            .join('\n'),
      );
      expect(result.direction, Direction.long);
      expect(result.stopLoss!, lessThan(result.entry!));
      expect(result.riskReward!, closeTo(2, 1e-9));
    });

    test('tendencia bajista con shorts desactivados → sin entrada', () {
      final candles = candlesFromCloses(staircase(150, start: 400, step: -1));
      final result = MerinoStrategy(allowShorts: false).evaluate(candles);
      expect(result.direction, Direction.short);
      expect(result.status, SetupStatus.none);
    });
  });
}
