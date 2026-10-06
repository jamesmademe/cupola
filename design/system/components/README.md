# Components

One card per widget. Each card is a `README.md` — what the widget is for, its variants, the tokens it
uses, what the caller provides, how it reads to a screen reader, and what not to do with it — and a
catalog of pictures the real widget renders:

```sh
flutter test --tags catalog --run-skipped test/design_catalog
```

writes `build/design_catalog/<Card>/<phone|desktop>.<dark|light>.png` from
`test/design_catalog/<card>_catalog_test.dart`. The pictures are built, not committed. The animated
cards live in [`../motion/`](../motion/).

| Group | Card | Widget |
| --- | --- | --- |
| Actions | [Button](Button/README.md) | `lib/core/theme.dart`, `lib/core/widgets/cross_service_action.dart` |
| Actions | [CrossServiceAction](CrossServiceAction/README.md) | `lib/core/widgets/cross_service_action.dart` |
| Actions | [HeaderActionRow](HeaderActionRow/README.md) | `lib/core/widgets/header_action_row.dart`, `lib/core/widgets/library_detail_actions.dart`, `lib/core/status/media_action.dart` |
| Actions | [ReelCommandButton](ReelCommandButton/README.md) | `lib/core/widgets/reel_command_button.dart`, `lib/core/reel_motion.dart` |
| Navigation | [FloatingBottomNavBar](FloatingBottomNavBar/README.md) | `lib/core/widgets/floating_bottom_nav_bar.dart`, `lib/features/settings/domain/nav_tab.dart`, `lib/features/shell/presentation/shell_screen.dart` |
| Navigation | [SearchBarHeader](SearchBarHeader/README.md) | `lib/core/widgets/search_bar_header.dart` |
| Navigation | [SelectionPills](SelectionPills/README.md) | `lib/core/widgets/selection_pills.dart` |
| Navigation | [ServiceTabBar](ServiceTabBar/README.md) | `lib/core/widgets/service_tab_bar.dart`, `lib/features/services/domain/service_tab.dart` |
| Structure | [SectionHeader](SectionHeader/README.md) | `lib/core/widgets/section_header.dart` |
| Containers | [AppCard](AppCard/README.md) | `lib/core/widgets/app_card.dart` |
| Lists | [ServiceRecordRow](ServiceRecordRow/README.md) | `lib/core/widgets/service_record_row.dart` |
| Metadata | [TagChip](TagChip/README.md) | `lib/core/widgets/tag_chip.dart` |
| Metadata | [MachineName](MachineName/README.md) | `lib/core/widgets/machine_name.dart` |
| Status | [AppErrorState](AppErrorState/README.md) | `lib/core/widgets/app_error_state.dart`, `lib/core/widgets/inline_error_retry.dart`, `lib/core/widgets/brief_failure_line.dart` |
| Status | [CapabilityBanner](CapabilityBanner/README.md) | `lib/core/widgets/capability_banner.dart`, `lib/core/capability/capability_copy.dart` |
| Status | [ConnectionBadge](ConnectionBadge/README.md) | `lib/core/widgets/connection_badge.dart` |
| Status | [NotConfiguredPlaceholder](NotConfiguredPlaceholder/README.md) | `lib/core/widgets/not_configured_placeholder.dart` |
| Status | [ServiceOfflineState](ServiceOfflineState/README.md) | `lib/core/widgets/service_offline_state.dart` |
| Status | [StatusBadge](StatusBadge/README.md) | `lib/core/widgets/status_badge.dart` |
| Readouts | [ServiceKpiPeek](ServiceKpiPeek/README.md) | `lib/core/widgets/service_kpi_peek.dart`, `lib/features/services/presentation/service_kpi_provider.dart` |
| Feedback | [AppEmptyState](AppEmptyState/README.md) | `lib/core/widgets/app_empty_state.dart` |
| Feedback | [FaultBand](FaultBand/README.md) | `lib/core/widgets/fault_band.dart` |
| Feedback | [FaultNote](FaultNote/README.md) | `lib/core/widgets/fault_note.dart` |
| Loading | [Skeleton](Skeleton/README.md) | `lib/core/widgets/shimmer_placeholder.dart`, `lib/core/widgets/app_skeleton.dart`, `lib/core/widgets/list_rows_shimmer.dart` |
| Overlays | [AppBottomSheet](AppBottomSheet/README.md) | `lib/core/widgets/app_bottom_sheet.dart`, `lib/core/utils/sheet_utils.dart` |
| Overlays | [AppDialog](AppDialog/README.md) | `lib/core/widgets/app_dialog.dart` |
| Forms | [TextField](TextField/README.md) | `lib/core/theme.dart` |
| Iconography | [ServiceGlyphs](ServiceGlyphs/README.md) | `lib/core/service_glyphs.dart`, `lib/features/settings/domain/service_key.dart` |
| Media | [ContentCard](ContentCard/README.md) | `lib/core/widgets/content_card.dart` |
| Media | [MediaBrowseScaffold](MediaBrowseScaffold/README.md) | `lib/core/widgets/media_browse_scaffold.dart`, `lib/core/widgets/search_bar_header.dart` |
| Media | [MediaPosterCard](MediaPosterCard/README.md) | `lib/core/widgets/media_poster_card.dart`, `lib/core/widgets/media_grid.dart` |
| Media detail | [LibraryDetailActions](LibraryDetailActions/README.md) | `lib/core/widgets/library_detail_actions.dart`, `lib/core/status/media_action.dart` |
| Media detail | [MediaChildList](MediaChildList/README.md) | `lib/core/widgets/media_child_list.dart` |
| Media detail | [MediaChipSection](MediaChipSection/README.md) | `lib/core/widgets/media_chip_section.dart`, `lib/core/widgets/tag_chip.dart` |
| Media detail | [MediaDetailHero](MediaDetailHero/README.md) | `lib/core/widgets/media_detail_view.dart` |
| Media detail | [MediaDetailSection](MediaDetailSection/README.md) | `lib/core/widgets/media_detail_slot.dart` |
| Media detail | [MediaPage](MediaPage/README.md) | `lib/features/media/presentation/media_page.dart`, `lib/features/media/domain/media_row_view.dart`, `lib/core/title_light.dart` |
| Media detail | [ShelfPage](ShelfPage/README.md) | `lib/features/media/presentation/shelf_page.dart`, `lib/features/music/presentation/artist_page.dart`, `lib/features/readarr/presentation/author_page.dart` |
| Media detail | [MediaInfoCard](MediaInfoCard/README.md) | `lib/core/widgets/media_info_card.dart`, `lib/core/widgets/file_info_section.dart` |
| Media detail | [MediaProseSection](MediaProseSection/README.md) | `lib/core/widgets/media_prose_section.dart` |
| Media detail | [RatingChip](RatingChip/README.md) | `lib/core/widgets/rating_chip.dart`, `lib/core/utils/rating_display.dart` |
| Downloads | [DownloadQueueTile](DownloadQueueTile/README.md) | `lib/core/widgets/download_queue_tile.dart`, `lib/features/qbittorrent/presentation/widgets/torrent_tile.dart` |
| Downloads | [ReleaseRow](ReleaseRow/README.md) | `lib/core/widgets/release_list_widgets.dart`, `lib/core/widgets/interactive_search_sheet.dart` |
| Service surfaces | [AmbientScaffold](AmbientScaffold/README.md) | `lib/core/widgets/ambient_scaffold.dart`, `lib/features/services/presentation/service_home_screen.dart` |
| Service surfaces | [DomainSectionHeader](DomainSectionHeader/README.md) | `lib/core/widgets/domain_section.dart`, `lib/features/settings/domain/service_key.dart` |
| Service surfaces | [ServiceOverview](ServiceOverview/README.md) | `lib/core/widgets/service_overview.dart`, `lib/features/movies/presentation/radarr_overview_screen.dart` |
| Service surfaces | [ServiceRing](ServiceRing/README.md) | `lib/core/widgets/service_ring.dart` |
| Desktop shell | [CommandDeck](CommandDeck/README.md) | `lib/features/shell/presentation/desktop/command_deck.dart`, `lib/features/shell/domain/command_deck_entry.dart` |
| Desktop shell | [DesktopNavRail](DesktopNavRail/README.md) | `lib/features/shell/presentation/desktop/desktop_nav_rail.dart`, `lib/features/settings/domain/nav_tab.dart` |
| Desktop shell | [DesktopShell](DesktopShell/README.md) | `lib/features/shell/presentation/desktop/desktop_shell.dart` |
| Desktop shell | [InspectorPane](InspectorPane/README.md) | `lib/features/shell/presentation/desktop/inspector_pane.dart`, `lib/features/shell/domain/inspector_state.dart` |
| Desktop shell | [ServicePortal](ServicePortal/README.md) | `lib/features/shell/presentation/service_portal.dart` |
| Desktop shell | [WindowChrome](WindowChrome/README.md) | `lib/features/shell/presentation/desktop/window_chrome.dart`, `lib/features/shell/presentation/desktop/service_deck.dart`, `lib/core/platform/desktop_window.dart` |
