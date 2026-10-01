import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';

/// What the Access row of one connection holds while it is being edited: the
/// choice, and one field of every choice, so switching choices and back keeps
/// what was typed.
///
/// One controller for the connection form and the first-run walk, so the two
/// cannot disagree about what an Access row saves: [access] is the one
/// answer, and a choice whose fields are all empty is no access at all.
class ConnectionAccessController extends ChangeNotifier {
  ConnectionAccessController(
    this.service, {
    ConnectionAccess initial = const NoAccess(),
    AccessKind? preselect,
  }) : cloudflareId = TextEditingController(
         text: initial is CloudflareServiceToken ? initial.clientId : '',
       ),
       cloudflareSecret = TextEditingController(
         text: initial is CloudflareServiceToken ? initial.clientSecret : '',
       ),
       proxyUsername = TextEditingController(
         text: initial is ProxyPassword ? initial.username : '',
       ),
       proxyPassword = TextEditingController(
         text: initial is ProxyPassword ? initial.password : '',
       ) {
    if (initial is CustomHeaders) {
      for (final entry in initial.entries) {
        _headers.add(AccessHeaderFields(entry.name, entry.value, _changed));
      }
    }
    _kind =
        initial is NoAccess &&
            preselect != null &&
            accessKindsFor(service).contains(preselect)
        ? preselect
        : initial.kind;
    _ensureAHeaderRow();
    for (final field in _fields) {
      field.addListener(_changed);
    }
  }

  final ServiceKey service;
  final TextEditingController cloudflareId;
  final TextEditingController cloudflareSecret;
  final TextEditingController proxyUsername;
  final TextEditingController proxyPassword;
  final List<AccessHeaderFields> _headers = [];
  late AccessKind _kind;

  List<TextEditingController> get _fields => [
    cloudflareId,
    cloudflareSecret,
    proxyUsername,
    proxyPassword,
  ];

  /// The choice made on the row.
  AccessKind get kind => _kind;

  /// The custom header rows, in order.
  List<AccessHeaderFields> get headers => List.unmodifiable(_headers);

  /// The access the row describes, as it would be saved.
  ConnectionAccess get access {
    switch (_kind) {
      case AccessKind.none:
        return const NoAccess();
      case AccessKind.cloudflare:
        final id = cloudflareId.text.trim();
        final secret = cloudflareSecret.text.trim();
        if (id.isEmpty && secret.isEmpty) return const NoAccess();
        return CloudflareServiceToken(clientId: id, clientSecret: secret);
      case AccessKind.password:
        final username = proxyUsername.text.trim();
        final password = proxyPassword.text;
        if (username.isEmpty && password.isEmpty) return const NoAccess();
        return ProxyPassword(username: username, password: password);
      case AccessKind.custom:
        final entries = [
          for (final header in _headers)
            if (!header.isBlank)
              (name: header.name.text.trim(), value: header.value.text),
        ];
        return entries.isEmpty ? const NoAccess() : CustomHeaders(entries);
    }
  }

  void select(AccessKind kind) {
    if (kind == _kind) return;
    _kind = kind;
    _ensureAHeaderRow();
    _changed();
  }

  void addHeader() {
    _headers.add(AccessHeaderFields('', '', _changed));
    _changed();
  }

  void removeHeader(int index) {
    final removed = _headers.removeAt(index);
    _ensureAHeaderRow();
    _changed();
    // After the frame: the row's fields still hold these controllers until
    // the rebuild lands.
    SchedulerBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  /// Takes header [index] off the list and hands back its value, for the move
  /// into the credential field.
  String takeHeaderValue(int index) {
    final value = _headers[index].value.text.trim();
    removeHeader(index);
    return value;
  }

  /// Takes an address's `user:password@` off it and puts it where it belongs:
  /// the proxy password on this row, or, for a service that signs in with
  /// Authorization itself (NZBGet, Transmission, Nginx Proxy Manager), its
  /// own [username] and [password]. The address is left clean, so no
  /// credential is ever stored in it or sent in a request's URL. Whether there
  /// was anything to take.
  bool liftCredentialsFrom(
    TextEditingController address, {
    required TextEditingController username,
    required TextEditingController password,
  }) {
    final credentials = UrlUtils.credentialsInAddress(address.text);
    if (credentials == null) return false;
    address.text = UrlUtils.withoutCredentials(address.text);
    if (service.offersProxyPassword) {
      proxyUsername.text = credentials.username;
      proxyPassword.text = credentials.password;
      select(AccessKind.password);
    } else {
      username.text = credentials.username;
      password.text = credentials.password;
    }
    return true;
  }

  void _ensureAHeaderRow() {
    if (_kind == AccessKind.custom && _headers.isEmpty) {
      _headers.add(AccessHeaderFields('', '', _changed));
    }
  }

  void _changed() => notifyListeners();

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    for (final header in _headers) {
      header.dispose();
    }
    super.dispose();
  }
}

