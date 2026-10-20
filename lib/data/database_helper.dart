import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// Import condicional: en web se usa el stub para que dart:ffi no se compile.
import 'sqlite_init_web.dart'
    if (dart.library.io) 'sqlite_init_io.dart';

/// Core local offline-first (SQLite) – patrón Singleton.
class DatabaseHelper {
  static const String _dbName = 'pomodoro.db';
  static const int _dbVersion = 2;

  static const String tablaTareas = 'tareas';
  static const String tablaSesiones = 'sesiones';

  /// Tareas borradas en el teléfono que aún no llegaron al servidor.
  static const String tablaEliminadas = 'tareas_eliminadas';

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
      onUpgrade: _onUpgrade,
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
    await _crearTablaEliminadas(db);
  }

  /// Versión 2: se agrega la tabla de borrados pendientes de sincronizar.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _crearTablaEliminadas(db);
  }

  Future<void> _crearTablaEliminadas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tablaEliminadas (
        id TEXT PRIMARY KEY NOT NULL,
        eliminada_en TEXT NOT NULL
      )
    ''');
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

  /// Borra la tarea (y sus sesiones, por cascada) y deja constancia del borrado
  /// para enviarlo en la siguiente sincronización.
  Future<int> eliminarTarea(String id) async {
    if (!soportado) return 0;
    final db = await database;
    return db.transaction<int>((txn) async {
      await txn.insert(
        tablaEliminadas,
        {'id': id, 'eliminada_en': _now()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return txn.delete(tablaTareas, where: 'id = ?', whereArgs: [id]);
    });
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

  /// Sesiones completadas con el título de su tarea, para estadísticas.
  Future<List<Map<String, dynamic>>> listarSesionesCompletadasConTitulo() async {
    if (!soportado) return [];
    final db = await database;
    return db.rawQuery('''
      SELECT s.*, t.titulo AS tarea_titulo
      FROM sesiones s
      LEFT JOIN tareas t ON s.tarea_id = t.id
      WHERE s.estado = 'completada'
      ORDER BY s.fecha_inicio DESC
    ''');
  }

  /// Ids de las tareas borradas que aún no llegaron al servidor.
  Future<List<String>> listarEliminadas() async {
    if (!soportado) return [];
    final db = await database;
    final filas = await db.query(tablaEliminadas, columns: ['id']);
    return filas.map((fila) => fila['id'] as String).toList();
  }

  /// Quita los borrados que el servidor ya confirmó.
  Future<void> limpiarEliminadas(List<String> ids) async {
    if (!soportado || ids.isEmpty) return;
    final db = await database;
    final marcas = List.filled(ids.length, '?').join(',');
    await db.delete(
      tablaEliminadas,
      where: 'id IN ($marcas)',
      whereArgs: ids,
    );
  }

  /// Payload listo para POST /api/sync.
  Future<Map<String, dynamic>> exportarParaSync() async => {
        'tasks': await listarTareas(),
        'sessions': await listarSesiones(),
        'tareas_eliminadas': await listarEliminadas(),
      };

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
