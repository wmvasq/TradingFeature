import 'dart:math';
import '../models/trading_models.dart';
import 'market_data_service.dart';
import 'indicators_service.dart';
import 'signal_engine.dart';

/// Servicio para probar la estrategia con datos históricos
/// Crucial para validar la estrategia antes de usarla con dinero real
class BacktestingService {
  final TradingConfig config;
  final MarketDataService marketData;

  BacktestingService({required this.config, required this.marketData});

  /// Ejecuta un backtest completo en un par de trading
  ///
  /// [candles] - Datos históricos OHLCV
  /// [initialCapital] - Capital inicial (default: $10,000)
  /// [commission] - Comisión por trade (default: 0.1% = 0.001)
  ///
  /// Retorna un objeto con todas las métricas
  Future<BacktestResult> runBacktest({
    required List<Candle> candles,
    double initialCapital = 10000.0,
    double commission = 0.001, // 0.1% por trade
    bool useStopLoss = true,
    bool useTakeProfit = true,
  }) async {
    if (candles.length < config.emaLongPeriod + 50) {
      throw ArgumentError(
        'Datos insuficientes para backtest. Se necesitan al menos ${config.emaLongPeriod + 50} velas.',
      );
    }

    double capital = initialCapital;
    int tradesCount = 0;
    int winningTrades = 0;
    int losingTrades = 0;
    double totalProfit = 0.0;
    double totalLoss = 0.0;
    double maxDrawdown = 0.0;
    double peakCapital = initialCapital;

    List<Trade> trades = [];
    bool inPosition = false;
    double? entryPrice;
    double? entryQuantity;
    DateTime? entryTime;

    // Recorrer velas desde que tenemos suficientes datos para calcular indicadores
    int startIndex = config.emaLongPeriod + 20; // dar margen
    for (int i = startIndex; i < candles.length; i++) {
      // Obtener datos hasta la vela actual (no future泄漏)
      List<Candle> dataUpToNow = candles.sublist(0, i + 1);

      // Generar señal para esta vela (usando solo datos hasta ahora)
      TradingSignal? signal;
      try {
        signal = _generateSignalForCandle(dataUpToNow);
      } catch (e) {
        continue; // Si no hay suficientes datos, saltar
      }

      final currentCandle = candles[i];
      double currentPrice = currentCandle.close;

      // Lógica de trading
      if (!inPosition) {
        // ¿Comprar?
        if (signal.type == SignalType.buy ||
            signal.type == SignalType.strongBuy) {
          // Calcular tamaño de posición basado en riesgo
          double riskAmount = capital * config.maxRiskPerTrade;
          double? stopPrice =
              signal.stopLoss ?? (currentPrice * (1 - config.defaultStopLoss));
          double riskPerShare = (currentPrice - stopPrice!).abs();

          if (riskPerShare > 0) {
            double quantity = riskAmount / riskPerShare;
            double cost = quantity * currentPrice;
            double commissionCost = cost * commission;

            if (cost + commissionCost <= capital) {
              // Ejecutar compra
              inPosition = true;
              entryPrice = currentPrice;
              entryQuantity = quantity;
              entryTime = currentCandle.timestamp;

              capital -= (cost + commissionCost);

              tradesCount++;
            }
          }
        }
      } else {
        // En posición - evaluar venta
        bool shouldSell = false;
        double? exitPrice;
        String exitReason = '';

        // 1. Stop Loss
        if (useStopLoss && entryPrice != null) {
          double? sl =
              signal.stopLoss ?? (entryPrice * (1 - config.defaultStopLoss));
          if (currentPrice <= sl) {
            shouldSell = true;
            exitPrice = currentPrice;
            exitReason = 'Stop Loss';
          }
        }

        // 2. Take Profit (si no hit SL)
        if (!shouldSell && useTakeProfit && entryPrice != null) {
          if (signal.takeProfit1 != null &&
              currentPrice >= signal.takeProfit1!) {
            shouldSell = true;
            exitPrice = signal.takeProfit1;
            exitReason = 'Take Profit 1';
          } else if (signal.takeProfit2 != null &&
              currentPrice >= signal.takeProfit2!) {
            shouldSell = true;
            exitPrice = signal.takeProfit2;
            exitReason = 'Take Profit 2';
          } else if (signal.takeProfit3 != null &&
              currentPrice >= signal.takeProfit3!) {
            shouldSell = true;
            exitPrice = signal.takeProfit3;
            exitReason = 'Take Profit 3';
          }
        }

        // 3. Señal de venta (opcional, aunque Merino recomienda no shortear)
        if (!shouldSell && signal.type == SignalType.sell) {
          // Solo vender si hay ganancia para evitar perder en tendencia bajista
          if (entryPrice != null && currentPrice > entryPrice) {
            shouldSell = true;
            exitPrice = currentPrice;
            exitReason = 'Señal de venta';
          }
        }

        // Ejecutar venta si corresponde
        if (shouldSell && exitPrice != null && entryQuantity != null) {
          double revenue = entryQuantity! * exitPrice;
          double commissionCost = revenue * commission;
          double profit =
              revenue - (entryQuantity! * entryPrice!) - commissionCost;

          capital += (revenue - commissionCost);

          // Actualizar estadísticas
          if (profit > 0) {
            winningTrades++;
            totalProfit += profit;
          } else {
            losingTrades++;
            totalLoss += profit.abs();
          }

          // Actualizar drawdown
          if (capital > peakCapital) {
            peakCapital = capital;
          }
          double currentDrawdown = (peakCapital - capital) / peakCapital;
          if (currentDrawdown > maxDrawdown) {
            maxDrawdown = currentDrawdown;
          }

          // Guardar trade
          trades.add(
            Trade(
              entryDate: entryTime!,
              exitDate: currentCandle.timestamp,
              entryPrice: entryPrice!,
              exitPrice: exitPrice,
              quantity: entryQuantity!,
              profit: profit,
              profitPercent: profit / (entryPrice! * entryQuantity!) * 100,
              reason: exitReason,
              stopLoss: signal.stopLoss,
              takeProfit: signal.takeProfit1,
            ),
          );

          // Resetear posición
          inPosition = false;
          entryPrice = null;
          entryQuantity = null;
          entryTime = null;
        }
      }
    }

    // Vender si aún hay posición al final
    if (inPosition && entryQuantity != null && entryPrice != null) {
      double lastPrice = candles.last.close;
      double revenue = entryQuantity! * lastPrice;
      double commissionCost = revenue * commission;
      double profit = revenue - (entryQuantity! * entryPrice!) - commissionCost;

      capital += (revenue - commissionCost);

      trades.add(
        Trade(
          entryDate: entryTime!,
          exitDate: candles.last.timestamp,
          entryPrice: entryPrice!,
          exitPrice: lastPrice,
          quantity: entryQuantity!,
          profit: profit,
          profitPercent: profit / (entryPrice! * entryQuantity!) * 100,
          reason: 'Fin del backtest',
          stopLoss: null,
          takeProfit: null,
        ),
      );
    }

    // ============================================
    // CALCULAR MÉTRICAS FINALES
    // ============================================

    double finalBalance = capital;
    double totalReturn =
        ((finalBalance - initialCapital) / initialCapital) * 100;

    double winRate = tradesCount > 0 ? winningTrades / tradesCount * 100 : 0.0;

    double profitFactor = totalLoss > 0
        ? totalProfit / totalLoss
        : double.infinity;

    double averageWin = winningTrades > 0 ? totalProfit / winningTrades : 0.0;
    double averageLoss = losingTrades > 0 ? totalLoss / losingTrades : 0.0;

    double sharpeRatio = _calculateSharpeRatio(trades);
    double sortinoRatio = _calculateSortinoRatio(trades);

    // Mejor/worst trade
    Trade? bestTrade = trades.isNotEmpty
        ? trades.reduce((a, b) => a.profit > b.profit ? a : b)
        : null;
    Trade? worstTrade = trades.isNotEmpty
        ? trades.reduce((a, b) => a.profit < b.profit ? a : b)
        : null;

    // Duración promedio de trades
    double avgHoldTimeHours = trades.isNotEmpty
        ? trades.map((t) => t.duration.inHours).reduce((a, b) => a + b) /
              trades.length
        : 0.0;

    return BacktestResult(
      initialCapital: initialCapital,
      finalBalance: finalBalance,
      totalReturn: totalReturn,
      tradesCount: tradesCount,
      winningTrades: winningTrades,
      losingTrades: losingTrades,
      winRate: winRate,
      profitFactor: profitFactor,
      averageWin: averageWin,
      averageLoss: averageLoss,
      averageWinLossRatio: averageLoss > 0
          ? averageWin / averageLoss
          : double.infinity,
      maxDrawdown: maxDrawdown * 100, // en porcentaje
      sharpeRatio: sharpeRatio,
      sortinoRatio: sortinoRatio,
      bestTrade: bestTrade,
      worstTrade: worstTrade,
      averageHoldTimeHours: avgHoldTimeHours,
      trades: trades,
      configUsed: config,
      testPeriod: TestPeriod(
        start: candles.first.timestamp,
        end: candles.last.timestamp,
        totalDays: candles.last.timestamp
            .difference(candles.first.timestamp)
            .inDays,
      ),
    );
  }

