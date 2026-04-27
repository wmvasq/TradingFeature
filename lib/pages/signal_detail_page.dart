import 'package:flutter/material.dart';
import '../models/trading_models.dart';
import '../services/trading_ai_service.dart';

/// Página que muestra detalle completo de una señal de trading
class SignalDetailPage extends StatelessWidget {
  final TradingSignal signal;
  final TradingAIService? aiService;

  const SignalDetailPage({super.key, required this.signal, this.aiService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detalle de Señal'),
        actions: [
          if (aiService != null)
            IconButton(
              icon: Icon(Icons.psychology),
              onPressed: () => _showAIAnalysis(context),
              tooltip: 'Análisis IA',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con tipo de señal y confianza
            _buildHeader(context),
            SizedBox(height: 20),

            // Niveles de trade
            _buildLevelsCard(),
            SizedBox(height: 20),

            // Indicadores técnicos
            _buildTechnicalIndicators(),
            SizedBox(height: 20),

            // Explicación y razones
            _buildAnalysisSection(),
            SizedBox(height: 20),

            // Advertencias
            if (signal.warnings.isNotEmpty) _buildWarningsSection(),

            SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: _buildActionButtons(context),
    );
  }

  Widget _buildHeader(BuildContext context) {
    Color signalColor;
    IconData signalIcon;
    String signalText;

    switch (signal.type) {
      case SignalType.strongBuy:
        signalColor = Colors.green.shade800;
        signalIcon = Icons.trending_up;
        signalText = 'SEÑAL FUERTE DE COMPRA';
        break;
      case SignalType.buy:
        signalColor = Colors.green;
        signalIcon = Icons.arrow_upward;
        signalText = 'SEÑAL DE COMPRA';
        break;
      case SignalType.sell:
        signalColor = Colors.red;
        signalIcon = Icons.arrow_downward;
        signalText = 'SEÑAL DE VENTA';
        break;
      default:
        signalColor = Colors.orange;
        signalIcon = Icons.remove;
        signalText = 'MANTENER / ESPERAR';
    }

    return Card(
      elevation: 4,
      color: signalColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(signalIcon, size: 40, color: signalColor),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signalText,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: signalColor,
                        ),
                      ),
                      Text(
                        'Confianza: ${(signal.confidence * 100).toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: signalColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    signal.timeframe,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(signal.reason, style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Niveles de Trading',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _buildLevelRow(
              'Precio Actual',
              signal.entryPrice?.toStringAsFixed(2) ?? 'N/A',
              Colors.blue,
            ),
            _buildLevelRow(
              'Stop Loss',
              signal.stopLoss?.toStringAsFixed(2) ?? 'N/A',
              Colors.red,
              isNegative: true,
            ),
            if (signal.takeProfit1 != null)
              _buildLevelRow(
                'TP 1 (50%)',
                '${signal.takeProfit1!.toStringAsFixed(2)} (${_calcPercent(signal.takeProfit1!)}%)',
                Colors.green,
              ),
            if (signal.takeProfit2 != null)
              _buildLevelRow(
                'TP 2 (30%)',
                '${signal.takeProfit2!.toStringAsFixed(2)} (${_calcPercent(signal.takeProfit2!)}%)',
                Colors.green,
              ),
            if (signal.takeProfit3 != null)
              _buildLevelRow(
                'TP 3 (20%)',
                '${signal.takeProfit3!.toStringAsFixed(2)} (${_calcPercent(signal.takeProfit3!)}%)',
                Colors.green,
              ),
            Divider(),
            if (signal.riskRewardRatio != null)
              Text(
                'Risk/Reward: 1:${signal.riskRewardRatio!.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelRow(
    String label,
    String value,
    Color color, {
    bool isNegative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isNegative ? Colors.red : color,
            ),
          ),
        ],
      ),
    );
  }

  double _calcPercent(double price) {
    if (signal.entryPrice == null || signal.entryPrice == 0) return 0;
    return ((price - signal.entryPrice!) / signal.entryPrice! * 100);
  }

  Widget _buildTechnicalIndicators() {
    if (signal.technicalData.isEmpty) return SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Indicadores Técnicos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: signal.technicalData.entries.map((entry) {
                return _buildTechChip(entry.key, entry.value);
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechChip(String key, dynamic value) {
    String displayValue;
    Color color = Colors.grey;

    if (value is double) {
      displayValue = value.toStringAsFixed(4);
      if (key.contains('EMA'))
        color = Colors.blue;
      else if (key == 'ADX')
        color = value > 25 ? Colors.green : Colors.orange;
      else if (key == 'RSI')
        color = value < 30
            ? Colors.green
            : value > 70
            ? Colors.red
            : Colors.blue;
      else if (key == 'Squeeze')
        color = value > 0
            ? Colors.green
            : value < 0
            ? Colors.red
            : Colors.grey;
    } else {
      displayValue = value.toString();
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${_abbreviateKey(key)}: $displayValue',
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  String _abbreviateKey(String key) {
    Map<String, String> abbreviations = {
      'EMA9': 'e9',
      'EMA20': 'e20',
      'EMA50': 'e50',
      'EMA200': 'e200',
      'ADX': 'ADX',
      '+DI': '+DI',
      '-DI': '-DI',
      'RSI': 'RSI',
      'MACD': 'MACD',
      'Squeeze': 'SQ',
      'Volume': 'Vol',
      'AvgVolume': 'AvgV',
    };
    return abbreviations[key] ?? key;
  }

  Widget _buildAnalysisSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, size: 20),
                SizedBox(width: 8),
                Text(
                  'Análisis de la Señal',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12),
            ...signal.detailedReasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0, left: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: Colors.green),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(reason, style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningsSection() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Advertencias',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            ...signal.warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0, left: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning, size: 14, color: Colors.orange),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        warning,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.all(12),
        color: Colors.grey[100],
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showRiskCalculator(context),
                icon: Icon(Icons.calculate),
                label: Text('Calcular Riesgo'),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: signal.isReliable
                    ? () => _addToWatchlist(context)
                    : null,
                icon: Icon(Icons.bookmark_add),
                label: Text('Guardar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAIAnalysis(BuildContext context) async {
    if (aiService == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.psychology, color: Colors.purple),
            SizedBox(width: 8),
            Text('Análisis IA'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: FutureBuilder<String>(
            future: aiService!.explainSignal(signal, detailed: true),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Analizando señal con IA...'),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              return SingleChildScrollView(
                child: Text(snapshot.data ?? 'No hay análisis disponible'),
              );
            },
          ),
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

  void _showRiskCalculator(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Calculadora de Riesgo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Capital total (\$)',
                hintText: '10000',
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 12),
            Text(
              'Riesgo por operación: ${(config.maxRiskPerTrade * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (signal.entryPrice != null && signal.stopLoss != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Riesgo por Bitcoin: \$${_riskPerBTC().toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar'),
          ),
          FilledButton(
            onPressed: () {
              // Calcular monto sugerido
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(' Calculado: revisa tus settings')),
              );
            },
            child: Text('Calcular'),
          ),
        ],
      ),
    );
  }

  double _riskPerBTC() {
    if (signal.entryPrice == null || signal.stopLoss == null) return 0;
    return signal.entryPrice! - signal.stopLoss!;
  }

  void _addToWatchlist(BuildContext context) {
    // TODO: Implementar guardado en base de datos local
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Señal guardada en watchlist'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  TradingConfig get config =>
      TradingConfig(); // Usar global o pasar por parámetro
}
