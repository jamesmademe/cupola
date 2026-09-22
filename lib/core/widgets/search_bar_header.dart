import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/features/shell/domain/screen_search.dart';

/// A reusable, always-visible search bar widget for the top of screens.
///
/// Provides debounced text input, clear button, and Material Design 3 styling.
/// Uses the M3 SearchBar widget with proper color tokens.
class SearchBarHeader extends StatefulWidget {
  /// Callback when the search query changes (debounced).
  final ValueChanged<String> onQueryChanged;

  /// Placeholder text for the search bar.
  final String hintText;

  /// Initial query value.
  final String? initialQuery;

  /// Debounce duration for search input.
  final Duration debounceDuration;

  /// Whether to autofocus the search field
  final bool autofocus;

  /// Accent for the leading search glyph.
  ///
  /// Defaults to the app's primary. It used to be hard-coded to the Seerr
  /// indigo, which left an indigo magnifier sitting on the amber Radarr page and
  /// the pink Lidarr one — the per-service accent is part of the identity, so
  /// every screen passes its own.
  final Color? accent;

  const SearchBarHeader({
    super.key,
    required this.onQueryChanged,
    this.hintText = 'Search...',
    this.initialQuery,
    this.debounceDuration = const Duration(milliseconds: 400),
    this.autofocus = false,
    this.accent,
  });

  @override
  State<SearchBarHeader> createState() => _SearchBarHeaderState();
}

class _SearchBarHeaderState extends State<SearchBarHeader> {
  late final TextEditingController _controller;

  /// Held by the field so the window's `⌘F` has something to focus.
  ///
  /// Owned here rather than passed in by every caller: "search this screen"
  /// means this field, and there are twenty-odd screens whose only search field
  /// is this widget. See [ScreenSearchTarget] for why the registry is explicit
  /// rather than a walk of the tree.
  late final FocusNode _focusNode;
  Timer? _debounceTimer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode(debugLabel: 'screen search');
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      widget.onQueryChanged(_controller.text.trim());
    });
  }

  void _clearQuery() {
    _controller.clear();
    widget.onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // The magnifier is the accent carrying ink, so it is measured, not painted.
    // Six callers hand this a raw service accent and the field it sits in is
    // `surfaceContainer` — white on the light theme — where seven of the
    // seventeen accents are under 3:1 and Lidarr's pink is under 2:1. `onTint`
    // with no tint measures the glyph against that exact ground and walks the
    // hue until it clears, so a Radarr page still gets an amber magnifier, just
    // one that survives daylight. `tintAlpha: 0` because the field has an
    // opaque fill, not a wash of its own accent.
    final glyph = ServiceTheme.onTint(
      widget.accent ?? colorScheme.primary,
      surface: colorScheme.surfaceContainer,
      tintAlpha: 0,
    );

    final field = Semantics(
      label: 'Search',
      hint: 'Type ${widget.hintText}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SearchBar(
          controller: _controller,
          focusNode: _focusNode,
          hintText: widget.hintText,
          autoFocus: widget.autofocus,
          leading: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: Icon(Icons.search_rounded, color: glyph),
          ),
          trailing: [
            if (_hasText)
              Semantics(
                button: true,
                label: 'Clear search',
                hint: 'Remove the current search query',
                onTap: _clearQuery,
                child: ExcludeSemantics(
                  child: IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: _clearQuery,
                    tooltip: 'Clear search',
                  ),
                ),
              ),
          ],
          elevation: WidgetStateProperty.all(0),
          backgroundColor: WidgetStateProperty.all(
            colorScheme.surfaceContainer,
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusXl,
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          constraints: const BoxConstraints(minHeight: 52),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
        ),
      ),
    );

    // Only a desktop window has a `⌘F`, so only a desktop window pays for the
    // registration — and a phone build keeps this widget free of any provider
    // dependency at all.
    if (!AppBreakpoints.isDesktopShell(context)) return field;
    return ScreenSearchTarget(focusNode: _focusNode, child: field);
  }
}
