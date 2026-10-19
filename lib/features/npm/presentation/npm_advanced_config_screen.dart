import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_actions.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The per-host custom Nginx block, editable (decision 33).
///
/// NPM writes this text verbatim into the host's `server` section and reloads
/// nginx. If it does not parse, **the hostname stops answering** and stays down
/// until someone comes back and fixes it, and Cupola cannot warn first, because
/// it does not parse Nginx. Three things follow, and all three are drawn:
///
///  * the save asks for the **domain typed back**, not a tap. The domain is the
///    one word muscle memory cannot supply, and on a phone the thing that
///    actually goes wrong is editing the host you did not mean to open;
///  * the only undo is the text this editor opened with: NPM keeps one block
///    per host and no history, so that copy is held for the session and
///    offered as *Revert*;
///  * whatever nginx says afterwards is printed **exactly as it came**
///    (`nginx: [emerg] unknown directive …`), because it names the directive
///    and the line number, and a friendlier paraphrase would throw away the
///    only part that is actionable.
///
/// Routed, a child of the Proxy hosts tab (`ServiceRoutes.npmAdvanced`), and
/// resolved from the path alone: the host is looked up by id in the table the
/// tab already reads. It used to be pushed on the tab's own navigator, which
/// left the URL on the tab, so the service header above stayed drawn and this
/// page's app bar landed on top of it.
class NpmAdvancedConfigScreen extends ConsumerWidget {
  const NpmAdvancedConfigScreen({super.key, required this.hostId});

