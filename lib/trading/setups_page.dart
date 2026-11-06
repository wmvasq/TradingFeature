import 'package:flutter/material.dart';
import 'models.dart';
import 'setup_repository.dart';
import 'setup_tracker.dart';
import 'setups.dart';

/// Lista de setups guardados con su seguimiento y estadísticas.
class SetupsPage extends StatefulWidget {
  final SetupRepository repository;

  const SetupsPage({super.key, required this.repository});

  @override
  State<SetupsPage> createState() => _SetupsPageState();
}

class _SetupsPageState extends State<SetupsPage> {
  List<SavedSetup>? _setups;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    // Primero mostrar lo guardado; luego actualizar con las velas nuevas
    final saved = await widget.repository.all();
    if (mounted) setState(() => _setups = saved);
    final tracked = await SetupTracker(widget.repository).refresh();
    if (!mounted) return;
    setState(() {
      _setups = tracked;
      _refreshing = false;
    });
  }

  Future<bool> _confirmDelete(SavedSetup s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar setup?'),
        content: Text('${s.assetLabel} ${s.interval} · ${s.strategy}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final setups = _setups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar seguimiento',
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: setups == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_refreshing) const LinearProgressIndicator(),
                  _StatsCard(stats: SetupStats.of(setups)),
                  const SizedBox(height: 8),
                  if (setups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Todavía no hay setups. Las entradas se guardan solas '
                        'mientras miras el gráfico, y los setups en espera con '
                        'el botón "Guardar setup".',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final s in setups)
                    Dismissible(
                      key: ValueKey(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: Colors.red.withValues(alpha: 0.2),
                        child: const Icon(Icons.delete),
                      ),
                      confirmDismiss: (_) => _confirmDelete(s),
                      onDismissed: (_) {
                        widget.repository.delete(s.id!);
                        setState(() => _setups = [...setups]..remove(s));
                      },
                      child: _SetupTile(setup: s),
                    ),
                ],
              ),
            ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final SetupStats stats;

  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final winRate = stats.winRate;
    final rColor = stats.totalR >= 0 ? Colors.green : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _stat('Setups', '${stats.total}'),
            _stat('Activos', '${stats.active}'),
            _stat('Ganados / perdidos', '${stats.won} / ${stats.lost}'),
            _stat(
              'Win rate',
              winRate == null ? '—' : '${(winRate * 100).toStringAsFixed(0)}%',
            ),
            _stat(
              'Resultado',
              '${stats.totalR >= 0 ? '+' : ''}${stats.totalR.toStringAsFixed(2)} R',
              color: rColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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

class _SetupTile extends StatelessWidget {
  final SavedSetup setup;

  const _SetupTile({required this.setup});

  @override
  Widget build(BuildContext context) {
    final s = setup;
    final (label, color) = switch (s.state) {
      SetupState.pending => ('En espera', Colors.orange),
      SetupState.open => ('Abierto', Colors.blue),
      SetupState.won => (
        '+${s.plannedRiskReward.toStringAsFixed(2)} R',
        Colors.green,
      ),
      SetupState.lost => ('-1 R', Colors.red),
      SetupState.expired => ('Expirado', Colors.grey),
    };
    final directionText = s.direction == Direction.long ? 'LONG' : 'SHORT';

    return Card(
      child: ListTile(
        title: Text(
          '${s.assetLabel} ${s.interval} · ${s.strategy} · $directionText',
        ),
        subtitle: Text(
          'E ${_fmt(s.entry)} · SL ${_fmt(s.stopLoss)} · TP ${_fmt(s.takeProfit)}\n'
          '${_formatTime(s.signalTime)}'
          '${s.origin == SetupOrigin.manual ? ' · manual' : ''}',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(label, style: TextStyle(color: color)),
          backgroundColor: color.withValues(alpha: 0.12),
          side: BorderSide.none,
        ),
      ),
    );
  }

  static String _fmt(double v) => v.toStringAsFixed(v >= 100 ? 2 : 4);

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
