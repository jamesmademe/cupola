import 'package:flutter/material.dart';

import 'package:cupola/core/theme.dart';

/// A service's mark in its tile: how a service is recognised wherever it is
/// named with its shape (a service room's identity, a row of Stack), in ink on
/// the room's strong fill, never in the service's colour.
///
/// The tile is [size] square (44 by default, a touch target's side), its
/// corners a third of a gutter rounder than a control's at that size, the mark
/// a little over half of it.
class ServiceMarkTile extends StatelessWidget {
  const ServiceMarkTile({super.key, required this.icon, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: room.fillStrong,
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: room.edge),
        ),
        child: Icon(icon, size: size * 0.55, color: room.ink),
      ),
    );
  }
}
