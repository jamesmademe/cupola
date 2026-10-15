@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/qr_code_view.dart';

import 'catalog.dart';

/// An invite of one address at home, as the Seerr of a household with no
/// certificate to vouch for and no name.
const _short = 'cupola://invite?v=1&home=http%3A%2F%2F192.168.1.10%3A5055';

/// An invite with both addresses, the certificate each shows, and a name: the
/// longest an operator's own Seerr makes, and the densest code the sheet draws.
const _long =
    'cupola://invite?v=1&home=https%3A%2F%2Fnas.home.arpa%3A5055'
    '&away=https%3A%2F%2Fseerr.example.net'
    '&homePin=a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'
    '&awayPin=0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0'
    '&title=Rossi+Movies';

Widget _qr(String data, {double size = 232}) =>
    QrCodeView(data: data, size: size, semanticLabel: 'QR code of the invite');

void main() {
  catalogCard(
    'QrCodeView',
    width: 880,
    scenes: [
      CatalogScene(
        'QrCodeView · a short payload (33 modules, 5 pixels each) at the '
        'sheet\'s 232 · always black on white, in the dark room too',
        (_) => _qr(_short),
      ),
      CatalogScene(
        'QrCodeView · a long payload (both addresses, both certificates, a '
        'name: 65 modules, 3 pixels each) at 232 · the code centred in its '
        'tile, the spare pixels part of the quiet zone',
        (_) => _qr(_long),
      ),
      CatalogScene(
        'QrCodeView · size 120 · the tile is the side asked for, the module '
        'snaps down to a whole pixel and the rest is quiet zone',
        (_) => _qr(_short, size: 120),
      ),
      CatalogScene(
        'On a desktop window · the same long payload at 232: the tile is the '
        'same size on every platform, and so is its code',
        (_) => _qr(_long),
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · the tile keeps its side while the words around it '
        'double: a scanner reads the tile, not the text',
        (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _qr(_short),
            const SizedBox(height: 12),
            Text(
              'Rossi Movies · nas.home.arpa:5055',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
