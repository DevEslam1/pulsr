part of '../settings_screen.dart';

class _SettingsCategoryItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tintColor;

  const _SettingsCategoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tintColor,
  });
}

class _Category {
  final String id;
  final IconData icon;
  String title = '';
  final GlobalKey key;

  _Category(this.id, this.icon) : key = GlobalKey();
}

class _SearchItem {
  final String categoryId;
  final String category;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> keywords;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Professional-only setting; hidden from Normal-mode search.
  final bool pro;

  _SearchItem({
    this.categoryId = '',
    required this.category,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.keywords,
    this.trailing,
    this.onTap,
    this.pro = false,
  });
}
