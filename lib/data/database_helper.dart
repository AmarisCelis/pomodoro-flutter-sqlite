import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Import condicional: en web se usa el stub para que dart:ffi no se compile.
import 'sqlite_init_web.dart'
    if (dart.library.io) 'sqlite_init_io.dart';

/// Core local offline-first (SQLite) – patrón Singleton.
class DatabaseHelper {
  static const String _dbName = 'pomodoro.db';
  static const int _dbVersion = 1;

  static const String tablaTareas = 'tareas';
  static const String tablaSesiones = 'sesiones';

  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;

  static Database? _database;

  /// SQLite solo está disponible fuera de la web.
  static bool get soportado => !kIsWeb;

  /// Llamar una vez en `main()` antes de usar la base de datos.
  /// - Web: solo imprime 'SQLite no soportado en Web'.
  /// - Escritorio: sqfliteFfiInit() + databaseFactoryFfi.
  /// - Android/iOS: sqflite estándar.
  static void inicializarPlataforma() => inicializarSqlitePlataforma();

  Future<Database> get database async {
    if (!soportado) {
      throw UnsupportedError('SQLite no soportado en Web');
    }
    return _database ??= await _initDatabase();
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onOpen: (db) async {
        // Mantiene el archivo compacto (objetivo < 50MB).
        await db.rawQuery('PRAGMA auto_vacuum = INCREMENTAL');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // WITHOUT ROWID: con PK TEXT evita el índice rowid duplicado -> menos peso.
    await db.execute('''
      CREATE TABLE $tablaTareas (
        id TEXT PRIMARY KEY NOT NULL,
        titulo TEXT NOT NULL,
        completada INTEGER NOT NULL DEFAULT 0,
        pomodoros_estimados INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      ) WITHOUT ROWID
    ''');

    await db.execute('''
      CREATE TABLE $tablaSesiones (
        id TEXT PRIMARY KEY NOT NULL,
        tarea_id TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        duracion_minutos INTEGER NOT NULL,
        estado TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (tarea_id) REFERENCES $tablaTareas (id) ON DELETE CASCADE
      ) WITHOUT ROWID
    ''');

    await db.execute(
        'CREATE INDEX idx_sesiones_tarea ON $tablaSesiones (tarea_id)');
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  // ---------------------------------------------------------------- TAREAS
  Future<int> insertarTarea(Map<String, dynamic> tarea) async {
    if (!soportado) return 0;
    final db = await database;
    return db.insert(
      tablaTareas,
      {...tarea, 'updated_at': tarea['updated_at'] ?? _now()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listarTareas() async {
    if (!soportado) return [];
    final db = await database;
    return db.query(tablaTareas, orderBy: 'updated_at DESC');
  }

  Future<int> actualizarTarea(Map<String, dynamic> tarea) async {
    if (!soportado) return 0;
    final db = await database;
    return db.update(
      tablaTareas,
      {...tarea, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [tarea['id']],
    );
  }

  // -------------------------------------------------------------- SESIONES
  Future<int> insertarSesion(Map<String, dynamic> sesion) async {
    if (!soportado) return 0;
    final db = await database;
    return db.insert(
      tablaSesiones,
      {...sesion, 'updated_at': sesion['updated_at'] ?? _now()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> listarSesiones() async {
    if (!soportado) return [];
    final db = await database;
    return db.query(tablaSesiones, orderBy: 'fecha_inicio DESC');
  }

  Future<int> actualizarSesion(Map<String, dynamic> sesion) async {
    if (!soportado) return 0;
    final db = await database;
    return db.update(
      tablaSesiones,
      {...sesion, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [sesion['id']],
    );
  }

  /// Payload listo para POST /api/sync.
  Future<Map<String, dynamic>> exportarParaSync() async => {
        'tasks': await listarTareas(),
        'sessions': await listarSesiones(),
      };

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
