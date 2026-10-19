import 'package:flutter/material.dart';
import '../data/database_helper.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _db = DatabaseHelper.instance;
  bool _cargando = true;

  int _minutosTotales = 0;
  int _rachaDias = 0;
  int _sesionesHoy = 0;

  Map<String, int> _minutosPorTarea = {};
  Map<String, List<Map<String, dynamic>>> _historialPorDia = {};
  
  DateTime _fechaSeleccionada = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _cargarEstadisticas();
  }

  Future<void> _cargarEstadisticas() async {
    try {
      final db = await _db.database; 
      
      final sesiones = await db.rawQuery('''
        SELECT s.*, t.titulo as tarea_titulo 
        FROM sesiones s 
        LEFT JOIN tareas t ON s.tarea_id = t.id 
        WHERE s.estado = 'completada' 
        ORDER BY s.fecha_inicio DESC
      ''');

      int minutos = 0;
      Set<String> diasTrabajados = {};
      final String fechaHoy = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      int hoy = 0;

      Map<String, int> minsTarea = {};
      Map<String, List<Map<String, dynamic>>> histDia = {};

      for (var s in sesiones) {
        int duracion = (s['duracion_minutos'] as int? ?? 0);
        minutos += duracion;
        
        final fecha = s['fecha_inicio'] as String;
        final dia = fecha.substring(0, 10);
        diasTrabajados.add(dia);

        if (dia == fechaHoy) hoy++;

        String tituloTarea = s['tarea_titulo'] as String? ?? 'Tarea eliminada';
        minsTarea[tituloTarea] = (minsTarea[tituloTarea] ?? 0) + duracion;

        if (!histDia.containsKey(dia)) {
          histDia[dia] = [];
        }
        histDia[dia]!.add(s);
      }

      int racha = 0;
      DateTime fechaCheck = DateTime.now().toUtc();
      
      if (!diasTrabajados.contains(fechaHoy)) {
        fechaCheck = fechaCheck.subtract(const Duration(days: 1));
      }

      while (diasTrabajados.contains(fechaCheck.toIso8601String().substring(0, 10))) {
        racha++;
        fechaCheck = fechaCheck.subtract(const Duration(days: 1));
      }

      if (!mounted) return;
      setState(() {
        _minutosTotales = minutos;
        _rachaDias = racha;
        _sesionesHoy = hoy;
        _minutosPorTarea = minsTarea;
        _historialPorDia = histDia;
        _cargando = false;
      });
    } catch (e) {
      debugPrint("Error cargando estadísticas: $e");
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarDetalleTarea(String nombreTarea) {
    Map<String, int> desglosePorDia = {};

    _historialPorDia.forEach((dia, sesiones) {
      for (var s in sesiones) {
        if ((s['tarea_titulo'] as String? ?? 'Tarea eliminada') == nombreTarea) {
          int duracion = s['duracion_minutos'] as int? ?? 0;
          desglosePorDia[dia] = (desglosePorDia[dia] ?? 0) + duracion;
        }
      }
    });

    // Estructura limpia y tipada explícitamente para evitar conflictos en Dart
    Map<String, Map<String, List<Map<String, dynamic>>>> datosAgrupados = {};
    List<String> nombresMeses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

    desglosePorDia.forEach((fecha, minutos) {
      String anio = fecha.substring(0, 4);
      int mesNum = int.parse(fecha.substring(5, 7));
      String dia = fecha.substring(8, 10);
      String nombreMes = nombresMeses[mesNum - 1];

      datosAgrupados.putIfAbsent(anio, () => {});
      datosAgrupados[anio]!.putIfAbsent(nombreMes, () => []);
      datosAgrupados[anio]![nombreMes]!.add({'dia': dia, 'minutos': minutos});
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(nombreTarea, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: datosAgrupados.isEmpty 
          ? const Text('No hay datos.')
          : SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: datosAgrupados.entries.map((entryAnio) {
                  return ExpansionTile(
                    initiallyExpanded: true,
                    title: Text('Año ${entryAnio.key}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    children: entryAnio.value.entries.map((entryMes) {
                      return ExpansionTile(
                        initiallyExpanded: true,
                        title: Text(entryMes.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                        children: entryMes.value.map((datoDia) {
                          return ListTile(
                            contentPadding: const EdgeInsets.only(left: 32, right: 16),
                            leading: const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                            title: Text('Día ${datoDia['dia']}'),
                            trailing: Text('${datoDia['minutos']} min', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          )
        ],
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final DateTime? seleccion = await showDatePicker(
      context: context,
      initialDate: _fechaSeleccionada.toLocal(), 
      firstDate: DateTime(2024), 
      lastDate: DateTime.now().add(const Duration(days: 1)), 
      helpText: 'Selecciona una fecha',
    );
    if (seleccion != null) {
      setState(() {
        _fechaSeleccionada = DateTime.utc(seleccion.year, seleccion.month, seleccion.day);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String fechaStr = _fechaSeleccionada.toIso8601String().substring(0, 10);
    List<Map<String, dynamic>> sesionesDelDia = _historialPorDia[fechaStr] ?? [];
    int minsDelDia = sesionesDelDia.fold(0, (sum, item) => sum + (item['duracion_minutos'] as int? ?? 0));

    var tareasOrdenadas = _minutosPorTarea.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    var topTareas = tareasOrdenadas.take(10).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas Detalladas'), centerTitle: true),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(child: _MiniCard(titulo: 'Hoy', valor: '$_sesionesHoy', icono: Icons.today, color: Colors.blue)),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniCard(titulo: 'Minutos', valor: '$_minutosTotales', icono: Icons.timer, color: Colors.green)),
                    const SizedBox(width: 8),
                    Expanded(child: _MiniCard(titulo: 'Racha', valor: '$_rachaDias', icono: Icons.local_fire_department, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 32),

                Text('Top 10 Tareas más productivas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (topTareas.isEmpty)
                  const Text('Aún no hay tareas completadas.', style: TextStyle(color: Colors.grey)),
                ...topTareas.map((entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                  title: Text(entry.key),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${entry.value} min', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  onTap: () => _mostrarDetalleTarea(entry.key),
                )),
                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Bitácora diaria', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _seleccionarFecha,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(fechaStr),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (sesionesDelDia.isEmpty)
                  const Text('No registraste actividad en esta fecha.', style: TextStyle(color: Colors.grey))
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text('Total del día: $minsDelDia min', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ),
                          const Divider(),
                          ...sesionesDelDia.map((sesion) => ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(sesion['tarea_titulo'] as String? ?? 'Tarea eliminada'),
                            trailing: Text('${sesion['duracion_minutos']} min'),
                          )).toList(),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  const _MiniCard({required this.titulo, required this.valor, required this.icono, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icono, color: color, size: 28),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(valor, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
            ),
            Text(titulo, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}