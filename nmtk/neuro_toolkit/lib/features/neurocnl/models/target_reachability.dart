/// Result of `GET /targets/{id}/reachability`.
///
/// Mirrors the backend's `ReachabilityResponse` (`app/routers/target_reachability.py`),
/// which answers the question *from inside the backend container*: is the target's
/// SDK importable there, and does a local device enumeration find anything?
///
/// [detail] is the part worth showing a user — "akida SDK not installed",
/// "no Akida devices connected", "3 device(s) found", or the string of whatever
/// exception the probe raised. A bare boolean cannot distinguish "the SDK is
/// missing" from "the SDK is fine but no card is plugged in", so callers that
/// only had the boolean had to guess a message.
class TargetReachability {
  const TargetReachability({required this.reachable, this.detail = ''});

  final bool reachable;
  final String detail;
}
