# HomeModule

One module of the Home in the slab every module shares, and the two pieces of the operator's Home that are not
modules of content: Needs you at the top and Set up next at the foot. A module decides its state; the frame draws it,
so no module invents its own way of loading, failing or asking for a service.

Rendered from `lib/features/home/presentation/widgets/home_module_frame.dart` (`HomeModuleFrame`),
`lib/features/home/presentation/widgets/needs_you_banner.dart` (`NeedsYouLine`, its words from
`lib/features/home/domain/needs_you.dart`) and `lib/features/home/presentation/widgets/set_up_next_module.dart`
(`SetUpNextModule`, `EditHomeRow`, its suggestions from `lib/features/home/domain/set_up_next.dart`), by
`test/design_catalog/home_module_catalog_test.dart`. Which modules a person's Home has, in what order, is the registry
`HomeModule` (`lib/features/home/domain/home_module.dart`) read through the person's saved layout; see
[EditHome](../EditHome/README.md).

## The five states

- **Loading** (`HomeModuleFrame.loading`): the module's name in the section role over the shape of its rows (two
  list rows unless the module passes its own skeleton, a poster row for Arrived). Never a spinner in the middle of the
  Home. Spoken `Loading downloads`.
- **Ready** (the default constructor): the name, the line under it in `meta` and `inkSecondary` (`2 wait for you`,
  `1 downloading · 15.5 MB/s across 2 clients`), an optional quiet link at the end of the heading, the rows. Rows are
  rows of the slab, a hairline between them, never cards inside it.
- **Nothing to say**: no frame. The module draws nothing and the next one moves up: the Home has no empty boxes. Only
  when every source answered: a source that did not answer is not an empty one.
- **Its sources did not answer** (`HomeModuleFrame.silent`): the module keeps its place and says which service and why
  through the classification (`coverageFailureSentence`), as a `FaultBand.section` (red, a source did not answer) or
  `FaultBand.partial` (amber, it answered with a fault), with Retry. What was last known may sit above it, dimmed.
- **Its service is not set up** (`HomeModuleFrame.needsService`): `Set up TrueNAS to see storage`, what it would show,
  and `Set up TrueNAS` at the end, the whole slab one target. Only for a module the person switched on in Edit Home;
  a module on by default whose service is missing is not drawn, and Set up next names the service once.

The slab is `slab`, `AppRadius.slab`, a `hair` edge, padding `gutter` × `slabY`, `md` between modules.

## Needs you

One line, one target, first on the operator's Home and absent when nothing is wrong (the header's `12 of 12
answering` already answers) or before anything answered (no space is held for it).

- A service that did not answer leads, the glyph red: `Radarr did not answer at 20:53`, and the line is its Retry
  (`Retry both` for two). Its faults cannot be seen while it is silent.
- Otherwise the largest group of equal faults leads, the glyph amber: `18 downloads need a manual import`; a single
  fault is a sentence about it (`Big Buck Bunny is stuck`, `The media stack stopped`, `The certificate for
  nas.home.arpa expires in 6 days`). The line is Review, which opens the place that fault is fixed today.
- `+2` when more things need the person. A request waiting for approval is not a fault: it is never in Needs you.
- `fillQuiet` under a `hair` edge, `AppRadius.button`, at least 52pt tall. At a large reading size the count and the
  way in go under the sentence.

## Set up next and Edit Home

- **Set up next** (`SetUpNextModule`): at most three services the stack lacks, each with what it adds (`Set up
  Jellyfin · Play on every title, and who is watching`), ordered by how much, then `All services`. A Plex stands for
  Jellyfin, any download client for the four. Absent when nothing it knows of is missing. Each row opens that service's
  setup form in Settings, whose way back leads to the Home.
- **EditHomeRow**: the last thing on the operator's Home, a dashed `edge` around `Edit Home · Reorder and hide
  modules`, opening `/home/edit`.

## Semantics

A module's heading is one header node: its name and the line under it (`Requests, 2 wait for you`). Needs you is one
button whose label is the whole sentence, the way in at its end (`18 downloads need a manual import, and 2 more things
need you. Review`), announced when it appears. Each Set up next row is one button, its line as the value.

## States in the catalog

Each sheet is drawn in the dark and the light room: the frame ready, loading, silent and needing a service; Needs
you led by a group, by one fault and by a silent service; Set up next over Radarr, Sonarr and Seerr; the Edit Home
row; text at 200%.

## Do / don't

- Do let a module draw nothing when it has nothing to say, and only then.
- Don't put a card inside the slab, or a second Retry under a silent module.
- Don't say `Set up X` twice on one Home: a missing service is named by Set up next, once.
