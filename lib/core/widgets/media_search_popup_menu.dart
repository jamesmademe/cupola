import 'package:flutter/material.dart';

/// A reusable popup menu for media search options.
///
/// Shows options for "Automatic search" and "Interactive search".
/// Used in Series and Music detail screens for season/album search menus.
class MediaSearchPopupMenu extends StatelessWidget {
  /// Callback when "Automatic search" is selected.
  final VoidCallback onAutoSearch;

  /// Callback when "Interactive search" is selected.
  final VoidCallback onInteractiveSearch;

  /// Whether to show a loading indicator instead of the menu.
  final bool isLoading;

  /// Optional custom icon. Defaults to [Icons.search_rounded].
  final IconData icon;

  /// Optional icon size. Defaults to 20.
  final double iconSize;

  /// Optional tooltip. Defaults to "Search options".
  final String tooltip;

  const MediaSearchPopupMenu({
    super.key,
    required this.onAutoSearch,
    required this.onInteractiveSearch,
    this.isLoading = false,
    this.icon = Icons.search_rounded,
    this.iconSize = 20,
    this.tooltip = 'Search options',
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return PopupMenuButton<String>(
      icon: Icon(icon, size: iconSize),
      tooltip: tooltip,
      onSelected: (value) {
        if (value == 'auto') onAutoSearch();
        if (value == 'interactive') onInteractiveSearch();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'auto', child: Text('Automatic search')),
        const PopupMenuItem(
          value: 'interactive',
          child: Text('Interactive search'),
        ),
      ],
    );
  }
}