/// One custom header's two fields on the Access row.
class AccessHeaderFields {
  AccessHeaderFields(String name, String value, VoidCallback onChanged)
    : name = TextEditingController(text: name),
      value = TextEditingController(text: value) {
    this.name.addListener(onChanged);
    this.value.addListener(onChanged);
  }

  final TextEditingController name;
  final TextEditingController value;

  /// A row nobody has typed into, which is neither saved nor checked.
  bool get isBlank => name.text.trim().isEmpty && value.text.isEmpty;

  void dispose() {
    name.dispose();
    value.dispose();
  }
}

/// One field of the Access row, as the row hands it to its host to draw.
///
/// [secret] fields are hidden, and [onPaste] fills them from the clipboard:
/// a token or a password is copied from somewhere else rather than typed.
/// [validator] runs under the host's `Form`.
@immutable
class AccessField {
  const AccessField({
    required this.label,
    required this.controller,
    this.secret = false,
    this.validator,
    this.onPaste,
  });

  final String label;
  final TextEditingController controller;
  final bool secret;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onPaste;
}

/// How a host draws the Access row's fields in its own style.
typedef AccessFieldBuilder =
    Widget Function(BuildContext context, AccessField field);

/// The Access row: what a connection presents to a gateway in front of its
/// service, on every request. None, a Cloudflare Access service token, a
/// proxy's password, or custom headers, with labelled fields and the secrets
/// hidden behind Paste.
///
/// The same row in the connection form and in the first-run walk, its fields
/// drawn in the host's style: the form's outlined fields by default, and
/// whatever [fieldBuilder] draws otherwise (the walk's filled fields with
/// their label above). The fields validate as form fields, so the host wraps
/// the row in a `Form`.
///
/// [onMoveToCredential] receives the value of a custom header that duplicates
/// the service's own credential header, for the host to put in the
/// credential field.
class ConnectionAccessFields extends StatefulWidget {
  const ConnectionAccessFields({
    super.key,
    required this.controller,
    required this.onMoveToCredential,
    this.fieldBuilder,
  });

  final ConnectionAccessController controller;
  final ValueChanged<String> onMoveToCredential;

  /// Draws one field in the host's style. Null draws the connection form's
  /// outlined field.
  final AccessFieldBuilder? fieldBuilder;

  @override
  State<ConnectionAccessFields> createState() => _ConnectionAccessFieldsState();
}