  /// Genera señal para una vela específica (sin fuga de futuro)
  TradingSignal _generateSignalForCandle(List<Candle> data) {
    // En backtest, usamos solo el timeframe principal
    final engine = TradingSignalEngine(
      config: config,
      candles: data,
      // weeklyCandles y dailyCandles se dejan vacíos
    );

    return engine.generateSignal();
  }

  // Método _aggregateToTimeframe eliminado - no necesario para backtest
  double _calculateSharpeRatio(
    List<Trade> trades, {
    double riskFreeRate = 0.0,
  }) {
    if (trades.length < 2) return 0.0;

    List<double> returns = trades.map((t) => t.profitPercent / 100).toList();
    double meanReturn = returns.reduce((a, b) => a + b) / returns.length;

    double sumSquaredDeviation = 0.0;
    for (double ret in returns) {
      sumSquaredDeviation += (ret - meanReturn) * (ret - meanReturn);
    }
    double stdDev = sqrt(sumSquaredDeviation / (returns.length - 1));

    if (stdDev == 0) return 0.0;

    return (meanReturn - riskFreeRate) / stdDev * sqrt(252); // anualizado
  }

  /// Calcula ratio de Sortino (solo considerando volatilidad negativa)
  double _calculateSortinoRatio(
    List<Trade> trades, {
    double riskFreeRate = 0.0,
  }) {
    if (trades.isEmpty) return 0.0;

    List<double> returns = trades.map((t) => t.profitPercent / 100).toList();
    double meanReturn = returns.reduce((a, b) => a + b) / returns.length;

    // Solo desviación de retornos negativos
    List<double> negativeReturns = returns.where((r) => r < 0).toList();
    if (negativeReturns.isEmpty) return double.infinity; // Sin pérdidas

    double sumSquaredDown = 0.0;
    for (double ret in negativeReturns) {
      sumSquaredDown += (ret - meanReturn) * (ret - meanReturn);
    }
    double downDev = sqrt(sumSquaredDown / negativeReturns.length);

    if (downDev == 0) return double.infinity;

    return (meanReturn - riskFreeRate) / downDev * sqrt(252);
  }

