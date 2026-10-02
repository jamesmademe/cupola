@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_tile.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

Torrent _torrent(
  String name,
  TorrentState parsed,
  String state, {
  required double progress,
  int size = 8 * _gb,
  int dlSpeed = 0,
  int upSpeed = 0,
  int eta = 8640000,
}) => Torrent(
  hash: name,
  name: name,
  size: size,
  progress: progress,
  state: state,
  parsedState: parsed,
  dlSpeed: dlSpeed,
  upSpeed: upSpeed,
  eta: eta,
  category: 'movies',
  tracker: '',
  tags: const [],
  ratio: 0.4,
  addedOn: 0,
  completed: 0,
  leechers: 3,
  seeders: 12,
);

Widget _column(List<Widget> rows) =>
    Column(mainAxisSize: MainAxisSize.min, children: rows);

void _noop() {}

void main() {
  catalogCard(
    'DownloadQueueTile',
    width: 768,
    scenes: [
      CatalogScene(
        'TorrentTile (qBittorrent) · downloading, stalled, paused, queued, '
        'seeding · blue, amber, neutral, neutral, green; no bar when queued or '
        'complete',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.1080p.BluRay.x264-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.63,
              size: 9 * _gb,
              dlSpeed: 25 * _mb,
              upSpeed: 1200 * 1024,
              eta: 720,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.2160p.Restored.BluRay.x265-GROUP',
              TorrentState.stalled,
              'stalledDL',
              progress: 0.41,
              size: 22 * _gb,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'The.Cabinet.of.Dr.Caligari.1920.720p.BluRay.x264-GROUP',
              TorrentState.paused,
              'pausedDL',
              progress: 0.22,
              size: 4 * _gb,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Sherlock.Jr.1924.1080p.BluRay.x264-GROUP',
              TorrentState.queuedDl,
              'queuedDL',
              progress: 0,
              size: 6 * _gb,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.Score.FLAC-GROUP',
              TorrentState.seeding,
              'uploading',
              progress: 1,
              size: 1300 * _mb,
              upSpeed: 3400 * 1024,
              eta: 7800,
            ),
            onTap: _noop,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'TorrentTile · a long wait · `2 h 10 min` and `1 d 5 h` left beside a '
        'long name at 390 · the unit stays with its figure, and the name is '
        'what ellipsises',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.2160p.Restored.BluRay.REMUX.x265-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.12,
              size: 48 * _gb,
              dlSpeed: 6 * _mb,
              eta: 7800,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'The.Cabinet.of.Dr.Caligari.1920.2160p.UHD.BluRay.REMUX-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.03,
              size: 61 * _gb,
              dlSpeed: 700 * 1024,
              eta: 104400,
            ),
            onTap: _noop,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'TorrentTile · error draws no bar; fetching metadata and checking '
        'read as in progress',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.1080p.BluRay.x264-GROUP',
              TorrentState.error,
              'error',
              progress: 0.08,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Sherlock.Jr.1924.720p.BluRay.x264-GROUP',
              TorrentState.metaDownloading,
              'metaDL',
              progress: 0,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.2160p.Restored.BluRay.x265-GROUP',
              TorrentState.checking,
              'checkingDL',
              progress: 0.87,
            ),
            onTap: _noop,
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'Selected · a lamp wash at 8% with a 40% lamp border, after a '
        'long-press starts selection · the bar is the blue tone, in progress',
        (_) => TorrentTile(
          torrent: _torrent(
            'Nosferatu.1922.1080p.BluRay.x264-GROUP',
            TorrentState.downloading,
            'downloading',
            progress: 0.63,
            dlSpeed: 25 * _mb,
            eta: 720,
          ),
          selected: true,
          onTap: _noop,
          onLongPress: _noop,
        ),
        width: 390,
      ),
      CatalogScene(
        'Stale (sampleAge set) · the time left becomes the sample age and the '
        'bar drains to neutral at its last position',
        (_) => DownloadQueueTile(
          title: 'Nosferatu.1922.1080p.BluRay.x264-GROUP',
          subtitle: '9.0\u00A0GB · 12\u00A0min',
          progress: 0.63,
          percentage: 63,
          accent: ServiceKey.qbittorrent.accent,
          statusLabel: 'Downloading',
          statusTone: StatusTone.info,
          metrics: const [
            DownloadQueueMetric(label: '↓ 25.0 MB/s', accented: true),
          ],
          sampleAge: const Duration(minutes: 6),
          onTap: _noop,
        ),
        width: 390,
      ),
      CatalogScene(
        'Usenet rows (SABnzbd, NZBGet) · no chip, no metrics; the state heads '
        'the second line and DownloadQueueActionsMenu trails the first',
        (_) => _column([
          DownloadQueueTile(
            title: 'Metropolis.1927.1080p.BluRay.x264-GROUP',
            subtitle: 'Downloading · 0:12:00 · 1.2 GB left of 3.4 GB',
            progress: 0.65,
            percentage: 65,
            accent: ServiceKey.sabnzbd.accent,
            actions: DownloadQueueActionsMenu(paused: false, onCommand: (_) {}),
          ),
          DownloadQueueTile(
            title: 'Sherlock.Jr.1924.720p.BluRay.x264-GROUP',
            subtitle: 'Paused · movies · 2.1 GB left',
            progress: 0.18,
            percentage: 18,
            accent: ServiceKey.nzbget.accent,
            actions: DownloadQueueActionsMenu(paused: true, onCommand: (_) {}),
          ),
          DownloadQueueTile(
            title: 'The.Cabinet.of.Dr.Caligari.1920.1080p.BluRay.x264-GROUP',
            subtitle: 'Queued · movies · progress unknown',
            progress: null,
            percentage: null,
            accent: ServiceKey.nzbget.accent,
            actions: DownloadQueueActionsMenu(paused: false, onCommand: (_) {}),
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'Long name and long state label · the name takes the free width, '
        'the chip keeps its own up to a 40% cap, and both ellipsise before '
        'anything overflows',
        (_) => DownloadQueueTile(
          title:
              'The.Cabinet.of.Dr.Caligari.1920.Restored.Tinted.1080p.BluRay.'
              'x264-GROUP',
          subtitle: '6.4\u00A0GB · 3\u00A0h 10\u00A0min',
          progress: 0.04,
          percentage: 4,
          accent: ServiceKey.transmission.accent,
          statusLabel: 'Tracker unreachable',
          statusTone: StatusTone.warning,
          onTap: _noop,
        ),
        width: 390,
      ),
      CatalogScene(
        'TorrentTile on the desktop · the same plate in the wider queue column',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.1080p.BluRay.x264-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.63,
              size: 9 * _gb,
              dlSpeed: 25 * _mb,
              upSpeed: 1200 * 1024,
              eta: 720,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.2160p.Restored.BluRay.x265-GROUP',
              TorrentState.stalled,
              'stalledDL',
              progress: 0.41,
              size: 22 * _gb,
            ),
            onTap: _noop,
          ),
        ]),
        width: 720,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · a downloading and a stalled TorrentTile, a selected '
        'one, a Usenet row and a long state label, at twice the reading size',
        (_) => _column([
          TorrentTile(
            torrent: _torrent(
              'Nosferatu.1922.1080p.BluRay.x264-GROUP',
              TorrentState.downloading,
              'downloading',
              progress: 0.63,
              size: 9 * _gb,
              dlSpeed: 25 * _mb,
              upSpeed: 1200 * 1024,
              eta: 720,
            ),
            onTap: _noop,
          ),
          TorrentTile(
            torrent: _torrent(
              'Metropolis.1927.2160p.Restored.BluRay.x265-GROUP',
              TorrentState.stalled,
              'stalledDL',
              progress: 0.41,
              size: 22 * _gb,
            ),
            selected: true,
            onTap: _noop,
            onLongPress: _noop,
          ),
          DownloadQueueTile(
            title: 'Metropolis.1927.1080p.BluRay.x264-GROUP',
            subtitle: 'Downloading · 0:12:00 · 1.2 GB left of 3.4 GB',
            progress: 0.65,
            percentage: 65,
            accent: ServiceKey.sabnzbd.accent,
            actions: DownloadQueueActionsMenu(paused: false, onCommand: (_) {}),
          ),
          DownloadQueueTile(
            title:
                'The.Cabinet.of.Dr.Caligari.1920.Restored.Tinted.1080p.BluRay.'
                'x264-GROUP',
            subtitle: '6.4\u00A0GB · 3\u00A0h 10\u00A0min',
            progress: 0.04,
            percentage: 4,
            accent: ServiceKey.transmission.accent,
            statusLabel: 'Tracker unreachable',
            statusTone: StatusTone.warning,
            onTap: _noop,
          ),
        ]),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