class _ConnectionAccessFieldsState extends State<ConnectionAccessFields> {
  ConnectionAccessController get _access => widget.controller;
  ServiceKey get _service => _access.service;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _access,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsSectionLabel('Access'),
          const SizedBox(height: AppSpacing.sm),
          // Wrapped, never scrolled: a choice cut off at the edge of a phone
          // is a choice the user cannot see.
          SelectionPills<AccessKind>.wrap(
            values: accessKindsFor(_service),
            selected: _access.kind,
            labelBuilder: (kind) => kind.label,
            onSelected: _access.select,
          ),
          if (_service.proxyPasswordUnavailable case final why?)
            _note(context, why),
          ...switch (_access.kind) {
            AccessKind.none => const <Widget>[],
            AccessKind.cloudflare => _cloudflareFields(context),
            AccessKind.password => _proxyPasswordFields(context),
            AccessKind.custom => _customHeaderFields(context),
          },
        ],
      ),
    );
  }

  /// A line of explanation under the row, in the page's quiet voice.
  Widget _note(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  List<Widget> _cloudflareFields(BuildContext context) {
    bool started() =>
        _access.cloudflareId.text.trim().isNotEmpty ||
        _access.cloudflareSecret.text.trim().isNotEmpty;
    return [
      const SizedBox(height: AppSpacing.md),
      _field(
        context,
        AccessField(
          label: 'Client ID',
          controller: _access.cloudflareId,
          // A choice left empty saves no access at all; once one half is in,
          // the other is needed.
          validator: (value) => started() && (value ?? '').trim().isEmpty
              ? 'Add the client ID'
              : null,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      _secretField(
        context,
        controller: _access.cloudflareSecret,
        label: 'Client secret',
        validator: (value) => started() && (value ?? '').trim().isEmpty
            ? 'Add the client secret'
            : null,
      ),
      _note(
        context,
        'On Cloudflare: create a service token, then add a Service Auth '
        'policy for it to this application.',
      ),
    ];
  }

  List<Widget> _proxyPasswordFields(BuildContext context) {
    bool started() =>
        _access.proxyUsername.text.trim().isNotEmpty ||
        _access.proxyPassword.text.isNotEmpty;
    return [
      const SizedBox(height: AppSpacing.md),
      // "Proxy" in both labels: a service that signs in with a username and
      // a password of its own shows that pair above these.
      _field(
        context,
        AccessField(
          label: 'Proxy username',
          controller: _access.proxyUsername,
          validator: (value) =>
              started() ? proxyUsernameProblem((value ?? '').trim()) : null,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      _secretField(
        context,
        controller: _access.proxyPassword,
        label: 'Proxy password',
      ),
    ];
  }

  List<Widget> _customHeaderFields(BuildContext context) {
    final headers = _access.headers;
    return [
      for (final (index, header) in headers.indexed) ...[
        const SizedBox(height: AppSpacing.md),
        _headerRow(context, index, header, headers),
      ],
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _access.addHeader,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add a header'),
        ),
      ),
    ];
  }

  Widget _headerRow(
    BuildContext context,
    int index,
    AccessHeaderFields header,
    List<AccessHeaderFields> headers,
  ) {
    List<AccessHeader> entries() => [
      for (final other in headers)
        if (!other.isBlank)
          (name: other.name.text.trim(), value: other.value.text),
    ];
    final clash = duplicatesCredentialHeader(_service, header.name.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                context,
                AccessField(
                  label: 'Header name',
                  controller: header.name,
                  validator: (value) {
                    if (header.isBlank) return null;
                    final name = (value ?? '').trim();
                    // Not saved while it stands: Cupola's own header would win
                    // and this one would never be sent.
                    if (duplicatesCredentialHeader(_service, name)) {
                      return credentialHeaderClash(_service);
                    }
                    return customHeaderNameProblem(
                      _service,
                      name,
                      earlier: [
                        for (final other in headers.take(index))
                          if (!other.isBlank) other.name.text,
                      ],
                    );
                  },
                ),
              ),
            ),
            IconButton(
              onPressed: () => _access.removeHeader(index),
              icon: const Icon(Icons.remove_circle_outline_rounded),
              tooltip: 'Remove header',
            ),
          ],
        ),
        if (clash)
          Row(
            children: [
              Expanded(child: _note(context, credentialHeaderClash(_service))),
              TextButton(
                onPressed: () =>
                    widget.onMoveToCredential(_access.takeHeaderValue(index)),
                child: const Text('Move it'),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        _secretField(
          context,
          controller: header.value,
          label: 'Header value',
          validator: (value) {
            if (header.isBlank) return null;
            final problem = customHeaderValueProblem(value ?? '');
            if (problem != null) return problem;
            // Said once, under the last value, for the list as a whole.
            final isLast = index == headers.length - 1;
            return isLast && exceedsAccessHeadersLimit(entries())
                ? kAccessHeadersTooLarge
                : null;
          },
        ),
      ],
    );
  }

  /// A secret of the row: hidden, with Paste beside it, since a token or a
  /// password is copied from somewhere else rather than typed.
  Widget _secretField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    FormFieldValidator<String>? validator,
  }) => _field(
    context,
    AccessField(
      label: label,
      controller: controller,
      secret: true,
      validator: validator,
      onPaste: () => _paste(controller),
    ),
  );

  /// [field] in the host's style, or the connection form's.
  Widget _field(BuildContext context, AccessField field) =>
      widget.fieldBuilder?.call(context, field) ?? _formField(field);

  /// The connection form's field: outlined, its label floating in the frame.
  Widget _formField(AccessField field) => TextFormField(
    controller: field.controller,
    decoration: InputDecoration(
      labelText: field.label,
      suffixIcon: field.onPaste == null
          ? null
          : IconButton(
              onPressed: field.onPaste,
              icon: const Icon(Icons.content_paste_rounded),
              tooltip: 'Paste',
            ),
    ),
    obscureText: field.secret,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: field.secret ? TextInputType.visiblePassword : null,
    textInputAction: TextInputAction.next,
    validator: field.validator,
  );

  Future<void> _paste(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    controller.text = text;
  }
}
