import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();

  factory DatabaseHelper() => instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'v2ray_tunnel_v7.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE networks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        country TEXT,
        isp TEXT,
        name TEXT,
        host TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE keys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid_or_pass TEXT,
        path TEXT,
        protocol TEXT,
        ip TEXT,
        port INTEGER,
        security TEXT,
        type TEXT,
        host_header TEXT,
        ping_ms INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE static_servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        address TEXT,
        port INTEGER,
        protocol TEXT,
        uuid TEXT,
        sni TEXT,
        host TEXT,
        path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE user_session (
        id INTEGER PRIMARY KEY,
        remaining_seconds INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS keys');
      await db.execute('''
        CREATE TABLE keys (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uuid_or_pass TEXT,
          path TEXT,
          protocol TEXT,
          ip TEXT,
          port INTEGER,
          security TEXT,
          type TEXT,
          host_header TEXT,
          ping_ms INTEGER DEFAULT 0
        )
      ''');
    }
  }

  // Network Methods
  Future<void> insertNetwork(Map<String, dynamic> network) async {
    final db = await database;
    await db.insert(
      'networks',
      network,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllNetworks() async {
    final db = await database;
    return await db.query('networks');
  }

  Future<List<String>> getCountries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'networks',
      columns: ['DISTINCT country'],
    );
    return maps.map((m) => m['country']?.toString() ?? '').where((c) => c.isNotEmpty).toList();
  }

  Future<List<String>> getIspsForCountry(String country) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'networks',
      columns: ['DISTINCT isp'],
      where: 'country = ?',
      whereArgs: [country],
    );
    return maps.map((m) => m['isp']?.toString() ?? '').where((i) => i.isNotEmpty).toList();
  }

  Future<List<String>> getHostsForIsp(String isp) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'networks',
      where: 'isp = ?',
      whereArgs: [isp],
    );
    return maps.map((map) => map['host']?.toString() ?? '').where((h) => h.isNotEmpty).toList();
  }

  // Key Methods
  Future<void> insertKey(Map<String, dynamic> keyData) async {
    final db = await database;
    await db.insert(
      'keys',
      keyData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearKeys() async {
    final db = await database;
    await db.delete('keys');
  }

  Future<Map<String, dynamic>?> getFirstKey() async {
    try {
      final db = await database;
      List<Map<String, dynamic>> results = await db.query(
        'keys',
        limit: 1,
      );
      if (results.isNotEmpty) {
        return results.first;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getFastestKey() async {
    try {
      final db = await database;
      List<Map<String, dynamic>> results = await db.query(
        'keys',
        orderBy: 'ping_ms ASC',
        limit: 1,
      );
      if (results.isNotEmpty) {
        return results.first;
      }
    } catch (_) {}
    return getFirstKey();
  }

  // Static Server Methods
  Future<void> insertStaticServer(Map<String, dynamic> serverData) async {
    final db = await database;
    await db.insert(
      'static_servers',
      serverData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllStaticServers() async {
    try {
      final db = await database;
      return await db.query('static_servers');
    } catch (_) {
      return [];
    }
  }

  // User Session Methods
  Future<void> initializeSession() async {
    final db = await database;
    await db.insert(
      'user_session',
      {
        'id': 1,
        'remaining_seconds': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> getRemainingTime() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> results = await db.query(
        'user_session',
        columns: ['remaining_seconds'],
        where: 'id = ?',
        whereArgs: [1],
      );
      if (results.isNotEmpty) {
        return results.first['remaining_seconds'] as int? ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  Future<void> updateRemainingTime(int seconds) async {
    try {
      final db = await database;
      await db.update(
        'user_session',
        {'remaining_seconds': seconds},
        where: 'id = ?',
        whereArgs: [1],
      );
    } catch (_) {}
  }
}
