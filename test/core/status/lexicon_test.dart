import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';

/// The brand book's lexicon table, held word by word: one word per state, in
/// the tone the tone rule gives it.
void main() {
  test('each state word carries the tone the brand book gives it', () {
    expect(StateWord.answering.tone, StatusTone.success);
    // The only red words.
    expect(StateWord.didNotAnswer.tone, StatusTone.error);
    expect(StateWord.values.where((w) => w.tone == StatusTone.error), [
      StateWord.didNotAnswer,
    ]);
    expect(StateWord.notSetUp.tone, isNull);
    expect(StateWord.stuck.tone, StatusTone.warning);
    expect(StateWord.failed.tone, StatusTone.warning);
    // Stopped on purpose, and the backlog: neutral, never amber.
    for (final word in [
      StateWord.stopped,
      StateWord.missing,
      StateWord.wanted,
      StateWord.cutoffUnmet,
      StateWord.notAired,
      StateWord.notOutYet,
    ]) {
      expect(word.tone, StatusTone.neutral, reason: word.label);
    }
    expect(StateWord.waitingForApproval.tone, StatusTone.info);
  });

  test('the classification spells silence with the same word', () {
    expect(
      failureLabel(ServiceFailureReason.unreachable),
      StateWord.didNotAnswer.label,
    );
  });

  test('a word inside a sentence drops its capital, never an acronym', () {
    expect(StateWord.didNotAnswer.inline, 'did not answer');
    expect(StateWord.stuck.inline, 'stuck');
    expect(Lexicon.inline('Refused the key'), 'refused the key');
    expect(
      Lexicon.inline('API not at this address'),
      'API not at this address',
    );
  });

  test('the way in names the service', () {
    expect(Lexicon.setUp('Plex'), 'Set up Plex');
    expect(Lexicon.isNotSetUp('Plex'), 'Plex is not set up');
    expect(Lexicon.retry, 'Retry');
  });
}
