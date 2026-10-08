/// Continue watching: what somebody started and did not finish.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/continue_watching.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show bringUnderLens;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';

/// Continue watching: up to three titles started and not finished, on every
/// Jellyfin and Plex, each opening its page.
///
/// Absent when nothing is in progress and every server answered, when its
/// only title is already Featured's first slide, and without a media server
/// (Set up next names Jellyfin). A Jellyfin whose household member nobody
/// chose asks who you are, once.
class HomeContinueWatchingModule extends ConsumerWidget {
  const HomeContinueWatchingModule({super.key});

  static const _title = 'Continue watching';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final services = HomeModule.continueWatching.services
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (services.isEmpty) return const SizedBox.shrink();

    final read = ref.watch(homeResumeProvider);
    final resume = read.value;
    if (resume == null) {
      if (read.hasError) {
        return HomeModuleFrame.silent(
          title: _title,
          coverage: SourceCoverage.merge([
            for (final service in services)
              SourceCoverage.failure(service, read.error),
          ]),
          onRetry: () => ref.invalidate(homeResumeProvider),
        );
      }
      return const HomeModuleFrame.loading(title: _title);
    }

    final coverage = resume.coverage;
    final asking = resume.viewerMissing.isEmpty
        ? null
        : _WhoAreYou(
            instanceId: resume.viewerMissing.first,
            name: resume.viewerMissing.length > 1
                ? null
                : settings.connectionName(resume.viewerMissing.first),
          );
    // Featured already leads with its only title: said once is enough.
    if (asking == null &&
        coverage.failed.isEmpty &&
        resume.rows.length == 1 &&
        _featuredLeadsWith(ref, resume.rows.single)) {
      return const SizedBox.shrink();
    }
    if (resume.rows.isEmpty && asking == null) {
      if (coverage.failed.isEmpty) return const SizedBox.shrink();
      return HomeModuleFrame.silent(
        title: _title,
        coverage: coverage,
        onRetry: () => ref.invalidate(homeResumeProvider),
      );
    }

    final shown = resume.rows
        .take(continueWatchingRowLimit)
        .toList(growable: false);
    final servers = {
      for (final row in shown) row.service.title,
      if (asking != null) ServiceKey.jellyfin.title,
    }.join(' · ');
    final note = coverage.failed.isEmpty
        ? null
        : coverageFailureSentence(coverage);

    return HomeModuleFrame(
      title: _title,
      subtitle: servers,
      semanticLabel: joinSpokenParts([_title, ?note]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) HomeCoverageNote(note: note, coverage: coverage),
          for (final (index, row) in shown.indexed)
            ContinueWatchingRow(
              key: ValueKey('${row.instanceId}/${row.item.id}'),
              row: row,
              divided: index > 0,
            ),
          if (asking != null) ...[
            if (shown.isNotEmpty) const SizedBox(height: AppSpacing.sm),
            asking,
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

/// Whether Featured is on the Home and its first slide is [row].
bool _featuredLeadsWith(WidgetRef ref, ResumeRow row) {
  if (!ref.watch(homeLayoutProvider).shown.contains(HomeModule.featured)) {
    return false;
  }
  final first = ref.watch(featuredProvider).value?.firstOrNull;
  return first is FeaturedResume &&
      first.row.instanceId == row.instanceId &&
      first.row.item.id == row.item.id;
}

/// One title in progress: its picture, its name, the episode, how long is
/// left, over an ink bar.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({
    super.key,
    required this.row,
    this.divided = false,
  });

  final ResumeRow row;

  /// Whether a hairline separates it from the row above.
  final bool divided;

  static const Size thumb = Size(112, 63);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final item = row.item;
    final title = resumeTitle(item);
    final detail = resumeDetail(item);
    final left = resumeLeft(item);
    final server = row.service == ServiceKey.jellyfin
        ? ref.watch(jellyfinClientForProvider(row.instanceId))
        : ref.watch(plexClientForProvider(row.instanceId));
    final image = item.posterPath == null
        ? null
        : server.imageFor(item.posterPath!, width: 360);

    // At a large reading size the words take the slab's width under the
    // picture, rather than a third of it beside.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final picture = ClipRRect(
      borderRadius: AppRadius.borderRadiusSm,
      child: SizedBox.fromSize(
        size: thumb,
        child: image == null
            ? ColoredBox(
                color: room.fillQuiet,
                child: Icon(
                  row.service.icon,
                  size: 20,
                  color: room.inkSecondary,
                ),
              )
            : ContentCard(imageUrl: image.url, httpHeaders: image.headers),
      ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.row.weight(FontWeight.w600).copyWith(color: room.ink),
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        if (left != null)
          Text(
            left,
            maxLines: 1,
            style: AppType.meta.tabular
                .weight(FontWeight.w600)
                .copyWith(color: room.ink),
          ),
        if (item.resumeProgress case final progress?) ...[
          const SizedBox(height: 7),
          // Ink: how far somebody got is not a status.
          HomeRowBar(value: progress, color: room.ink),
        ],
      ],
    );

    Future<void> open() => openResume(context, ref, row);

    return Semantics(
      container: true,
      button: true,
      label: title,
      value: joinSpokenParts([
        spokenFromDotted(detail),
        ?left,
        if (item.resumeProgress case final progress?)
          '${(progress * 100).round()} percent watched',
      ]),
      onTap: open,
      child: InkWell(
        onTap: open,
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: divided
                  ? Border(top: BorderSide(color: room.hair))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: picture),
                        const SizedBox(height: AppSpacing.sm),
                        words,
                      ],
                    )
                  : Row(
                      children: [
                        picture,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: words),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The question a Jellyfin with no household member chosen asks, once:
/// `Which Jellyfin user are you?`, to the connection's form where the picker
/// is.
class _WhoAreYou extends ConsumerWidget {
  const _WhoAreYou({required this.instanceId, required this.name});

  final String instanceId;

  /// What tells the connection apart, while Jellyfin has more than one.
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final jellyfin = [ServiceKey.jellyfin.title, ?name].join(' ');
    final question = 'Which $jellyfin user are you?';
    const line = 'A server key sees every user; pick yours once';
    return Semantics(
      button: true,
      label: question,
      hint: line,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.borderRadiusMd,
        onTap: () => openSettings(
          context,
          ref,
          to: ServiceRoutes.settingsForConnection(
            ServiceKey.jellyfin,
            instanceId,
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(color: room.hair),
          ),
          child: Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: room.inkSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question,
                      style: AppType.row
                          .weight(FontWeight.w600)
                          .copyWith(color: room.ink),
                    ),
                    Text(
                      line,
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: room.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row's page: a movie's or a series' Media page with the connection it is
/// on leading, else the item's own page on its server.
Future<void> openResume(
  BuildContext context,
  WidgetRef ref,
  ResumeRow row,
) async {
  final key = MediaKey.ofStreamItem(row.item);
  if (key != null) {
    await context.openMedia(key, focus: row.instanceId);
    return;
  }
  await bringUnderLens(ref, row.service, row.instanceId);
  if (!context.mounted) return;
  await context.pushMounted(ServiceRoutes.streamItem(row.service, row.item.id));
}
