import 'package:flutter_test/flutter_test.dart';
import 'package:myenglishtool/trading/backtest.dart';
import 'package:myenglishtool/trading/models.dart';
import 'package:myenglishtool/trading/setups.dart';
import 'package:myenglishtool/trading/strategies/strategy.dart';

/// Da entrada LONG (SL -1, TP +2 respecto al cierre) cuando la última vela
/// tiene el volumen marcado con 1; si no, "sin entrada".
class _FakeStrategy implements Strategy {
  int evaluations = 0;

  @override
  String get name => 'Fake';
  @override
  String get description => '';
  @override
  int get minCandles => 3;

  @override
  StrategyResult evaluate(List<Candle> candles) {
    evaluations++;
    final last = candles.last;
    if (last.volume != 1) {
      return const StrategyResult(status: SetupStatus.none, summary: '');
    }
    return StrategyResult(
      status: SetupStatus.entry,
      direction: Direction.long,
      summary: 'Entrada LONG',
      entry: last.close,
      stopLoss: last.close - 1,
      takeProfit: last.close + 2,
    );
  }
}

/// [specs]: (high, low, close, señal).
List<Candle> candles(List<(double, double, double, bool)> specs) => [
  for (var i = 0; i < specs.length; i++)
    Candle(
      openTime: DateTime(2026, 1, 1).add(Duration(minutes: 5 * i)),
      open: specs[i].$3,
      high: specs[i].$1,
      low: specs[i].$2,
      close: specs[i].$3,
      volume: specs[i].$4 ? 1 : 0,
    ),
];

BacktestReport run(Strategy strategy, List<Candle> c, {double fee = 0}) =>
    runBacktest(
      strategy: strategy,
      candles: c,
      symbol: 'TEST',
      assetLabel: 'Test',
      interval: '5m',
      settings: BacktestSettings(window: 3, feeRate: fee),
    );

void main() {
  test('abre en la señal y cierra en TP / SL', () {
    final report = run(
      _FakeStrategy(),
      candles([
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, true), // señal: E 100, SL 99, TP 102
        (102.5, 100, 102, false), // TP → +2 R
        (102.5, 101.5, 102, true), // señal: E 102, SL 101, TP 104
        (102, 100.5, 101, false), // SL → -1 R
      ]),
    );
    expect(report.closed.length, 2);
    expect(report.won, 1);
    expect(report.lost, 1);
    expect(report.grossR, closeTo(1, 1e-9));
    expect(report.equity, [closeTo(2, 1e-9), closeTo(1, 1e-9)]);
    expect(report.maxDrawdownR, closeTo(1, 1e-9));
  });

  test('un trade a la vez: no evalúa ni abre mientras hay uno activo', () {
    final strategy = _FakeStrategy();
    final report = run(
      strategy,
      candles([
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, true), // abre
        (100.8, 99.5, 100, true), // señal ignorada: hay trade activo
        (100.8, 99.5, 100, true), // ignorada
        (102.5, 100, 102, false), // TP
      ]),
    );
    expect(report.trades.length, 1);
    // Evalúa en la vela de la señal y en la del TP (al quedar libre)
    expect(strategy.evaluations, 2);
  });

  test('comisión en R: 2 × comisión × entrada / riesgo', () {
    final report = run(
      _FakeStrategy(),
      candles([
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, true),
        (102.5, 100, 102, false),
      ]),
      fee: 0.001, // 0,1 % por lado
    );
    // 2 × 0,001 × 100 / 1 = 0,2 R → +2 R bruto, +1,8 R neto
    expect(report.closed.single.feeR(0.001), closeTo(0.2, 1e-9));
    expect(report.netR, closeTo(1.8, 1e-9));
  });

  test('trade abierto al final no cuenta en las estadísticas', () {
    final report = run(
      _FakeStrategy(),
      candles([
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, false),
        (100.5, 99.5, 100, true),
        (100.8, 99.5, 100, false),
      ]),
    );
    expect(report.trades.single.setup.state, SetupState.open);
    expect(report.closed, isEmpty);
    expect(report.winRate, isNull);
  });
}
