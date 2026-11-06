import 'package:sqflite/sqflite.dart';
import '../db_helper.dart';
import 'models.dart';
import 'setups.dart';

/// Almacenamiento de setups. Hoy es SQLite local; para la nube basta con
/// otra implementación de esta interfaz.
abstract class SetupRepository {
  /// Guarda el setup. Devuelve false si ya existía (misma `key`).
  Future<bool> save(SavedSetup setup);
  Future<List<SavedSetup>> all();
  Future<void> update(SavedSetup setup);
  Future<void> delete(int id);
}

class SqfliteSetupRepository implements SetupRepository {
  static const _table = 'trading_setups';

  Future<Database> get _db => DBHelper().db;

  @override
  Future<bool> save(SavedSetup setup) async {
    final id = await (await _db).insert(_table, {
      'setup_key': setup.key,
      ..._toRow(setup),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    // Con conflicto ignorado sqflite devuelve 0 o -1 según la plataforma
    return id > 0;
  }

  @override
  Future<List<SavedSetup>> all() async {
    final rows = await (await _db).query(_table, orderBy: 'signal_time DESC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> update(SavedSetup setup) async {
    await (await _db).update(
      _table,
      _toRow(setup),
      where: 'id = ?',
      whereArgs: [setup.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await (await _db).delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, Object?> _toRow(SavedSetup s) => {
    'symbol': s.symbol,
    'asset_label': s.assetLabel,
    'interval': s.interval,
    'strategy': s.strategy,
    'direction': s.direction.name,
    'origin': s.origin.name,
    'state': s.state.name,
    'entry': s.entry,
    'stop_loss': s.stopLoss,
    'take_profit': s.takeProfit,
    'summary': s.summary,
    'signal_time': s.signalTime.millisecondsSinceEpoch,
    'created_at': s.createdAt.millisecondsSinceEpoch,
    'triggered_at': s.triggeredAt?.millisecondsSinceEpoch,
    'resolved_at': s.resolvedAt?.millisecondsSinceEpoch,
    'checked_until': s.checkedUntil.millisecondsSinceEpoch,
    'candles_checked': s.candlesChecked,
  };

  static SavedSetup _fromRow(Map<String, Object?> r) {
    DateTime time(String column) =>
        DateTime.fromMillisecondsSinceEpoch(r[column] as int);
    DateTime? maybeTime(String column) =>
        r[column] == null ? null : time(column);

    return SavedSetup(
      id: r['id'] as int,
      symbol: r['symbol'] as String,
      assetLabel: r['asset_label'] as String,
      interval: r['interval'] as String,
      strategy: r['strategy'] as String,
      direction: Direction.values.byName(r['direction'] as String),
      origin: SetupOrigin.values.byName(r['origin'] as String),
      state: SetupState.values.byName(r['state'] as String),
      entry: (r['entry'] as num).toDouble(),
      stopLoss: (r['stop_loss'] as num).toDouble(),
      takeProfit: (r['take_profit'] as num).toDouble(),
      summary: r['summary'] as String? ?? '',
      signalTime: time('signal_time'),
      createdAt: time('created_at'),
      triggeredAt: maybeTime('triggered_at'),
      resolvedAt: maybeTime('resolved_at'),
      checkedUntil: time('checked_until'),
      candlesChecked: r['candles_checked'] as int,
    );
  }
}
