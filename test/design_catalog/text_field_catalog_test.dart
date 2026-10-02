@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalog.dart';

Widget _controlled(String text, Widget Function(TextEditingController) build) {
  final controller = TextEditingController(text: text);
  return build(controller);
}

void main() {
  catalogCard(
    'TextField',
    scenes: [
      CatalogScene(
        'TextFormField · rest, filled, a 1px room.edge border',
        (_) => const TextField(
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://your-server:7878',
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'TextFormField(autofocus: true) · focused, a 1.5px room.focus border',
        (_) => _controlled(
          'https://radarr.lan:7878',
          (controller) => TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Server URL'),
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'TextFormField(errorText:) · a 1.5px amber border at rest, the '
        'message in body-small in the same tone under the field',
        (_) => _controlled(
          'radarr.lan:7878',
          (controller) => TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              errorText: 'Include http:// or https://',
            ),
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'TextFormField(obscureText: true) · the API-key field\'s shape: '
        'reveal and copy in the suffix, the credential path as a helper',
        (_) => _controlled(
          'a1b2c3d4e5f6',
          (controller) => TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: 'Enter your API key',
              helperText: 'Radarr → Settings → General → Security',
              helperMaxLines: 2,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility_rounded),
                    onPressed: () {},
                    tooltip: 'Show API key',
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {},
                    tooltip: 'Copy API key',
                  ),
                ],
              ),
            ),
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'TextField(enabled: false) · disabled, with a value',
        (_) => _controlled(
          'https://radarr.lan:7878',
          (controller) => TextField(
            controller: controller,
            enabled: false,
            decoration: const InputDecoration(labelText: 'Server URL'),
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'A long label, value and helper · on a 280pt field: the value scrolls, '
        'the helper wraps to its two lines',
        (_) => _controlled(
          'https://radarr.with-a-very-long-hostname.home.arpa:7878/radarr',
          (controller) => TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Server URL including the port and any base path',
              helperText:
                  'Radarr → Settings → General → Host: the address you open '
                  'in a browser, without a trailing slash',
              helperMaxLines: 2,
            ),
          ),
        ),
        width: 280,
      ),
      CatalogScene(
        'Text at 200% · rest with a hint, filled, and with an error: the '
        'label, the value, the message and the field at twice the reading '
        'size',
        (_) => Column(
          children: [
            const TextField(
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://your-server:7878',
              ),
            ),
            const SizedBox(height: 16),
            _controlled(
              'radarr.lan:7878',
              (controller) => TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  errorText: 'Include http:// or https://',
                ),
              ),
            ),
          ],
        ),
        width: 360,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Focused and in error · autofocus with errorText, on the desktop where '
        'the keyboard holds focus: the amber border at 1.5px',
        (_) => _controlled(
          'radarr.lan:7878',
          (controller) => TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              errorText: 'Include http:// or https://',
            ),
          ),
        ),
        width: 360,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
