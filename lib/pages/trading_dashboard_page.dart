import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math; // Para math.min y math.max
import '../models/trading_models.dart';
import '../services/market_data_service.dart';
import '../services/indicators_service.dart';
import '../services/signal_engine.dart';
import '../services/backtesting_service.dart';
import '../services/trading_ai_service.dart';
// Páginas locales
import 'signal_detail_page.dart';
import 'backtest_report_page.dart';
import 'trading_settings_page.dart';
import 'ai_assistant_page.dart';

/// Pantalla principal del sistema de trading de Bitcoin
/// Muestra: gráfico, señales, indicadores y controles
class TradingDashboardPage extends StatefulWidget {
  const TradingDashboardPage({super.key});

  @override
  State<TradingDashboardPage> createState() => _TradingDashboardPageState();
}

class _TradingDashboardPageState extends State<TradingDashboardPage> {
  // ============================================
  // ESTADO
  // ============================================
  final MarketDataService _marketData = MarketDataService();
  final TradingConfig _config = TradingConfig();
  final TradingAIService _aiService = TradingAIService();

  List<Candle> _candles = [];
  TradingSignal? _lastSignal;
  bool _isLoading = false;
  String? _error;
  double _currentPrice = 0.0;

  // Controladores de UI
  String _selectedTimeframe = '1h';
  final List<String> _timeframes = ['15m', '1h', '4h', '1d'];

  // Indicadores en gráfico
  bool _showEMA9 = true;
  bool _showEMA20 = true;
  bool _showEMA50 = true;
  bool _showEMA200 = false;
  bool _showVolume = true;

  // Historial de señales
  final List<TradingSignal> _signalHistory = [];

  // Modo backtesting
  bool _isBacktesting = false;
  BacktestResult? _backtestResult;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // ============================================
  // CARGA DE DATOS
  // ============================================

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Obtener precio actual
      double price = await _marketData.getCurrentBTCPrice();

      // 2. Obtener velas históricas
      List<Candle> candles = await _marketData.fetchBinanceKlines(
        symbol: 'BTCUSDT',
        interval: _selectedTimeframe,
        limit: 500,
      );

      if (mounted) {
        setState(() {
          _currentPrice = price;
          _candles = candles;
          _isLoading = false;
        });

        // 3. Generar señal inicial
        _generateSignal();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadInitialData();
  }

  /// Genera señal basada en datos cargados
  void _generateSignal() {
    if (_candles.length < _config.emaLongPeriod) return;

    try {
      final engine = TradingSignalEngine(config: _config, candles: _candles);

      final signal = engine.generateSignal();

      setState(() {
        _lastSignal = signal;
        _signalHistory.insert(0, signal);
        // Mantener solo últimas 50 señales
        if (_signalHistory.length > 50) {
          _signalHistory.removeLast();
        }
      });

      // Mostrar notificación si señal es fuerte
      if (signal.isReliable) {
        _showSignalNotification(signal);
      }
    } catch (e) {
      // Error generando señal
      debugPrint('Error generando señal: $e');
    }
  }

  void _showSignalNotification(TradingSignal signal) {
    // TODO: Implementar notificación local
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🚨 Señal ${signal.type.toString().toUpperCase()} detectada!',
        ),
        backgroundColor: signal.type == SignalType.buy
            ? Colors.green
            : Colors.red,
        duration: Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Ver',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SignalDetailPage(signal: signal),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================
  // BACKTESTING
  // ============================================

  Future<void> _runBacktest() async {
    setState(() {
      _isBacktesting = true;
      _error = null;
    });

    try {
      // Obtener datos históricos más largos para backtest (ej: 2 años)
      List<Candle> historicalData = await _marketData.fetchBinanceKlines(
        symbol: 'BTCUSDT',
        interval: _selectedTimeframe,
        limit: 2000, // Máximo permitido por Binance
      );

      if (historicalData.length < 100) {
        throw Exception('Datos históricos insuficientes para backtest');
      }

      final backtester = BacktestingService(
        config: _config,
        marketData: _marketData,
      );

      final result = await backtester.runBacktest(
        candles: historicalData,
        initialCapital: 10000.0,
        commission: 0.001,
      );

      setState(() {
        _backtestResult = result;
        _isBacktesting = false;
      });

      // Mostrar diálogo con resultados
      _showBacktestResultDialog(result);
    } catch (e) {
      setState(() {
        _error = 'Backtest falló: $e';
        _isBacktesting = false;
      });
    }
  }