  /// Genera reporte de backtesting en texto
  String generateReport(BacktestResult result) {
    StringBuffer report = StringBuffer();

    report.writeln('═══════════════════════════════════════════════');
    report.writeln('        BACKTEST RESULT - TRADING STRATEGY');
    report.writeln('═══════════════════════════════════════════════');
    report.writeln();
    report.writeln('📊 TEST PERIOD');
    report.writeln(
      '   Start: ${result.testPeriod.start.toString().substring(0, 10)}',
    );
    report.writeln(
      '   End:   ${result.testPeriod.end.toString().substring(0, 10)}',
    );
    report.writeln('   Days:  ${result.testPeriod.totalDays}');
    report.writeln();
    report.writeln('💰 CAPITAL');
    report.writeln(
      '   Initial:  \$${result.initialCapital.toStringAsFixed(2)}',
    );
    report.writeln('   Final:    \$${result.finalBalance.toStringAsFixed(2)}');
    report.writeln(
      '   Return:   ${result.totalReturn >= 0 ? '+' : ''}${result.totalReturn.toStringAsFixed(2)}%',
    );
    report.writeln('   Max DD:   ${result.maxDrawdown.toStringAsFixed(2)}%');
    report.writeln();
    report.writeln('📈 TRADES');
    report.writeln('   Total:    ${result.tradesCount}');
    report.writeln(
      '   Winners:  ${result.winningTrades} (${result.winRate.toStringAsFixed(1)}%)',
    );
    report.writeln('   Losers:   ${result.losingTrades}');
    report.writeln(
      '   Profit Factor: ${result.profitFactor.toStringAsFixed(2)}',
    );
    report.writeln();
    report.writeln('📊 STATS');
    report.writeln(
      '   Avg Win:        \$${result.averageWin.toStringAsFixed(2)}',
    );
    report.writeln(
      '   Avg Loss:       \$${result.averageLoss.toStringAsFixed(2)}',
    );
    report.writeln(
      '   Win/Loss Ratio: ${result.averageWinLossRatio.toStringAsFixed(2)}',
    );
    report.writeln(
      '   Sharpe Ratio:   ${result.sharpeRatio.toStringAsFixed(2)}',
    );
    report.writeln(
      '   Sortino Ratio:  ${result.sortinoRatio.toStringAsFixed(2)}',
    );
    report.writeln(
      '   Avg Hold Time:  ${result.averageHoldTimeHours.toStringAsFixed(1)} hrs',
    );
    report.writeln();

    if (result.bestTrade != null) {
      report.writeln(
        '🏆 BEST TRADE: +\$${result.bestTrade!.profit.toStringAsFixed(2)} (${result.bestTrade!.profitPercent.toStringAsFixed(2)}%)',
      );
    }
    if (result.worstTrade != null) {
      report.writeln(
        '💔 WORST TRADE: -\$${result.worstTrade!.loss.toStringAsFixed(2)} (${result.worstTrade!.profitPercent.toStringAsFixed(2)}%)',
      );
    }

    report.writeln();
    report.writeln(
      'Config: EMAs(${config.emaFastPeriod},${config.emaMediumPeriod},${config.emaSlowPeriod}) | ADX(${config.adxPeriod}) > ${config.adxThreshold}',
    );
    report.writeln('═══════════════════════════════════════════════');

    return report.toString();
  }
}

