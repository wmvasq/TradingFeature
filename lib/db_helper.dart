import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'conversations.db');

    return await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            text TEXT,
            conversation_max_score REAL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE phrase_scores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER,
            phrase_index INTEGER,
            max_score REAL DEFAULT 0,
            FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE daily_practice (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            conversation_id INTEGER,
            score REAL,
            FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE conversations ADD COLUMN conversation_max_score REAL DEFAULT 0',
          );
          await db.execute('''
            CREATE TABLE phrase_scores (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              conversation_id INTEGER,
              phrase_index INTEGER,
              max_score REAL DEFAULT 0,
              FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE daily_practice (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT,
              conversation_id INTEGER,
              score REAL,
              FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE ai_practice_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT,
              topic TEXT,
              avg_score REAL,
              exchanges INTEGER
            )
          ''');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE app_config (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              key TEXT UNIQUE NOT NULL,
              value TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  /// Insert a conversation: expects a Map with {title, text(List)}
  Future<int> insertConversation(Map<String, dynamic> conversation) async {
    final dbClient = await db;

    final title = conversation['title'];
    final textJson = jsonEncode(conversation['text']); // only the list

    return await dbClient.insert('conversations', {
      'title': title,
      'text': textJson,
    });
  }

  /// Get all conversations (only id + title)
  Future<List<Map<String, dynamic>>> getAllConversations() async {
    final dbClient = await db;
    return await dbClient.query(
      'conversations',
      columns: ['id', 'title', 'text', 'conversation_max_score'],
    );
  }

  /// Get one conversation by ID
  Future<Map<String, dynamic>?> getConversationById(int id) async {
    final dbClient = await db;
    final result = await dbClient.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) return null;

    final row = result.first;

    return {
      'id': row['id'],
      'title': row['title'],
      'text': jsonDecode(row['text'] as String),
      'conversation_max_score': row['conversation_max_score'] as double? ?? 0,
    };
  }

  /// Update conversation: title + text(list)
  Future<void> updateConversation(
    int id,
    Map<String, dynamic> conversation,
  ) async {
    final dbClient = await db;

    final title = conversation['title'];
    final textJson = jsonEncode(conversation['text']);

    await dbClient.update(
      'conversations',
      {'title': title, 'text': textJson},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete conversation
  Future<void> deleteConversation(int id) async {
    final dbClient = await db;
    await dbClient.delete(
      'phrase_scores',
      where: 'conversation_id = ?',
      whereArgs: [id],
    );
    await dbClient.delete(
      'daily_practice',
      where: 'conversation_id = ?',
      whereArgs: [id],
    );
    await dbClient.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  /// Get phrase scores for a conversation
  Future<Map<int, double>> getPhraseScores(int conversationId) async {
    final dbClient = await db;
    final result = await dbClient.query(
      'phrase_scores',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    final scores = <int, double>{};
    for (var row in result) {
      scores[row['phrase_index'] as int] = row['max_score'] as double;
    }
    return scores;
  }

  /// Save phrase score (only if higher than existing)
  Future<void> savePhraseScore(
    int conversationId,
    int phraseIndex,
    double score,
  ) async {
    final dbClient = await db;
    final existing = await dbClient.query(
      'phrase_scores',
      where: 'conversation_id = ? AND phrase_index = ?',
      whereArgs: [conversationId, phraseIndex],
    );

    if (existing.isEmpty) {
      await dbClient.insert('phrase_scores', {
        'conversation_id': conversationId,
        'phrase_index': phraseIndex,
        'max_score': score,
      });
    } else {
      final currentMax = existing.first['max_score'] as double;
      if (score > currentMax) {
        await dbClient.update(
          'phrase_scores',
          {'max_score': score},
          where: 'conversation_id = ? AND phrase_index = ?',
          whereArgs: [conversationId, phraseIndex],
        );
      }
    }
  }

  /// Update conversation's max score (average of all phrase scores)
  Future<void> updateConversationMaxScore(int conversationId) async {
    final dbClient = await db;
    final result = await dbClient.query(
      'phrase_scores',
      columns: ['max_score'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    if (result.isEmpty) return;

    double sum = 0;
    for (var row in result) {
      sum += row['max_score'] as double;
    }
    final avg = sum / result.length;

    await dbClient.update(
      'conversations',
      {'conversation_max_score': avg},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  /// Get conversation's max score
  Future<double> getConversationMaxScore(int conversationId) async {
    final dbClient = await db;
    final result = await dbClient.query(
      'conversations',
      columns: ['conversation_max_score'],
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    if (result.isEmpty) return 0;
    return result.first['conversation_max_score'] as double? ?? 0;
  }

  Future<void> saveDailyPractice(int conversationId, double score) async {
    final dbClient = await db;
    final today = DateTime.now().toIso8601String().split('T')[0];
    final existing = await dbClient.query(
      'daily_practice',
      where: 'date = ? AND conversation_id = ?',
      whereArgs: [today, conversationId],
    );
    if (existing.isEmpty) {
      await dbClient.insert('daily_practice', {
        'date': today,
        'conversation_id': conversationId,
        'score': score,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getDailyPracticeScores() async {
    final dbClient = await db;
    final result = await dbClient.rawQuery('''
      SELECT date, AVG(score) as avg_score
      FROM daily_practice
      GROUP BY date
      ORDER BY date DESC
      LIMIT 7
    ''');
    return result.reversed.toList();
  }

  Future<void> saveAIPracticeSession(
    String topic,
    double avgScore,
    int exchanges,
  ) async {
    final dbClient = await db;
    final today = DateTime.now().toIso8601String().split('T')[0];
    await dbClient.insert('ai_practice_sessions', {
      'date': today,
      'topic': topic,
      'avg_score': avgScore,
      'exchanges': exchanges,
    });
  }

  Future<List<Map<String, dynamic>>> getAISessionScores() async {
    final dbClient = await db;
    final result = await dbClient.rawQuery('''
      SELECT date, AVG(avg_score) as avg_score
      FROM ai_practice_sessions
      GROUP BY date
      ORDER BY date DESC
      LIMIT 7
    ''');
    return result.reversed.toList();
  }

  Future<double> getOverallAverageScore() async {
    final dbClient = await db;

    final convResult = await dbClient.rawQuery('''
      SELECT AVG(conversation_max_score) as avg FROM conversations
      WHERE conversation_max_score > 0
    ''');

    final aiResult = await dbClient.rawQuery('''
      SELECT AVG(avg_score) as avg FROM ai_practice_sessions
    ''');

    final convAvg = (convResult.first['avg'] as num?)?.toDouble() ?? 0.0;
    final aiAvg = (aiResult.first['avg'] as num?)?.toDouble() ?? 0.0;

    int count = 0;
    double sum = 0;

    if (convAvg > 0) {
      sum += convAvg;
      count++;
    }
    if (aiAvg > 0) {
      sum += aiAvg;
      count++;
    }

    return count > 0 ? sum / count : 0.0;
  }

  /// Guardar configuración de la aplicación
  Future<void> saveAppConfig(String key, String value) async {
    final dbClient = await db;
    await dbClient.execute(
      'INSERT OR REPLACE INTO app_config (id, key, value) VALUES ((SELECT id FROM app_config WHERE key = ?), ?, ?)',
      [key, key, value],
    );
  }

  /// Obtener configuración de la aplicación
  Future<String?> getAppConfig(String key) async {
    final dbClient = await db;
    final result = await dbClient.query(
      'app_config',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String;
  }

  /// Obtener toda la configuración
  Future<Map<String, String>> getAllAppConfig() async {
    final dbClient = await db;
    final result = await dbClient.query('app_config');
    final config = <String, String>{};
    for (var row in result) {
      config[row['key'] as String] = row['value'] as String;
    }
    return config;
  }

  /// Obtener el valor de configuración o un valor por defecto
  Future<String> getAppConfigOrDefault(String key, String defaultValue) async {
    final value = await getAppConfig(key);
    return value ?? defaultValue;
  }

  /// Eliminar configuración
  Future<void> deleteAppConfig(String key) async {
    final dbClient = await db;
    await dbClient.delete(
      'app_config',
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  Future<int> getTotalPracticeMinutes() async {
    final dbClient = await db;

    final convResult = await dbClient.rawQuery('''
      SELECT COUNT(*) as count FROM daily_practice
    ''');
    final convCount = (convResult.first['count'] as int?) ?? 0;

    final aiResult = await dbClient.rawQuery('''
      SELECT SUM(exchanges) as total FROM ai_practice_sessions
    ''');
    final aiExchanges = (aiResult.first['total'] as int?) ?? 0;

    final convMinutes = convCount * 10;
    final aiMinutes = aiExchanges * 3;

    return convMinutes + aiMinutes;
  }
}
