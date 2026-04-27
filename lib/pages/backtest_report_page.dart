import 'package:flutter/material.dart';
import '../models/trading_models.dart';
import '../services/backtesting_service.dart';

/// Página que muestra el reporte completo de backtesting
class BacktestReportPage extends StatelessWidget {
  final BacktestResult result;

  const BacktestReportPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reporte de Backtest'),
        actions: [
          IconButton(
            icon: Icon(Icons.download),
            onPressed: () => _exportReport(),
            tooltip: 'Exportar',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Resumen ejecutivo
            _buildExecutiveSummary(),
            SizedBox(height: 20),

            // Gráfico de equity curve
            _buildEquityCurve(),
            SizedBox(height: 20),

            // Métricas principales
            _buildMetricsGrid(),
            SizedBox(height: 20),

            // Tabla de trades
            _buildTradesTable(),
            SizedBox(height: 20),

            // Configuración usada
            _buildConfigUsed(),
            SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildExecutiveSummary() {
    Color returnColor = result.totalReturn >= 0 ? Colors.green : Colors.red;
    Color gradeColor = _getGradeColor(result.grade);

    return Card(
      elevation: 4,
      color: gradeColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Resumen Ejecutivo',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: gradeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Calif: ${result.grade}',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  'Retorno',
                  '${result.totalReturn.toStringAsFixed(2)}%',
                  returnColor,
                ),
                _buildSummaryItem(
                  'Trades',
                  result.tradesCount.toString(),
                  Colors.blue,
                ),
                _buildSummaryItem(
                  'Win Rate',
                  '${result.winRate.toStringAsFixed(1)}%',
                  Colors.green,
                ),
                _buildSummaryItem(
                  'Profit Factor',
                  result.profitFactor.toStringAsFixed(2),
                  Colors.purple,
                ),
              ],
            ),
            SizedBox(height: 12),
            LinearProgressIndicator(
              value: result.totalReturn / 100 + 0.5, // visual normalizado
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(returnColor),
              minHeight: 8,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEquityCurve() {
    // Simulación simple de equity curve basada en trades
    // En producción usarías fl_chart para gráfico real
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Curva de Equity (simulada)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Container(
              height: 150,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100, Colors.blue.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Center(
                child: Text(
                  '📈 Gráfico de Equity Curve\n(se implementará con fl_chart)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Métricas de Desempeño',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _buildMetricChip(
                  'Máx Drawdown',
                  '${result.maxDrawdown.toStringAsFixed(2)}%',
                  Colors.red,
                ),
                _buildMetricChip(
                  'Sharpe Ratio',
                  result.sharpeRatio.toStringAsFixed(2),
                  Colors.blue,
                ),
                _buildMetricChip(
                  'Sortino',
                  result.sortinoRatio.toStringAsFixed(2),
                  Colors.purple,
                ),
                _buildMetricChip(
                  'Avg Win',
                  '\$${result.averageWin.toStringAsFixed(2)}',
                  Colors.green,
                ),
                _buildMetricChip(
                  'Avg Loss',
                  '\$${result.averageLoss.toStringAsFixed(2)}',
                  Colors.red,
                ),
                _buildMetricChip(
                  'W/L Ratio',
                  result.averageWinLossRatio.toStringAsFixed(2),
                  Colors.orange,
                ),
                _buildMetricChip(
                  'Hold Avg',
                  '${result.averageHoldTimeHours.toStringAsFixed(1)} h',
                  Colors.cyan,
                ),
                _buildMetricChip(
                  'Best Trade',
                  '\$${result.bestTrade?.profit.toStringAsFixed(2) ?? 'N/A'}',
                  Colors.green,
                ),
                _buildMetricChip(
                  'Worst Trade',
                  '-\$${result.worstTrade?.loss.toStringAsFixed(2) ?? 'N/A'}',
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTradesTable() {
    if (result.trades.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('No hay trades en este período.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top 10 Trades',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Entrada')),
                  DataColumn(label: Text('Salida')),
                  DataColumn(label: Text('P/L')),
                  DataColumn(label: Text('Razón')),
                ],
                rows: result.trades.take(10).map((trade) {
                  return DataRow(
                    cells: [
                      DataCell(Text(trade.isWin ? '✅' : '❌')),
                      DataCell(
                        Text('\$${trade.entryPrice.toStringAsFixed(2)}'),
                      ),
                      DataCell(Text('\$${trade.exitPrice.toStringAsFixed(2)}')),
                      DataCell(
                        Text(
                          '${trade.profitPercent.toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: trade.isWin ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(trade.reason, style: TextStyle(fontSize: 10)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigUsed() {
    TradingConfig c = result.configUsed;
    return Card(
      color: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración Utilizada',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Capital: \$${c.totalCapital.toStringAsFixed(2)}'),
            Text(
              'Distribución: ${(c.percentLongTerm * 100).toInt()}% Largo | ${(c.percentWeekly * 100).toInt()}% Semanal | ${(c.percentDaily * 100).toInt()}% Diario | ${(c.percentFutures * 100).toInt()}% Futuros',
            ),
            Text(
              'EMAs: ${c.emaFastPeriod}, ${c.emaMediumPeriod}, ${c.emaSlowPeriod}, ${c.emaLongPeriod}',
            ),
            Text('ADX: período ${c.adxPeriod}, umbral ${c.adxThreshold}'),
            Text(
              'Riesgo máximo por trade: ${(c.maxRiskPerTrade * 100).toStringAsFixed(1)}%',
            ),
            Text(
              'Stop loss por defecto: ${(c.defaultStopLoss * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.all(12),
        color: Colors.grey[100],
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Volver'),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _shareResults(),
                child: Text('Compartir Resultados'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return Colors.orange;
      case 'D':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  void _exportReport() {
    // TODO: Exportar a PDF/CSV
    ScaffoldMessenger.of(
      globalKey.currentContext!,
    ).showSnackBar(SnackBar(content: Text('📤 Reporte exportado (simulado)')));
  }

  void _shareResults() {
    // Compartir resultados
    String text =
        '''
Backtest Trading Strategy - Jaime Merino
Retorno: ${result.totalReturn.toStringAsFixed(2)}%
Win Rate: ${result.winRate.toStringAsFixed(1)}%
Profit Factor: ${result.profitFactor.toStringAsFixed(2)}
Calificación: ${result.grade}
    ''';

    // TODO: Implementar share plugin
    ScaffoldMessenger.of(
      globalKey.currentContext!,
    ).showSnackBar(SnackBar(content: Text('📤 Compartir (simulado)')));
  }
}

// Global key para contexto en ScaffoldMessenger
final GlobalKey globalKey = GlobalKey();
