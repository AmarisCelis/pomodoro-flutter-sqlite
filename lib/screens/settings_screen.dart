import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Decisión del usuario cuando los tiempos salen del rango recomendado.
enum _Decision { cancelar, ajustar, continuar }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Claves de SharedPreferences (minutos).
  static const String claveTrabajo = 'minutos_trabajo';
  static const String claveDescanso = 'minutos_descanso';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _trabajoCtrl = TextEditingController();
  final _descansoCtrl = TextEditingController();

  @override
  void dispose() {
    _trabajoCtrl.dispose();
    _descansoCtrl.dispose();
    super.dispose();
  }

 // String? _validar(String? valor) {
  //  if (valor == null || valor.trim().isEmpty) {
  //    return 'Este campo es obligatorio';
 //   }
 //   if ((int.tryParse(valor.trim()) ?? 0) <= 0) {
 //     return 'Debe ser mayor a 0';
 //   }
 //   return null;
 // }

  /// Rango recomendado de un Pomodoro (minutos). Fuera de él se pide confirmación.
  static const int minTrabajoRecomendado = 15;
  static const int maxTrabajoRecomendado = 60;
  static const int minDescansoRecomendado = 3;
  static const int maxDescansoRecomendado = 30;

  /// Límites absolutos: evitan valores como 0 o 999 que no tienen sentido.
  static const int minAbsoluto = 1;
  static const int maxAbsoluto = 120;

  String? _validarMinutos(String? valor) {
    if (valor == null || valor.trim().isEmpty) return 'Requerido';
    final min = int.tryParse(valor.trim()) ?? 0;
    if (min < minAbsoluto || min > maxAbsoluto) {
      return 'Debe ser entre $minAbsoluto y $maxAbsoluto min';
    }
    return null;
  }

  bool _fueraDeRango(int valor, int min, int max) => valor < min || valor > max;

  int _ajustar(int valor, int min, int max) =>
      valor < min ? min : (valor > max ? max : valor);

  /// Muestra el aviso de tiempos fuera de lo recomendado y devuelve la decisión.
  Future<_Decision?> _confirmarFueraDeRango(int trabajo, int descanso) {
    final detalle = <String>[
      if (_fueraDeRango(trabajo, minTrabajoRecomendado, maxTrabajoRecomendado))
        'Trabajo: $trabajo min (recomendado de $minTrabajoRecomendado a $maxTrabajoRecomendado)',
      if (_fueraDeRango(descanso, minDescansoRecomendado, maxDescansoRecomendado))
        'Descanso: $descanso min (recomendado de $minDescansoRecomendado a $maxDescansoRecomendado)',
    ];
    return showDialog<_Decision>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fuera del rango recomendado'),
        content: Text(
          '${detalle.join('\n')}\n\n'
          '¿Quieres continuar con estos tiempos o usar el rango recomendado?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _Decision.cancelar),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _Decision.ajustar),
            child: const Text('Usar rango recomendado'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _Decision.continuar),
            child: const Text('Continuar de todos modos'),
          ),
        ],
      ),
    );
  }

//

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    var trabajo = int.parse(_trabajoCtrl.text.trim());
    var descanso = int.parse(_descansoCtrl.text.trim());

    final fueraDeRango =
        _fueraDeRango(trabajo, minTrabajoRecomendado, maxTrabajoRecomendado) ||
            _fueraDeRango(descanso, minDescansoRecomendado, maxDescansoRecomendado);
    if (fueraDeRango) {
      final decision = await _confirmarFueraDeRango(trabajo, descanso);
      if (decision == null || decision == _Decision.cancelar) return;
      if (decision == _Decision.ajustar) {
        trabajo = _ajustar(trabajo, minTrabajoRecomendado, maxTrabajoRecomendado);
        descanso = _ajustar(descanso, minDescansoRecomendado, maxDescansoRecomendado);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsScreen.claveTrabajo, trabajo);
    await prefs.setInt(SettingsScreen.claveDescanso, descanso);
    debugPrint('Guardado -> trabajo: $trabajo min, descanso: $descanso min');

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void initState() {
    super.initState();
    _cargarValoresActuales();
  }

  Future<void> _cargarValoresActuales() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _trabajoCtrl.text = (prefs.getInt(SettingsScreen.claveTrabajo) ?? 25).toString();
    _descansoCtrl.text = (prefs.getInt(SettingsScreen.claveDescanso) ?? 5).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Tiempos'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _trabajoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Minutos de Trabajo',
                    helperText: 'Recomendado: 15 a 60 min',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validarMinutos,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descansoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Minutos de Descanso',
                    helperText: 'Recomendado: 3 a 30 min',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validarMinutos,
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _guardar,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
