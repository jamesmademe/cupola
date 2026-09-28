@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'AppErrorState',
    scenes: [
      CatalogScene(
        'AppErrorState(serviceName:, onRetry:) · cold open, nothing retained',
        (_) => AppErrorState(
          serviceName: 'Radarr',
          error: Exception(
            'DioException [connection timeout]: The request connection took '
            'longer than 0:00:15.000000 and it was aborted.',
          ),
          onRetry: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'AppErrorState.compact() · no serviceName, no onRetry',
        (_) =>
            const AppErrorState.compact(error: 'Exception: Connection refused'),
        width: 280,
      ),
      CatalogScene(
        'InlineErrorRetry · one section of a page failed, self-sizing',
        (_) => InlineErrorRetry(
          message: 'Failed to load virtual machines',
          onRetry: () {},
        ),
        width: 360,
      ),
      CatalogScene(
        'InlineErrorRetry.fixedHeight · locked to 120px so a carousel row does '
        'not jump between loading, loaded and failed',
        (_) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0x40808080),
              style: BorderStyle.solid,
            ),
          ),
          child: InlineErrorRetry.fixedHeight(
            message: 'Failed to load containers',
            onRetry: () {},
          ),
        ),
        width: 360,
      ),
    ],
  );
}
