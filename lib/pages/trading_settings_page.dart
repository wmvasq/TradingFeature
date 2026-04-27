import 'package:flutter/material.dart';
import '../models/trading_models.dart';

/// Página de configuración del sistema de trading
class TradingSettingsPage extends StatefulWidget {
  final TradingConfig config;

  const TradingSettingsPage({super.key, required this.config});

  @override
  State<TradingSettingsPage> createState() => _TradingSettingsPageState();
}

class _TradingSettingsPageState extends State<TradingSettingsPage> {
  late TradingConfig _localConfig;

  @override
  void initState() {
    super.initState();
    _localConfig = widget.config;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Configuración de Trading')),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Sección: Capital
          _buildSection('Gestión de Capital', [
            _buildSliderSetting(
              'Capital Total (\$)',
              _localConfig.totalCapital,
              1000,
              100000,
              1000,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(totalCapital: v),
              ),
            ),
            _buildPercentageSlider(
              'Largo Plazo (40%)',
              _localConfig.percentLongTerm,
              0,
              1,
              0.05,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(percentLongTerm: v),
              ),
            ),
            _buildPercentageSlider(
              'Swing Semanal (30%)',
              _localConfig.percentWeekly,
              0,
              1,
              0.05,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(percentWeekly: v),
              ),
            ),
            _buildPercentageSlider(
              'Day Trading (20%)',
              _localConfig.percentDaily,
              0,
              1,
              0.05,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(percentDaily: v),
              ),
            ),
            _buildPercentageSlider(
              'Futuros (10%)',
              _localConfig.percentFutures,
              0,
              1,
              0.05,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(percentFutures: v),
              ),
            ),
          ]),
          SizedBox(height: 20),

          // Sección: Indicadores
          _buildSection('Indicadores Técnicos', [
            _buildSliderSetting(
              'EMA Rápida',
              _localConfig.emaFastPeriod.toDouble(),
              5,
              50,
              1,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(
                  emaFastPeriod: v.round(),
                ),
              ),
              suffix: 'px',
            ),
            _buildSliderSetting(
              'EMA Media',
              _localConfig.emaMediumPeriod.toDouble(),
              10,
              100,
              1,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(
                  emaMediumPeriod: v.round(),
                ),
              ),
              suffix: 'px',
            ),
            _buildSliderSetting(
              'EMA Lenta',
              _localConfig.emaSlowPeriod.toDouble(),
              20,
              200,
              1,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(
                  emaSlowPeriod: v.round(),
                ),
              ),
              suffix: 'px',
            ),
            _buildSliderSetting(
              'EMA Larga',
              _localConfig.emaLongPeriod.toDouble(),
              50,
              500,
              5,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(
                  emaLongPeriod: v.round(),
                ),
              ),
              suffix: 'px',
            ),
            _buildSliderSetting(
              'ADX Período',
              _localConfig.adxPeriod.toDouble(),
              5,
              30,
              1,
              (v) => setState(
                () =>
                    _localConfig = _localConfig.copyWith(adxPeriod: v.round()),
              ),
            ),
            _buildSliderSetting(
              'ADX Umbral',
              _localConfig.adxThreshold,
              15,
              40,
              1,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(adxThreshold: v),
              ),
            ),
          ]),
          SizedBox(height: 20),

          // Sección: Riesgo
          _buildSection('Gestión de Riesgo', [
            _buildPercentageSlider(
              'Riesgo máximo por trade',
              _localConfig.maxRiskPerTrade,
              0.005,
              0.10,
              0.005,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(maxRiskPerTrade: v),
              ),
            ),
            _buildPercentageSlider(
              'Stop Loss por defecto',
              _localConfig.defaultStopLoss,
              0.01,
              0.10,
              0.005,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(defaultStopLoss: v),
              ),
            ),
            _buildSliderSetting(
              'Risk/Reward mínimo',
              _localConfig.riskRewardRatio,
              1,
              5,
              0.5,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(riskRewardRatio: v),
              ),
            ),
            _buildPercentageSlider(
              'Máx pérdida diaria',
              _localConfig.maxDailyLoss,
              0.01,
              0.20,
              0.01,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(maxDailyLoss: v),
              ),
            ),
          ]),
          SizedBox(height: 20),

          // Sección: Filtros
          _buildSection('Filtros de Mercado', [
            SwitchListTile(
              title: Text('Evitar operar cerca de Halving'),
              subtitle: Text('Según recomendación de Merino'),
              value: _localConfig.avoidHalvingPeriod,
              onChanged: (v) => setState(
                () =>
                    _localConfig = _localConfig.copyWith(avoidHalvingPeriod: v),
              ),
            ),
            _buildSliderSetting(
              'Días de evitación',
              _localConfig.halvingAvoidanceDays.toDouble(),
              1,
              30,
              1,
              (v) => setState(
                () => _localConfig = _localConfig.copyWith(
                  halvingAvoidanceDays: v.round(),
                ),
              ),
            ),
          ]),
          SizedBox(height: 30),

          // Botones
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetToDefaults,
                  child: Text('Restablecer'),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saveConfig,
                  child: Text('Guardar Configuración'),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Text(
            'Nota: Los cambios afectarán las futuras señales generadas.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[800],
              ),
            ),
            SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSetting(
    String label,
    double value,
    double min,
    double max,
    double divisions,
    Function(double) onChanged, {
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 14)),
              Text(
                suffix != null
                    ? '${value.toInt()}${suffix}'
                    : value.toStringAsFixed(2),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / divisions).round(),
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildPercentageSlider(
    String label,
    double value,
    double min,
    double max,
    double step,
    Function(double) onChanged,
  ) {
    return _buildSliderSetting(
      label,
      value,
      min,
      max,
      step,
      onChanged,
      suffix: '%',
    );
  }

  void _resetToDefaults() {
    setState(() {
      _localConfig = TradingConfig(); // valores por defecto
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Configuración restablecida a valores por defecto'),
      ),
    );
  }

  void _saveConfig() {
    // TODO: Guardar en SharedPreferences o base de datos
    Navigator.pop(context, _localConfig); // Devolver config actualizada
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Configuración guardada'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
