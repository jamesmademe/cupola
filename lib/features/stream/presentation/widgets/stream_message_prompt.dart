/// Composing the one line Cupola can put on somebody's television.
///
/// Its own file because it is the only text *entry* on the Stream surfaces, and
/// the only one in the app that writes to a screen the user is not looking at.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// How many characters a player will draw before it starts cutting.
///
/// Clients differ and none of them documents a limit, so this is a floor rather
/// than a protocol fact: a message long enough to overflow the shortest of them
/// is a message the sender cannot predict the shape of, and one they will not
/// know was truncated. Enforced in the field rather than after sending, so the
/// limit is visible while typing.
const int kStreamMessageMaxLength = 120;

/// Asks for a line of text to send to [playerLabel], or null if the user backs
/// out.
///
/// Returns the trimmed text; never an empty string, because "send nothing" is
/// the cancel case and a player that receives an empty toast shows an empty box
/// over whatever is playing.
///
/// **Named for its target.** A message is an interruption of a specific person
/// on a specific screen, and a dialog titled "Send a message" leaves the sender
/// to remember which of four sessions they tapped.
Future<String?> showStreamMessagePrompt({
  required BuildContext context,
  required String userName,
  required String playerLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _MessagePrompt(userName: userName, playerLabel: playerLabel),
  );
}

class _MessagePrompt extends StatefulWidget {
  const _MessagePrompt({required this.userName, required this.playerLabel});

  final String userName;
  final String playerLabel;

  @override
  State<_MessagePrompt> createState() => _MessagePromptState();
}

class _MessagePromptState extends State<_MessagePrompt> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The Send button is disabled until there is something to send, so it has to
    // rebuild as the field fills.
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  String get _text => _controller.text.trim();

  void _send() {
    if (_text.isEmpty) return;
    Navigator.of(context).pop(_text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Message ${widget.userName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge!.weight(FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Says where it lands and that it may not: the server relays the
            // command over the connection it holds to the client, and a client
            // that has nowhere to draw a toast simply ignores it.
            'It appears on ${widget.playerLabel}. Some players cannot show '
            'messages and will ignore it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: kStreamMessageMaxLength,
            maxLines: 2,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'Dinner in ten minutes',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Disabled rather than hidden: the button is the affordance that says
          // what the field is for, and removing it while the field is empty
          // would take it out of the focus order at the moment it is needed.
          onPressed: _text.isEmpty ? null : _send,
          child: const Text('Send'),
        ),
      ],
    );
  }
}
