// lib/data/audio/player_strings.dart
import 'package:audio_service/audio_service.dart';

/// Provider for localized notification and playback media controls.
class PlayerStrings {
  final String favorite;
  final String unfavorite;
  final String shuffle;
  final String repeat;

  const PlayerStrings({
    this.favorite = 'Favorite',
    this.unfavorite = 'Unfavorite',
    this.shuffle = 'Shuffle',
    this.repeat = 'Repeat',
  });

  static PlayerStrings forLocale(String? langCode) {
    if (langCode == 'ar') {
      return const PlayerStrings(
        favorite: 'المفضلة',
        unfavorite: 'إزالة من المفضلة',
        shuffle: 'خلط',
        repeat: 'تكرار',
      );
    } else if (langCode == 'es') {
      return const PlayerStrings(
        favorite: 'Favorito',
        unfavorite: 'Eliminar de favoritos',
        shuffle: 'Aleatorio',
        repeat: 'Repetir',
      );
    }
    return const PlayerStrings();
  }

  MediaControl buildControlFavorite() => MediaControl.custom(
        androidIcon: 'drawable/ic_favorite',
        label: unfavorite,
        name: 'toggleFavorite',
      );

  MediaControl buildControlUnfavorite() => MediaControl.custom(
        androidIcon: 'drawable/ic_favorite_border',
        label: favorite,
        name: 'toggleFavorite',
      );

  MediaControl buildControlShuffleOn() => MediaControl.custom(
        androidIcon: 'drawable/ic_shuffle_on',
        label: shuffle,
        name: 'toggleShuffle',
      );

  MediaControl buildControlShuffleOff() => MediaControl.custom(
        androidIcon: 'drawable/ic_shuffle',
        label: shuffle,
        name: 'toggleShuffle',
      );

  MediaControl buildControlRepeatOne() => MediaControl.custom(
        androidIcon: 'drawable/ic_repeat_one',
        label: repeat,
        name: 'cycleRepeat',
      );

  MediaControl buildControlRepeatAll() => MediaControl.custom(
        androidIcon: 'drawable/ic_repeat_all',
        label: repeat,
        name: 'cycleRepeat',
      );

  MediaControl buildControlRepeatOff() => MediaControl.custom(
        androidIcon: 'drawable/ic_repeat',
        label: repeat,
        name: 'cycleRepeat',
      );
}
