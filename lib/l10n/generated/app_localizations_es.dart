// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Pulsr Música';

  @override
  String get songs => 'Canciones';

  @override
  String get albums => 'Álbumes';

  @override
  String get artists => 'Artistas';

  @override
  String get playlists => 'Listas de reproducción';

  @override
  String get genres => 'Géneros';

  @override
  String get folders => 'Carpetas';

  @override
  String get favorites => 'Favoritos';

  @override
  String get settings => 'Ajustes';

  @override
  String get search => 'Buscar';

  @override
  String get nowPlaying => 'Reproduciendo';

  @override
  String get queue => 'Cola de reproducción';

  @override
  String get lyrics => 'Letras';

  @override
  String get equalizer => 'Ecualizador';

  @override
  String get sleepTimer => 'Temporizador';

  @override
  String get rescanLibrary => 'Escanear biblioteca';

  @override
  String get play => 'Reproducir';

  @override
  String get pause => 'Pausar';

  @override
  String get next => 'Siguiente';

  @override
  String get previous => 'Anterior';

  @override
  String get shuffle => 'Aleatorio';

  @override
  String get repeat => 'Repetir';

  @override
  String get share => 'Compartir';

  @override
  String get tagEditor => 'Editar etiquetas';

  @override
  String get setRingtone => 'Establecer como tono';

  @override
  String get delete => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get close => 'Cerrar';

  @override
  String get noSongsFound => 'No se encontraron canciones';

  @override
  String get noSongsSubtitle =>
      'Escanea el almacenamiento local para encontrar archivos de música.';

  @override
  String get permissionRequired => 'Permiso requerido';

  @override
  String get audioAccessRequired =>
      'Se requiere acceso de audio para mostrar tu música.';

  @override
  String get openSettings => 'Abrir ajustes';

  @override
  String get privacyGuarantee =>
      '100% Sin conexión • Cero telemetría • Almacenamiento local';
}
