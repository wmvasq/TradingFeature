import 'package:flutter_test/flutter_test.dart';
import 'package:myenglishtool/trading/models.dart';
import 'package:myenglishtool/trading/setups.dart';

final _t0 = DateTime(2026, 11, 1, 10);

Candle candle(int i, {required double high, required double low}) => Candle(
  openTime: _t0.add(Duration(minutes: 5 * i)),
  open: (high + low) / 2,
  high: high,
  low: low,
  close: (high + low) / 2,
  volume: 1,
);

SavedSetup longSetup({SetupState state = SetupState.open}) => SavedSetup(
  symbol: 'BTCUSDT',
  assetLabel: 'BTC',
  interval: '5m',
  strategy: 'SMC',
  direction: Direction.long,
  origin: SetupOrigin.auto,
  state: state,
  entry: 100,
  stopLoss: 95,
  takeProfit: 110,
  summary: '',
  signalTime: _t0,
  createdAt: _t0,
  triggeredAt: state == SetupState.open ? _t0 : null,
  checkedUntil: _t0,
);

void main() {
  test('abierto: toca el TP → ganado con +R:R', () {
    final s = trackSetup(longSetup(), [
      candle(1, high: 104, low: 99),
      candle(2, high: 111, low: 103),
    ]);
    expect(s.state, SetupState.won);
    expect(s.resultR, closeTo(2, 1e-9));
    expect(s.resolvedAt, _t0.add(const Duration(minutes: 10)));
  });

  test('abierto: SL y TP en la misma vela → perdido (conservador)', () {
    final s = trackSetup(longSetup(), [candle(1, high: 112, low: 94)]);
    expect(s.state, SetupState.lost);
    expect(s.resultR, -1);
  });

  test('en espera: se activa al tocar la entrada y luego gana', () {
    final s = trackSetup(longSetup(state: SetupState.pending), [
      candle(1, high: 106, low: 102), // aún no toca 100
      candle(2, high: 103, low: 99.5), // activa
      candle(3, high: 110.5, low: 101), // TP
    ]);
    expect(s.state, SetupState.won);
    expect(s.triggeredAt, _t0.add(const Duration(minutes: 10)));
  });

  test('en espera: llega al TP sin entrar → expirado', () {
    final s = trackSetup(longSetup(state: SetupState.pending), [
      candle(1, high: 111, low: 101),
    ]);
    expect(s.state, SetupState.expired);
  });

  test('en espera: expira tras N velas sin tocar la entrada', () {
    final s = trackSetup(longSetup(state: SetupState.pending), [
      for (var i = 1; i <= 5; i++) candle(i, high: 105, low: 101),
    ], expiryCandles: 5);
    expect(s.state, SetupState.expired);
  });

  test('incremental: no vuelve a procesar velas ya revisadas', () {
    final first = trackSetup(longSetup(), [candle(1, high: 104, low: 99)]);
    expect(first.state, SetupState.open);
    expect(first.candlesChecked, 1);
    // Misma vela otra vez + una nueva: solo cuenta la nueva
    final second = trackSetup(first, [
      candle(1, high: 104, low: 99),
      candle(2, high: 105, low: 98),
    ]);
    expect(second.candlesChecked, 2);
  });

  test('key: entrada única por vela; en espera por precio de entrada', () {
    final entry = longSetup();
    final waiting = longSetup(state: SetupState.pending);
    expect(entry.key, contains('|E|'));
    expect(waiting.key, contains('|W|'));
    expect(entry.key, isNot(waiting.key));
  });

  test('estadísticas', () {
    final stats = SetupStats.of([
      trackSetup(longSetup(), [candle(1, high: 111, low: 99)]), // +2
      trackSetup(longSetup(), [candle(1, high: 101, low: 94)]), // -1
      longSetup(state: SetupState.pending),
    ]);
    expect(stats.won, 1);
    expect(stats.lost, 1);
    expect(stats.active, 1);
    expect(stats.winRate, 0.5);
    expect(stats.totalR, closeTo(1, 1e-9));
  });
}
