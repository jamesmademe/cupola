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
        'TextFormField · rest, filled, no border — the fill draws the '
        'boundary',
        (_) => const TextField(
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://your-server:7878',
          ),
        ),
        width: 360,
      ),
      CatalogScene(
        'TextFormField(autofocus: true) · focused, a 2px primary border',
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
        'TextFormField(errorText:) · a 1px error border at rest, the message '
        'in body-small under the field',
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
    ],
  );
}
