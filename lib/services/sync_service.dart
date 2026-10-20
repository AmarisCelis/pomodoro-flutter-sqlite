import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';

/// Error legible para mostrar al usuario cuando falla la sincronización.
class SyncException implements Exception {
  SyncException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Cliente de la API Laravel: inicia sesión y envía los datos locales a POST /api/sync.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  /// 10.0.2.2 es la dirección del equipo anfitrión desde el emulador de Android.
  static const String urlPorDefecto = 'http://10.0.2.2:8000/api';

  static const String _claveUrl = 'sync_url';
  static const String _claveToken = 'sync_token';

  Future<String> obtenerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_claveUrl) ?? urlPorDefecto;
  }

  Future<bool> haySesion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_claveToken) != null;
  }

  Future<void> iniciarSesion({
    required String url,
    required String email,
    required String password,
  }) async {
    final respuesta = await _enviar(
      () => http.post(
        Uri.parse('$url/login'),
        headers: _cabeceras(),
        body: jsonEncode({
          'email': email,
          'password': password,
          'device_name': 'app-pomodoro',
        }),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveUrl, url);
    await prefs.setString(_claveToken, respuesta['token'] as String);
  }

  Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveToken);
  }

  /// Envía tareas, sesiones y borrados. Devuelve un resumen para el usuario.
  Future<String> sincronizar() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_claveUrl) ?? urlPorDefecto;
    final token = prefs.getString(_claveToken);
    if (token == null) {
      throw SyncException('Inicia sesión antes de sincronizar.');
    }

    final payload = await DatabaseHelper.instance.exportarParaSync();
    final respuesta = await _enviar(
      () => http.post(
        Uri.parse('$url/sync'),
        headers: {..._cabeceras(), 'Authorization': 'Bearer $token'},
        body: jsonEncode(payload),
      ),
    );

    // Solo se quitan los borrados pendientes cuando el servidor confirmó todo.
    await DatabaseHelper.instance.limpiarEliminadas(
      List<String>.from(payload['tareas_eliminadas'] as List),
    );

    final afectados = respuesta['affected'] as Map<String, dynamic>;
    final tareas = (afectados['tasks'] as Map<String, dynamic>)['affected'];
    final sesiones = (afectados['sessions'] as Map<String, dynamic>)['affected'];
    return 'Sincronizado: $tareas tareas y $sesiones sesiones.';
  }

  Map<String, String> _cabeceras() => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _enviar(
    Future<http.Response> Function() peticion,
  ) async {
    http.Response respuesta;
    try {
      respuesta = await peticion();
    } catch (_) {
      throw SyncException('No se pudo conectar con el servidor.');
    }

    final cuerpo = respuesta.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(respuesta.body) as Map<String, dynamic>;
    if (respuesta.statusCode == 200) return cuerpo;

    throw SyncException(
      cuerpo['message'] as String? ?? 'Error ${respuesta.statusCode} del servidor.',
    );
  }
}
