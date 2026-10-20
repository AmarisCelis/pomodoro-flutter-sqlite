/// Fases del pomodoro.
enum FasePomodoro { trabajo, descanso }

/// Sesión de trabajo terminada, lista para guardarse en la base de datos.
class SesionCompletada {
  const SesionCompletada({
    required this.tareaId,
    required this.inicio,
    required this.minutos,
  });

  final String tareaId;
  final DateTime inicio;
  final int minutos;
}

/// Lógica del temporizador sin widgets: fases, tiempo restante y sesión en curso.
///
/// La pantalla solo lo llama para iniciar, pausar, sincronizar con el reloj y
/// reaccionar al fin de fase. Así la lógica se puede probar sin Flutter.
class CicloPomodoro {
  CicloPomodoro({this.minutosTrabajo = 25, this.minutosDescanso = 5})
      : segundosRestantes = minutosTrabajo * 60;

  int minutosTrabajo;
  int minutosDescanso;
  FasePomodoro fase = FasePomodoro.trabajo;
  int segundosRestantes;

  DateTime? _inicioReloj;
  int _segundosAlIniciar = 0;
  DateTime? _inicioSesion;
  String? _tareaSesion;

  bool get corriendo => _inicioReloj != null;

  /// Verdadero desde que empieza una fase de trabajo hasta que termina o se cancela.
  bool get haySesionEnCurso => _inicioSesion != null;

  int get duracionFase =>
      (fase == FasePomodoro.trabajo ? minutosTrabajo : minutosDescanso) * 60;

  /// Fracción de la fase que ya pasó, de 0 a 1.
  double get progreso => 1 - segundosRestantes / duracionFase;

  /// Aplica los minutos nuevos. Si el reloj corre, no cambia nada.
  void aplicarTiempos(int trabajo, int descanso) {
    if (corriendo) return;
    minutosTrabajo = trabajo;
    minutosDescanso = descanso;
    fase = FasePomodoro.trabajo;
    segundosRestantes = duracionFase;
  }

  /// Inicia o reanuda el reloj. Devuelve false si falta la tarea en fase de trabajo.
  bool iniciar({required String? tareaId, required DateTime ahora}) {
    if (corriendo) return true;
    if (fase == FasePomodoro.trabajo && tareaId == null) return false;

    final nuevaSesion =
        fase == FasePomodoro.trabajo && segundosRestantes == duracionFase;
    _inicioReloj = ahora;
    _segundosAlIniciar = segundosRestantes;
    if (nuevaSesion) {
      _inicioSesion = ahora;
      _tareaSesion = tareaId;
    }
    return true;
  }

  /// Recalcula el tiempo restante con el reloj real. Devuelve true si la fase terminó.
  bool sincronizar(DateTime ahora) {
    final inicio = _inicioReloj;
    if (inicio == null) return false;

    final restantes =
        _segundosAlIniciar - ahora.difference(inicio).inSeconds;
    segundosRestantes = restantes < 0 ? 0 : restantes;
    return restantes <= 0;
  }

  /// Detiene el reloj y conserva el tiempo restante.
  void pausar(DateTime ahora) {
    sincronizar(ahora);
    _inicioReloj = null;
  }

  /// Descarta la sesión en curso y vuelve a la fase de trabajo completa.
  void cancelar() {
    _inicioReloj = null;
    _inicioSesion = null;
    _tareaSesion = null;
    fase = FasePomodoro.trabajo;
    segundosRestantes = duracionFase;
  }

  /// Cierra la fase actual y pasa a la siguiente.
  /// Devuelve la sesión terminada solo cuando la fase cerrada era de trabajo.
  SesionCompletada? finalizarFase() {
    _inicioReloj = null;
    SesionCompletada? sesion;

    if (fase == FasePomodoro.trabajo) {
      final inicio = _inicioSesion;
      final tarea = _tareaSesion;
      if (inicio != null && tarea != null) {
        sesion = SesionCompletada(
          tareaId: tarea,
          inicio: inicio,
          minutos: minutosTrabajo,
        );
      }
      fase = FasePomodoro.descanso;
    } else {
      fase = FasePomodoro.trabajo;
    }

    _inicioSesion = null;
    _tareaSesion = null;
    segundosRestantes = duracionFase;
    return sesion;
  }
}
