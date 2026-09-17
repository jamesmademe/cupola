/// Transmission's eight states in the app's five tones, in one place.
///
/// It lives here rather than beside either of the two surfaces that need it
/// because it used to live beside **both**, and the copies drifted: the queue
/// plate switched exhaustively over `TransmissionStatus` while the Overview's
/// Finished region guarded two arms and fell through to green for the rest. The
/// same torrent — one sitting in the seed queue, one being re-verified, one
/// whose status code the app does not know — was a neutral chip two regions
/// above and a green dot below.
library;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// How a torrent's current state reads on the five-arm tone rule.
///
///  * **amber** for anything [TransmissionTorrent.warning] names — a stall or a
///    daemon-reported error. Both are faults: the client answered, and what it
///    answered is that this torrent is stuck. Red would claim it never replied.
///  * **green** for seeding, the one state that means "this one is done".
///  * **blue** for a live download or a running check, which is work in flight.
///  * **neutral** for stopped, for the three queues, and for a status code this
///    app has no name for — backlog and deliberate stops are the resting state
///    of a torrent client and must not compete with the states that are
///    actually wrong, and an unknown code is not evidence of anything.
///
/// Green is never the fallthrough. A finished torrent queued to seed has not
/// finished *seeding*, and "the switch ran out of arms" is not a reason to
/// claim it did.
StatusTone transmissionTorrentTone(TransmissionTorrent torrent) {
  if (torrent.warning != null) return StatusTone.warning;
  return switch (torrent.status) {
    TransmissionStatus.seed => StatusTone.success,
    TransmissionStatus.download || TransmissionStatus.check => StatusTone.info,
    TransmissionStatus.stopped ||
    TransmissionStatus.downloadWait ||
    TransmissionStatus.seedWait ||
    TransmissionStatus.checkWait ||
    TransmissionStatus.unknown => StatusTone.neutral,
  };
}
