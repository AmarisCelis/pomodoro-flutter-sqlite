import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/database_helper.dart';
import '../services/notification_service.dart';
import 'settings_screen.dart';

enum FasePomodoro { trabajo, descanso }

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> with WidgetsBindingObserver {
  // Duraciones en segundos; se cargan desde SharedPreferences (ver _cargarTiempos).
  int _duracionTrabajo = 25 * 60;
  int _duracionDescanso = 5 * 60;

  /// Tarea provisional hasta que exista la selección de tareas en la UI.
  static const String _tareaProvisionalId = 'tarea-provisional';

  Timer? _timer;
  FasePomodoro _fase = FasePomodoro.trabajo;

  /// Segundos restantes que se muestran en pantalla.
  int _segundosRestantes = 25 * 60;

  /// Momento real en que se (re)inició el reloj.
  DateTime? _inicio;

  /// Segundos restantes que había justo cuando se guardó [_inicio].
  int _segundosAlIniciar = 25 * 60;

  /// Inicio de la sesión de trabajo actual (para guardarla en SQLite).
  DateTime? _inicioSesionTrabajo;

  /// Reproductor del beep de fin de fase (sonido forzado desde la app).
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool get _corriendo => _timer?.isActive ?? false;
  int get _duracionFase =>
      _fase == FasePomodoro.trabajo ? _duracionTrabajo : _duracionDescanso;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.init();
    _cargarTiempos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Lee los minutos guardados (o usa 25/5 por defecto) y deja el reloj en
  /// la fase de trabajo con la nueva duración.
  Future<void> _cargarTiempos() async {
    final prefs = await SharedPreferences.getInstance();
    final trabajo = prefs.getInt(SettingsScreen.claveTrabajo) ?? 25;
    final descanso = prefs.getInt(SettingsScreen.claveDescanso) ?? 5;
    if (!mounted) return;
    setState(() {
      _duracionTrabajo = trabajo * 60;
      _duracionDescanso = descanso * 60;
      if (!_corriendo) {
        _fase = FasePomodoro.trabajo;
        _segundosRestantes = _duracionTrabajo;
        _segundosAlIniciar = _duracionTrabajo;
      }
    });
  }

  /// Abre Configuración; si se guardaron cambios (true), recarga los tiempos,
  /// actualiza la UI y reinicia el reloj con las nuevas duraciones.
  Future<void> _abrirConfiguracion() async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (guardado == true) {
      _timer?.cancel();
      _inicio = null;
      NotificationService.instance.cancelar();
      await _cargarTiempos(); // incluye setState y reinicia a fase de trabajo
      if (mounted) setState(() {});
    }
  }

  // ------------------------------------------------------- Segundo plano
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _inicio != null) {
      // Recalcula con el reloj real: el Timer pudo congelarse en background.
      _sincronizarConRelojReal();
    }
  }

  /// Calcula los segundos restantes usando la diferencia de tiempo real
  /// entre [_inicio] y ahora, en lugar de confiar en los ticks del Timer.
  void _sincronizarConRelojReal() {
    if (_inicio == null) return;
    final transcurridos = DateTime.now().difference(_inicio!).inSeconds;
    final restantes = _segundosAlIniciar - transcurridos;

    if (restantes <= 0) {
      setState(() => _segundosRestantes = 0);
      _finalizarFase();
    } else {
      setState(() => _segundosRestantes = restantes);
    }
  }

  // ------------------------------------------------------------ Controles
  void _iniciar() {
    if (_corriendo) return;
    _inicio = DateTime.now();
    _segundosAlIniciar = _segundosRestantes;
    if (_fase == FasePomodoro.trabajo &&
        _segundosRestantes == _duracionTrabajo) {
      _inicioSesionTrabajo = _inicio;
    }
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _sincronizarConRelojReal(),
    );
    _programarNotificacion();
    setState(() {});
  }

  /// Programa el aviso del SO para cuando termine la fase actual (R-01).
  void _programarNotificacion() {
    final esTrabajo = _fase == FasePomodoro.trabajo;
    NotificationService.instance.programarFinDeFase(
      segundos: _segundosRestantes,
      titulo: 'Tiempo terminado',
      cuerpo: esTrabajo
          ? 'Completaste un Pomodoro. Descansa ${_duracionDescanso ~/ 60} minutos.'
          : 'El descanso terminó. ¡A concentrarse!',
    );
  }

  void _pausar() {
    if (!_corriendo) return;
    _sincronizarConRelojReal();
    _timer?.cancel();
    _inicio = null;
    NotificationService.instance.cancelar();
    setState(() {});
  }

  void _cancelar() {
    _timer?.cancel();
    NotificationService.instance.cancelar();
    setState(() {
      _inicio = null;
      _inicioSesionTrabajo = null;
      _fase = FasePomodoro.trabajo;
      _segundosRestantes = _duracionTrabajo;
      _segundosAlIniciar = _duracionTrabajo;
    });
  }

  /// Reproduce el beep de alerta; un fallo de audio nunca debe romper el flujo.
  Future<void> _reproducirBeep() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/beep.wav'));
    } catch (e) {
      debugPrint('No se pudo reproducir el beep: $e');
    }
  }

  void _finalizarFase() {
    _timer?.cancel();
    _inicio = null;
    _reproducirBeep();

    if (_fase == FasePomodoro.trabajo) {
      // ⏱️ El contador llegó a 00:00 → persistir la sesión en SQLite.
      _guardarSesionLocal();
      _fase = FasePomodoro.descanso;
    } else {
      _fase = FasePomodoro.trabajo;
    }

    setState(() {
      _segundosRestantes = _duracionFase;
      _segundosAlIniciar = _duracionFase;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_fase == FasePomodoro.descanso
            ? '¡Pomodoro completado! Toma un descanso de ${_duracionDescanso ~/ 60} minutos.'
            : 'Descanso terminado. ¡A trabajar!'),
      ));
    }
  }

  /// Guarda la sesión de trabajo completada en SQLite (sin bloquear la UI).
  ///
  /// `tarea_id` es NOT NULL y tiene FOREIGN KEY (foreign_keys = ON), así que
  /// no se puede usar null ni un id inexistente: se usa una tarea provisional
  /// fija ([_tareaProvisionalId]) que se crea si aún no existe.
  Future<void> _guardarSesionLocal() async {
    final inicio = _inicioSesionTrabajo;
    if (inicio == null) return;

    try {
      final db = DatabaseHelper.instance;
      await db.insertarTarea({
        'id': _tareaProvisionalId,
        'titulo': 'Sin tarea asignada',
        'completada': 0,
        'pomodoros_estimados': 1,
      });
      await db.insertarSesion({
        'id': const Uuid().v4(),
        'tarea_id': _tareaProvisionalId,
        'fecha_inicio': inicio.toUtc().toIso8601String(),
        'duracion_minutos': _duracionTrabajo ~/ 60,
        'estado': 'completada',
      });
      debugPrint('Sesión guardada (inicio: $inicio)');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sesión guardada en el historial'),
        ));
      }
    } catch (e) {
      debugPrint('No se pudo guardar la sesión: $e');
    }
  }

  // ------------------------------------------------------------------- UI
  String get _tiempoFormateado {
    final m = (_segundosRestantes ~/ 60).toString().padLeft(2, '0');
    final s = (_segundosRestantes % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final esTrabajo = _fase == FasePomodoro.trabajo;
    final colorFase = esTrabajo ? scheme.primary : scheme.tertiary;
    final progreso = 1 - _segundosRestantes / _duracionFase;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomodoro'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
            onPressed: _abrirConfiguracion,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Chip(
                label: Text(esTrabajo ? 'Trabajo' : 'Descanso'),
                avatar: Icon(esTrabajo ? Icons.work : Icons.coffee,
                    color: colorFase),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  _tiempoFormateado,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: 96,
                        fontWeight: FontWeight.bold,
                        color: colorFase,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progreso,
                minHeight: 8,
                color: colorFase,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 48),
              _BotonGrande(
                key: const Key('btn_iniciar'),
                label: 'Iniciar',
                icon: Icons.play_arrow,
                onPressed: _corriendo ? null : _iniciar,
              ),
              const SizedBox(height: 12),
              _BotonGrande(
                key: const Key('btn_pausar'),
                label: 'Pausar',
                icon: Icons.pause,
                tonal: true,
                onPressed: _corriendo ? _pausar : null,
              ),
              const SizedBox(height: 12),
              _BotonGrande(
                key: const Key('btn_cancelar'),
                label: 'Cancelar',
                icon: Icons.stop,
                outlined: true,
                onPressed: _cancelar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tonal = false,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool tonal;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(64)),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleLarge),
    );
    final child = Text(label);
    final iconW = Icon(icon, size: 28);

    if (outlined) {
      return OutlinedButton.icon(
          onPressed: onPressed, icon: iconW, label: child, style: style);
    }
    if (tonal) {
      return FilledButton.tonalIcon(
          onPressed: onPressed, icon: iconW, label: child, style: style);
    }
    return FilledButton.icon(
        onPressed: onPressed, icon: iconW, label: child, style: style);
  }
}