// ============================================
// MODELOS DE BACKTESTING
// ============================================

class Trade {
  final DateTime entryDate;
  final DateTime exitDate;
  final double entryPrice;
  final double exitPrice;
  final double quantity;
  final double profit; // en dólares
  final double profitPercent; // en porcentaje
  final String reason; // 'Stop Loss', 'Take Profit 1', etc.
  final double? stopLoss;
  final double? takeProfit;

  Trade({
    required this.entryDate,
    required this.exitDate,
    required this.entryPrice,
    required this.exitPrice,
    required this.quantity,
    required this.profit,
    required this.profitPercent,
    required this.reason,
    this.stopLoss,
    this.takeProfit,
  });

  double get loss => profit < 0 ? profit.abs() : 0.0;
  bool get isWin => profit > 0;

  Duration get duration => exitDate.difference(entryDate);

  Map<String, dynamic> toJson() {
    return {
      'entryDate': entryDate.toIso8601String(),
      'exitDate': exitDate.toIso8601String(),
      'entryPrice': entryPrice,
      'exitPrice': exitPrice,
      'quantity': quantity,
      'profit': profit,
      'profitPercent': profitPercent,
      'reason': reason,
      'isWin': isWin,
      'durationHours': duration.inHours,
    };
  }
}

class BacktestResult {
  final double initialCapital;
  final double finalBalance;
  final double totalReturn; // en porcentaje
  final int tradesCount;
  final int winningTrades;
  final int losingTrades;
  final double winRate; // en porcentaje
  final double profitFactor; // (ganancia total / pérdida total)
  final double averageWin;
  final double averageLoss;
  final double averageWinLossRatio;
  final double maxDrawdown; // en porcentaje
  final double sharpeRatio;
  final double sortinoRatio;
  final Trade? bestTrade;
  final Trade? worstTrade;
  final double averageHoldTimeHours;
  final List<Trade> trades;
  final TradingConfig configUsed;
  final TestPeriod testPeriod;

  BacktestResult({
    required this.initialCapital,
    required this.finalBalance,
    required this.totalReturn,
    required this.tradesCount,
    required this.winningTrades,
    required this.losingTrades,
    required this.winRate,
    required this.profitFactor,
    required this.averageWin,
    required this.averageLoss,
    required this.averageWinLossRatio,
    required this.maxDrawdown,
    required this.sharpeRatio,
    required this.sortinoRatio,
    this.bestTrade,
    this.worstTrade,
    required this.averageHoldTimeHours,
    required this.trades,
    required this.configUsed,
    required this.testPeriod,
  });

  /// Evalúa si la estrategia es rentable (mínimo viable)
  bool get isProfitable => totalReturn > 0 && profitFactor > 1.5;

  /// Evalúa si el riesgo es aceptable
  bool get riskAcceptable => maxDrawdown < 20.0 && winRate > 40.0;

  /// Calificación general (A-F)
  String get grade {
    if (isProfitable && riskAcceptable && sharpeRatio > 1.5) return 'A';
    if (isProfitable && riskAcceptable) return 'B';
    if (totalReturn > 0) return 'C';
    if (totalReturn > -20) return 'D';
    return 'F';
  }
}

class TestPeriod {
  final DateTime start;
  final DateTime end;
  final int totalDays;

  TestPeriod({required this.start, required this.end, required this.totalDays});
}

// ============================================
// UTILIDADES
// ============================================

// Método para obtener número de semana (simple)
int getWeekNumber(DateTime date) {
  // Aproximación simple
  int dayOfYear = int.parse(date.toString().substring(0, 4)); // placeholder
  // Implementación correcta en producción
  return ((date.difference(DateTime(date.year, 1, 1)).inDays + date.weekday) /
          7)
      .floor();
}

// Extensión ya no se usa - removida
