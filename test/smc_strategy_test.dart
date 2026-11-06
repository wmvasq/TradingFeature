import 'package:flutter_test/flutter_test.dart';
import 'package:myenglishtool/trading/models.dart';
import 'package:myenglishtool/trading/strategies/smc_strategy.dart';

/// Construye velas a partir de una lista de cierres: cada vela abre en el
/// cierre anterior y tiene una mecha de [wick] a cada lado.
List<Candle> candlesFromCloses(List<double> closes, {double wick = 0.2}) {
  final start = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < closes.length; i++)
      Candle(
        openTime: start.add(Duration(hours: i)),
        open: i == 0 ? closes[0] : closes[i - 1],
        high:
            (i == 0 ? closes[0] : closes[i - 1]).clamp(
              closes[i],
              double.infinity,
            ) +
            wick,
        low:
            (i == 0 ? closes[0] : closes[i - 1]).clamp(
              double.negativeInfinity,
              closes[i],
            ) -
            wick,
        close: closes[i],
        volume: 1,
      ),
  ];
}

/// Interpola linealmente entre puntos clave: [(100, 0), (110, 10)] → 11 cierres.
List<double> path(List<double> pivots, {int stepsPerLeg = 6}) {
  final out = <double>[pivots.first];
  for (var p = 1; p < pivots.length; p++) {
    for (var s = 1; s <= stepsPerLeg; s++) {
      out.add(pivots[p - 1] + (pivots[p] - pivots[p - 1]) * s / stepsPerLeg);
    }
  }
  return out;
}

void main() {
  final smc = SmcStrategy();

  test('pocas velas → sin entrada', () {
    final result = smc.evaluate(candlesFromCloses(path([100, 110])));
    expect(result.status, SetupStatus.none);
  });

  test('tendencia alcista con retesteo del OB → entrada long', () {
    // Rango, impulso que rompe el máximo, nuevo máximo y retroceso al OB.
    final closes = path([
      100, 104, 101, 105, 102, 106, 103, 107, 104, 108, // estructura previa
      105, 109, 100, // barrida hasta el mínimo (origen del OB)
      125, // impulso que rompe el swing high (BOS)
      118, 130, // mínimo más alto (OB del último BOS) y nuevo máximo
    ]);
    // Retroceso hasta el OB de 118 sin romper ese mínimo
    final candles = candlesFromCloses([...closes, 126, 122, 119]);

    final result = smc.evaluate(candles);
    expect(result.direction, Direction.long);
    expect(
      result.status,
      SetupStatus.entry,
      reason: result.conditions
          .map((c) => '${c.met ? '✓' : '✗'} ${c.label}')
          .join('\n'),
    );
    expect(result.stopLoss!, lessThan(result.entry!));
    expect(result.takeProfit!, greaterThan(result.entry!));
    expect(result.riskReward!, greaterThanOrEqualTo(1.5));
  });

  test('tendencia alcista sin retroceso → esperando retesteo', () {
    final closes = path([
      100,
      104,
      101,
      105,
      102,
      106,
      103,
      107,
      104,
      108,
      105,
      109,
      100,
      125,
      118,
      130,
    ]);
    final result = smc.evaluate(candlesFromCloses(closes));
    expect(result.direction, Direction.long);
    expect(result.status, SetupStatus.waiting);
  });

  test('cierre por debajo del OB lo invalida', () {
    final closes = path([
      100,
      104,
      101,
      105,
      102,
      106,
      103,
      107,
      104,
      108,
      105,
      109,
      100,
      125,
      118,
      130,
    ]);
    final candles = candlesFromCloses([...closes, 115, 105, 99, 97]);
    final result = smc.evaluate(candles);
    expect(result.status, isNot(SetupStatus.entry));
  });

  test('estructura bajista con retesteo del OB → entrada short', () {
    final closes = path([
      200, 196, 199, 195, 198, 194, 197, 193, 196, 192,
      195, 191, 200, // barrida al máximo (origen del OB bajista)
      175, // impulso que rompe el swing low
      182, 170, // máximo más bajo (OB del último BOS) y nuevo mínimo
    ]);
    final candles = candlesFromCloses([...closes, 174, 178, 181]);

    final result = smc.evaluate(candles);
    expect(result.direction, Direction.short);
    expect(
      result.status,
      SetupStatus.entry,
      reason: result.conditions
          .map((c) => '${c.met ? '✓' : '✗'} ${c.label}')
          .join('\n'),
    );
    expect(result.stopLoss!, greaterThan(result.entry!));
    expect(result.takeProfit!, lessThan(result.entry!));
  });
}
