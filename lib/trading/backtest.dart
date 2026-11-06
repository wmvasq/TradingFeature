import 'dart:math';
import 'models.dart';
import 'setups.dart';
import 'strategies/strategy.dart';

class BacktestSettings {
  /// Velas que ve la estrategia en cada evaluación (igual que la app en vivo).
  final int window;
  final int expiryCandles;

  /// Comisión por lado (0.0005 = 0,05 %, taker en Binance Futures).
  final double feeRate;

  /// Si es true, los setups "en espera" también se operan como orden límite.
  final bool includeWaiting;

  const BacktestSettings({
    this.window = 500,
    this.expiryCandles = 50,
    this.feeRate = 0.0005,
    this.includeWaiting = false,
  });
}

class BacktestTrade {
  final SavedSetup setup;

  const BacktestTrade(this.setup);

  /// Comisión de entrada + salida expresada en R (riesgo de la operación).
  double feeR(double feeRate) =>
      2 * feeRate * setup.entry / (setup.entry - setup.stopLoss).abs();

  /// Resultado neto en R; null si no llegó a cerrarse (expirado o abierto).
  double? netR(double feeRate) {
    final r = setup.resultR;
    return r == null ? null : r - feeR(feeRate);
  }
}

class BacktestReport {
  final String strategy;
  final String symbol;
  final String assetLabel;
  final String interval;
  final BacktestSettings settings;
  final DateTime from;
  final DateTime to;
  final int candlesEvaluated;

  /// En orden cronológico. El último puede seguir activo al terminar.
  final List<BacktestTrade> trades;

  BacktestReport({
    required this.strategy,
    required this.symbol,
    required this.assetLabel,
    required this.interval,
    required this.settings,
    required this.from,
    required this.to,
    required this.candlesEvaluated,
    required this.trades,
  });

  late final List<BacktestTrade> closed = trades
      .where((t) => t.setup.resultR != null)
      .toList();
  late final int won = closed
      .where((t) => t.setup.state == SetupState.won)
      .length;
  late final int lost = closed.length - won;
  late final int expired = trades
      .where((t) => t.setup.state == SetupState.expired)
      .length;
  double? get winRate => closed.isEmpty ? null : won / closed.length;

  late final double grossR = closed.fold(0.0, (a, t) => a + t.setup.resultR!);
  late final double netR = closed.fold(
    0.0,
    (a, t) => a + t.netR(settings.feeRate)!,
  );
  double? get averageNetR => closed.isEmpty ? null : netR / closed.length;

  /// Ganancias netas / pérdidas netas (en R). null si no hay pérdidas.
  late final double? profitFactor = () {
    var gains = 0.0, losses = 0.0;
    for (final t in closed) {
      final r = t.netR(settings.feeRate)!;
      r > 0 ? gains += r : losses -= r;
    }
    return losses == 0 ? null : gains / losses;
  }();

  /// R neto acumulado después de cada trade cerrado (para la curva).
  late final List<double> equity = () {
    var total = 0.0;
    return [for (final t in closed) total += t.netR(settings.feeRate)!];
  }();

  /// Mayor caída desde un máximo de la curva, en R.
  late final double maxDrawdownR = () {
    var peak = 0.0, worst = 0.0;
    for (final value in equity) {
      peak = max(peak, value);
      worst = max(worst, peak - value);
    }
    return worst;
  }();

  late final int maxLosingStreak = () {
    var streak = 0, worst = 0;
    for (final t in closed) {
      streak = t.setup.state == SetupState.lost ? streak + 1 : 0;
      worst = max(worst, streak);
    }
    return worst;
  }();
}

/// Recorre [candles] vela por vela como si la app estuviera abierta:
/// en cada cierre evalúa [strategy] con las últimas `settings.window` velas y,
/// si no hay un trade activo, abre uno con la señal. El trade se sigue con
/// las velas siguientes usando las mismas reglas que el registro de setups.
BacktestReport runBacktest({
  required Strategy strategy,
  required List<Candle> candles,
  required String symbol,
  required String assetLabel,
  required String interval,
  BacktestSettings settings = const BacktestSettings(),
  void Function(double progress)? onProgress,
}) {
  final window = settings.window;
  final start = max(window, strategy.minCandles) - 1;
  if (candles.length <= start) {
    throw ArgumentError(
      'Se necesitan más de ${start + 1} velas (hay ${candles.length})',
    );
  }

  final trades = <BacktestTrade>[];
  SavedSetup? active;
  final total = candles.length - start;

  for (var i = start; i < candles.length; i++) {
    final candle = candles[i];

    // 1. La vela resuelve primero el trade activo (si hay)
    if (active != null) {
      active = trackSetup(active, [
        candle,
      ], expiryCandles: settings.expiryCandles);
      if (active.state.isFinal) {
        trades.add(BacktestTrade(active));
        active = null;
      }
    }

    // 2. Sin trade activo: evaluar la señal al cierre de esta vela
    if (active == null) {
      final result = strategy.evaluate(
        candles.sublist(max(0, i + 1 - window), i + 1),
      );
      final wanted =
          result.status == SetupStatus.entry ||
          (settings.includeWaiting && result.status == SetupStatus.waiting);
      if (wanted) {
        active = SavedSetup.fromResult(
          result: result,
          symbol: symbol,
          assetLabel: assetLabel,
          interval: interval,
          strategy: strategy.name,
          signalTime: candle.openTime,
          origin: SetupOrigin.auto,
        );
      }
    }

    if (onProgress != null && (i - start) % 250 == 0) {
      onProgress((i - start) / total);
    }
  }
  if (active != null) trades.add(BacktestTrade(active));
  onProgress?.call(1);

  return BacktestReport(
    strategy: strategy.name,
    symbol: symbol,
    assetLabel: assetLabel,
    interval: interval,
    settings: settings,
    from: candles[start].openTime,
    to: candles.last.openTime,
    candlesEvaluated: total,
    trades: trades,
  );
}