  final int hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(npmProxyHostsProvider);
    // A reload keeps the editor: the save re-reads the table, and dropping
    // the page to a skeleton would throw away the text being edited.
    final Widget content = hosts.when(
      skipLoadingOnReload: true,
      data: (all) {
        final host = all.where((h) => h.id == hostId).firstOrNull;
        if (host == null) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('This proxy host is no longer on Nginx Proxy Manager.'),
          );
        }
        return _AdvancedEditor(key: ValueKey(host.id), host: host);
      },
      loading: () => const ListRowsShimmer(count: 2),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.nginxProxyManager,
          error,
          consequence: 'the advanced config is not shown',
        ),
        error: error,
        service: ServiceKey.nginxProxyManager,
        onRetry: () => ref.invalidate(npmProxyHostsProvider),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.nginxProxyManager.accent,
      appBar: const GlassAppBar.inPage(pageTitle: 'Advanced'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle('Advanced'),
            // Above the editor, not inside its padded column: the banner owns
            // its own gutter.
            const NpmCapabilityBannerSlot(resources: {NpmResource.proxyHosts}),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _AdvancedEditor extends ConsumerStatefulWidget {
  const _AdvancedEditor({super.key, required this.host});

  final NpmProxyHost host;

  @override
  ConsumerState<_AdvancedEditor> createState() => _AdvancedEditorState();
}

class _AdvancedEditorState extends ConsumerState<_AdvancedEditor> {
  late final TextEditingController _controller;

  /// The block as it stood when this editor opened. The session's only undo.
  late final String _opened;

  bool _busy = false;

  /// nginx's own verdict on the last save, empty until there has been one.
  String _nginxError = '';

  @override
  void initState() {
    super.initState();
    _opened = widget.host.advancedConfig;
    _controller = TextEditingController(text: _opened);
    // Rebuilds Revert and Save as the text changes; both are about whether the
    // buffer still matches what was opened.
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.text != _opened;

  Future<void> _save() async {
    if (!capabilityWriteAllowed(
      context,
      ref,
      service: ServiceKey.nginxProxyManager,
      connectionId: capabilityConnectionId(ref, ServiceKey.nginxProxyManager),
      resource: NpmResource.proxyHosts.key,
      blockedMessage: npmBlockedMessage(NpmResource.proxyHosts),
    )) {
      return;
    }

    final domain = widget.host.primaryDomain;
    final confirmed = await confirmByTyping(
      context,
      title: 'Save the advanced config?',
      message:
          'This goes live the moment nginx reloads. If the block does not '
          'parse, $domain stops answering until you come back and fix it. No '
          'other host is affected. Cupola does not check Nginx syntax. Type the '
          'domain to save.',
      phrase: domain,
      confirmLabel: 'Save and reload',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _nginxError = '';
    });

    // Save and reload are one call; there is no separate reload endpoint and
    // no dry run, so the toast can only report that the write was accepted.
    // Whether nginx *loaded* it is the re-read below.
    NpmProxyHost? after;
    final ok = await runNpmAction(
      context,
      ref,
      resource: NpmResource.proxyHosts,
      action: (client) async {
        after = await client.updateProxyHostAdvancedConfig(
          widget.host.id,
          _controller.text,
        );
      },
      successMessage: 'Saved\u00A0· nginx reloaded',
      failureMessage: 'Could not save the advanced config',
      invalidate: [npmProxyHostsProvider],
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      // A refused configuration is not a failed request: NPM stored the block
      // and answered 200, then nginx declined to load it. The only place that
      // shows is `meta.nginx_err` on the re-read.
      _nginxError = ok && after != null && !after!.configLoaded
          ? after!.errorText
          : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lines = _controller.text.trim().isEmpty
        ? 0
        : _controller.text.trim().split('\n').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Text(
          'The custom Nginx block for ${widget.host.primaryDomain}\u00A0· '
          '$lines ${lines == 1 ? 'line' : 'lines'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _controller,
          minLines: 12,
          maxLines: null,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          // `.mono` rather than the `'monospace'` family alias, which
          // resolves to nothing on iOS and macOS. An Nginx block is read in
          // columns, an indented `location` body is the shape of the
          // thing, so the face is load-bearing, not decorative.
          style: theme.textTheme.bodySmall!.mono.copyWith(
            color: colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: '# nothing yet',
            filled: true,
            fillColor: colorScheme.surface,
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: AppRadius.borderRadiusMd,
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.borderRadiusMd,
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No validation, no autocomplete, no formatter. Cupola cannot tell '
          'you a line is wrong before you save it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (_nginxError.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _NginxVerdict(
            message: _nginxError,
            domain: widget.host.primaryDomain,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                // The only undo NPM leaves: it keeps one block per host and
                // no history, so this is the text this editor opened with
                // and nothing older exists anywhere.
                onPressed: _dirty && !_busy
                    ? () => _controller.text = _opened
                    : null,
                child: const Text('Revert to the block I opened'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              // Gated on the account's scope, and still `null` while there
              // is nothing to save. That is a different reason, and the
              // capability is never expressed as `null`.
              child: CapabilityGatedAction.builder(
                service: ServiceKey.nginxProxyManager,
                connectionId: capabilityConnectionId(
                  ref,
                  ServiceKey.nginxProxyManager,
                ),
                resource: NpmResource.proxyHosts.key,
                hint: npmCapabilityHint,
                blockedMessage: npmBlockedMessage(NpmResource.proxyHosts),
                onTap: _save,
                builder: (context, onPressed, annotate) => FilledButton(
                  onPressed: _dirty && !_busy ? onPressed : null,
                  child: annotate(
                    _busy
                        ? const Text('Reloading nginx…')
                        : const Text('Save changes…'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What nginx said when it refused the block, verbatim.
class _NginxVerdict extends StatelessWidget {
  const _NginxVerdict({required this.message, required this.domain});

  final String message;
  final String domain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Amber, not red: nginx answered, and what it said is that this one host's
    // configuration is refused. Red belongs to an NPM that did not answer.
    final tone = statusToneColor(
      colorScheme,
      StatusTone.warning,
      surface: colorScheme.surface,
    );

    return Semantics(
      container: true,
      label: 'nginx refused this block. $domain is not being served. $message',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(color: tone.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'nginx refused this block. Until a reload succeeds, $domain '
                'reads as refused. The text is saved exactly as typed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                message,
                style: theme.textTheme.bodySmall!.mono.copyWith(color: tone),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
