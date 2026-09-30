import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// qBittorrent's accent as ink on the header it sits in, walked against that
/// header's surface — the lit band on a desktop window, the plain surface on a
/// phone. The raw accent is measured nowhere.
Color qbittorrentBarInk(BuildContext context) => ServiceTheme.onTint(
  ServiceKey.qbittorrent.accent,
  surface: ServiceBandSurface.of(context),
  tintAlpha: 0,
);

class AddTorrentButton extends ConsumerWidget {
  const AddTorrentButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(Icons.add_rounded, color: qbittorrentBarInk(context)),
      onPressed: () => _showAddTorrentSheet(context, ref),
      tooltip: 'Add torrent',
    );
  }

  void _showAddTorrentSheet(BuildContext context, WidgetRef ref) {
    final urlController = TextEditingController();
    final categoryController = TextEditingController();
    final savePathController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final pickedFilesNotifier = ValueNotifier<List<PlatformFile>>([]);

    AppBottomSheet.show<void>(
      context: context,
      title: 'Add torrent',
      icon: Icons.add_link_rounded,
      accent: ServiceKey.qbittorrent.accent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          return Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'Magnet / URL',
                    hintText: 'magnet:?xt=urn:btih:...',
                  ),
                  onChanged: (_) => setModalState(() {}),
                  validator: (v) {
                    if (pickedFilesNotifier.value.isNotEmpty) return null;
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Required';
                    final isMagnet = value.toLowerCase().startsWith('magnet:');
                    final isHttp =
                        value.toLowerCase().startsWith('http://') ||
                        value.toLowerCase().startsWith('https://');
                    if (!isMagnet && !isHttp) {
                      return 'Enter a magnet link or an http(s) URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                ValueListenableBuilder<List<PlatformFile>>(
                  valueListenable: pickedFilesNotifier,
                  builder: (context, files, _) {
                    if (files.isEmpty) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.attach_file_rounded, size: 18),
                          label: const Text('Pick .torrent files'),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              allowMultiple: true,
                              type: FileType.custom,
                              allowedExtensions: const ['torrent'],
                              withData: true,
                            );
                            if (result != null && result.files.isNotEmpty) {
                              pickedFilesNotifier.value = result.files;
                              setModalState(() {});
                            }
                          },
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...files.map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.description_rounded, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'Remove',
                                  onPressed: () {
                                    pickedFilesNotifier.value = files
                                        .where((x) => x != f)
                                        .toList(growable: false);
                                    setModalState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add more files'),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              allowMultiple: true,
                              type: FileType.custom,
                              allowedExtensions: const ['torrent'],
                              withData: true,
                            );
                            if (result != null && result.files.isNotEmpty) {
                              pickedFilesNotifier.value = [
                                ...files,
                                ...result.files,
                              ];
                              setModalState(() {});
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: savePathController,
                  decoration: const InputDecoration(
                    labelText: 'Save path (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  style: FilledButton.styleFrom(
                    // The ink button, the theme's. The label's weight lives
                    // here, not on the Text: a `labelLarge` style on the Text
                    // carries the theme's own text colour and overrides the
                    // button's foreground.
                    textStyle: Theme.of(
                      ctx2,
                    ).textTheme.labelLarge!.weight(FontWeight.w600),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final service = ref.read(qbittorrentServiceProvider);
                      final files = pickedFilesNotifier.value;
                      final category = categoryController.text.trim().isEmpty
                          ? null
                          : categoryController.text.trim();
                      final savePath = savePathController.text.trim().isEmpty
                          ? null
                          : savePathController.text.trim();

                      if (files.isNotEmpty) {
                        final multipart = <MultipartFile>[];
                        for (final f in files) {
                          if (f.bytes != null) {
                            multipart.add(
                              MultipartFile.fromBytes(
                                f.bytes!,
                                filename: f.name,
                              ),
                            );
                          }
                        }
                        await service.addTorrentFiles(
                          multipart,
                          category: category,
                          savePath: savePath,
                        );
                      } else {
                        await service.addTorrentUrl(
                          urlController.text.trim(),
                          category: category,
                          savePath: savePath,
                        );
                      }
                      ref.invalidate(torrentsProvider);
                      ref.invalidate(allTorrentsProvider);
                      if (ctx2.mounted) Navigator.of(ctx2).pop();
                      if (context.mounted) {
                        SnackBarHelper.success(
                          context,
                          'Torrent added successfully',
                        );
                      }
                    } catch (e) {
                      if (ctx2.mounted) {
                        SnackBarHelper.error(
                          ctx2,
                          "Couldn't add the torrent.",
                          detail: e,
                        );
                      }
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 18),
                      const SizedBox(width: 8),
                      const Text('Add torrent'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