  void _showBacktestResultDialog(BacktestResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Backtest Resultado - Calificación: ${result.grade}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${result.totalReturn >= 0 ? '+' : ''}${result.totalReturn.toStringAsFixed(2)}% de retorno',
              ),
              Text('Win Rate: ${result.winRate.toStringAsFixed(1)}%'),
              Text('Profit Factor: ${result.profitFactor.toStringAsFixed(2)}'),
              Text('Max Drawdown: ${result.maxDrawdown.toStringAsFixed(2)}%'),
              Text('Sharpe: ${result.sharpeRatio.toStringAsFixed(2)}'),
              SizedBox(height: 10),
              Text(
                'Trades: ${result.tradesCount} (${result.winningTrades}G/${result.losingTrades}P)',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showFullBacktestReport(result);
            },
            child: Text('Ver Reporte Completo'),
          ),
        ],
      ),
    );
  }

  void _showFullBacktestReport(BacktestResult result) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BacktestReportPage(result: result)),
    );
  }

  // ============================================
  // UI
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bitcoin Trading - Estrategia Merino'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Actualizar datos',
          ),
          IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: _runBacktest,
            tooltip: 'Ejecutar Backtest',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'settings') {
                _openSettings();
              } else if (value == 'ai_assistant') {
                _openAIAssistant();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 8),
                    Text('Configuración'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'ai_assistant',
                child: Row(
                  children: [
                    Icon(Icons.smart_toy),
                    SizedBox(width: 8),
                    Text('Asistente IA'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _candles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando datos de Bitcoin...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error', style: TextStyle(color: Colors.red)),
            SizedBox(height: 16),
            ElevatedButton(onPressed: _refreshData, child: Text('Reintentar')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header con precio y señal actual
            _buildHeader(),
            Divider(height: 1),

            // 2. Gráfico de precios con EMAs
            _buildChart(),

            // 3. Panel de indicadores
            _buildIndicatorsPanel(),

            // 4. Detalle de señal actual
            if (_lastSignal != null) _buildSignalCard(_lastSignal!),

            // 5. Historial de señales
            _buildSignalHistory(),

            // 6. Backtest result (si existe)
            if (_backtestResult != null) _buildBacktestSummary(),

            SizedBox(height: 80), // Espacio para FAB
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.blueGrey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BTC/USDT',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${_currentPrice.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 24, color: Colors.blue[800]),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Señal Actual',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              SizedBox(height: 4),
              _buildSignalBadge(_lastSignal?.type ?? SignalType.hold),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBadge(SignalType type) {
    Color color;
    String text;
    IconData icon;

    switch (type) {
      case SignalType.buy:
        color = Colors.green;
        text = 'COMPRA';
        icon = Icons.arrow_upward;
        break;
      case SignalType.strongBuy:
        color = Colors.green.shade800;
        text = 'COMPRA FUERTE';
        icon = Icons.trending_up;
        break;
      case SignalType.sell:
        color = Colors.red;
        text = 'VENTA';
        icon = Icons.arrow_downward;
        break;
      case SignalType.hold:
      default:
        color = Colors.orange;
        text = 'ESPERAR';
        icon = Icons.remove;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    return Container(
      height: 300,
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Selector de timeframe
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _timeframes.map<Widget>((tf) {
              bool selected = _selectedTimeframe == tf;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(tf),
                  selected: selected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedTimeframe = tf;
                    });
                    _loadInitialData();
                  },
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 16),
          // Gráfico
          Expanded(child: _buildPriceChart()),
        ],
      ),
    );
  }

  Widget _buildPriceChart() {
    if (_candles.isEmpty) return SizedBox();

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_candles.length - 1).toDouble(),
        minY: _candles.map((c) => c.low).reduce(math.min) * 0.99,
        maxY: _candles.map((c) => c.high).reduce(math.max) * 1.01,
        lineBarsData: [
          // Precio BTC
          _buildPriceLine(),
          // EMAs
          if (_showEMA9) _buildEMALine('ema9', Colors.orange),
          if (_showEMA20) _buildEMALine('ema20', Colors.blue),
          if (_showEMA50) _buildEMALine('ema50', Colors.purple),
          if (_showEMA200) _buildEMALine('ema200', Colors.red),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            // tooltipBgColor no disponible en esta versión
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                int index = spot.x.toInt();
                if (index < _candles.length) {
                  Candle candle = _candles[index];
                  return LineTooltipItem(
                    '${candle.timestamp.toString().substring(11, 16)}\n'
                    'O:${candle.open.toStringAsFixed(2)}\n'
                    'H:${candle.high.toStringAsFixed(2)}\n'
                    'L:${candle.low.toStringAsFixed(2)}\n'
                    'C:${candle.close.toStringAsFixed(2)}',
                    const TextStyle(color: Colors.white, fontSize: 10),
                  );
                }
                return null;
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildPriceLine() {
    return LineChartBarData(
      spots: _candles.asMap().entries.map((entry) {
        return FlSpot(entry.key.toDouble(), entry.value.close);
      }).toList(),
      color: Colors.black,
      isCurved: true,
      barWidth: 2,
      dotData: FlDotData(show: false),
    );
  }

  LineChartBarData _buildEMALine(String emaKey, Color color) {
    // Calcular EMA para esa clave
    List<double> closes = _candles.map((c) => c.close).toList();
    Map<String, List<double?>> emas =
        TechnicalIndicatorsService.calculateMultipleEMAs(
          closes,
          {emaKey: int.parse(emaKey.substring(3))}, // 'ema9' -> 9
        );

    List<double?> emaValues = emas[emaKey]!;

    return LineChartBarData(
      spots: emaValues
          .asMap()
          .entries
          .where((entry) => entry.value != null)
          .map((entry) => FlSpot(entry.key.toDouble(), entry.value!))
          .toList(),
      color: color,
      isCurved: false,
      barWidth: 1.5,
      dotData: FlDotData(show: false),
    );
  }

  Widget _buildIndicatorsPanel() {
    if (_candles.isEmpty) return SizedBox();

    List<double> closes = _candles.map((c) => c.close).toList();
    List<double> highs = _candles.map((c) => c.high).toList();
    List<double> lows = _candles.map((c) => c.low).toList();

    double? adx = TechnicalIndicatorsService.getCurrentADX(
      highs,
      lows,
      closes,
      14,
    );
    double? rsi = TechnicalIndicatorsService.calculateRSI(closes, 14).last;
    var squeeze = TechnicalIndicatorsService.calculateSqueezeMomentum(
      highs,
      lows,
      closes,
    );
    double? currentSqueeze = squeeze.last;

    return Container(
      padding: EdgeInsets.all(12),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildIndicatorChip(
            'ADX',
            adx?.toStringAsFixed(1) ?? 'N/A',
            adx != null && adx > 25 ? Colors.green : Colors.orange,
          ),
          _buildIndicatorChip(
            'RSI',
            rsi?.toStringAsFixed(1) ?? 'N/A',
            rsi != null && rsi < 30
                ? Colors.green
                : rsi != null && rsi > 70
                ? Colors.red
                : Colors.blue,
          ),
          _buildIndicatorChip(
            'Squeeze',
            currentSqueeze?.toStringAsFixed(4) ?? 'N/A',
            currentSqueeze != null && currentSqueeze > 0
                ? Colors.green
                : currentSqueeze != null && currentSqueeze < 0
                ? Colors.red
                : Colors.grey,
          ),
          _buildIndicatorChip(
            'Precio',
            '\$${_currentPrice.toStringAsFixed(0)}',
            Colors.black,
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildSignalCard(TradingSignal signal) {
    return Card(
      margin: EdgeInsets.all(12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  signal.type == SignalType.buy
                      ? Icons.trending_up
                      : signal.type == SignalType.strongBuy
                      ? Icons.rocket_launch
                      : Icons.remove,
                  color: signal.type == SignalType.buy
                      ? Colors.green
                      : signal.type == SignalType.strongBuy
                      ? Colors.green.shade800
                      : Colors.orange,
                  size: 32,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SEÑAL: ${signal.type.toString().toUpperCase()}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Confianza: ${(signal.confidence * 100).toStringAsFixed(1)}%',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: signal.confidence > 0.7
                        ? Colors.green.withOpacity(0.2)
                        : signal.confidence > 0.5
                        ? Colors.orange.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    border: Border.all(
                      color: signal.confidence > 0.7
                          ? Colors.green
                          : signal.confidence > 0.5
                          ? Colors.orange
                          : Colors.red,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    signal.confidence > 0.7
                        ? 'ALTA'
                        : signal.confidence > 0.5
                        ? 'MEDIA'
                        : 'BAJA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: signal.confidence > 0.7
                          ? Colors.green
                          : signal.confidence > 0.5
                          ? Colors.orange
                          : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text('Razón: ${signal.reason}', style: TextStyle(fontSize: 14)),
            SizedBox(height: 8),
            if (signal.detailedReasons.isNotEmpty) ...[
              Text(
                'Detalles:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              ...signal.detailedReasons.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 2),
                  child: Text(
                    '• $r',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
              ),
            ],
            if (signal.warnings.isNotEmpty) ...[
              SizedBox(height: 8),
              ...signal.warnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 2),
                  child: Row(
                    children: [
                      Icon(Icons.warning, size: 12, color: Colors.orange),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPriceInfo('Entrada', signal.entryPrice),
                _buildPriceInfo('Stop Loss', signal.stopLoss, isNegative: true),
                _buildPriceInfo('TP 1', signal.takeProfit1, isPositive: true),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _askAIAboutSignal(signal),
                  child: Row(
                    children: [
                      Icon(Icons.psychology, size: 16),
                      SizedBox(width: 4),
                      Text('Explicar con IA'),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: signal.isReliable
                      ? () => _addToWatchlist(signal)
                      : null,
                  child: Text('Agregar a Watchlist'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceInfo(
    String label,
    double? value, {
    bool isPositive = false,
    bool isNegative = false,
  }) {
    Color textColor = Colors.grey[700]!;
    if (value != null) {
      if (isPositive) textColor = Colors.green;
      if (isNegative) textColor = Colors.red;
    }

    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        SizedBox(height: 2),
        Text(
          value != null ? '\$${value.toStringAsFixed(2)}' : '-',
          style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        ),
      ],
    );
  }

  Widget _buildSignalHistory() {
    if (_signalHistory.isEmpty) return SizedBox();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historial de Señales',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Container(
            height: 150,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _signalHistory.length,
              itemBuilder: (context, index) {
                final signal = _signalHistory[index];
                return Container(
                  width: 140,
                  margin: EdgeInsets.only(right: 8),
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: signal.type == SignalType.buy
                        ? Colors.green.shade50
                        : signal.type == SignalType.strongBuy
                        ? Colors.green.shade100
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: signal.type == SignalType.buy
                          ? Colors.green
                          : signal.type == SignalType.strongBuy
                          ? Colors.green.shade800
                          : Colors.orange,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signal.type.toString().split('.').last.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '${(signal.confidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12),
                      ),
                      Text(
                        signal.timestamp.toString().substring(11, 16),
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBacktestSummary() {
    if (_backtestResult == null) return SizedBox();

    final result = _backtestResult!;
    Color returnColor = result.totalReturn >= 0 ? Colors.green : Colors.red;

    return Card(
      margin: EdgeInsets.all(12),
      color: Colors.blueGrey[50],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Backtest (${result.testPeriod.totalDays}d)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: result.grade == 'A'
                        ? Colors.green
                        : result.grade == 'B'
                        ? Colors.blue
                        : result.grade == 'C'
                        ? Colors.orange
                        : Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Calif: ${result.grade}',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBacktestStat(
                  'Retorno',
                  '${result.totalReturn.toStringAsFixed(1)}%',
                  returnColor,
                ),
                _buildBacktestStat(
                  'Win Rate',
                  '${result.winRate.toStringAsFixed(0)}%',
                  Colors.blue,
                ),
                _buildBacktestStat(
                  'Profit Factor',
                  result.profitFactor.toStringAsFixed(2),
                  Colors.purple,
                ),
                _buildBacktestStat(
                  'Max DD',
                  '${result.maxDrawdown.toStringAsFixed(1)}%',
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBacktestStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ============================================
  // ACCIONES
  // ============================================

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TradingSettingsPage(config: _config)),
    );
    // Recargar con nueva configuración
    _generateSignal();
  }

  Future<void> _openAIAssistant() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AIAssistantPage(aiService: _aiService, currentSignal: _lastSignal),
      ),
    );
  }

  void _addToWatchlist(TradingSignal signal) {
    // TODO: Guardar señal en watchlist local (SQLite)
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Señal agregada a watchlist')));
  }

  void _askAIAboutSignal(TradingSignal signal) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Análisis IA de la Señal'),
        content: FutureBuilder<String>(
          future: _aiService.explainSignal(signal, detailed: true),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return SingleChildScrollView(
              child: Text(snapshot.data ?? 'No hay análisis disponible'),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
