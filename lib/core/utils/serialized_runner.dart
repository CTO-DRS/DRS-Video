import 'dart:async';

/// P4-M1 — strict one-at-a-time async pass runner.
///
/// A scheduler-like method that mutates shared state across many `await`
/// points (slot accounting, maps, database rows) must never run two passes
/// concurrently: two interleaved passes read the same "free slots" count
/// and both act on it (double-start the same task, double-write a row).
/// Firing the method from many event sources (native callbacks, connectivity
/// listener, user actions) makes that overlap a matter of time.
///
/// [SerializedRunner] queues passes strictly in request order: pass N+1
/// starts only after pass N fully drained. `await runner.run(pass)` still
/// means "my pass ran to completion" — callers keep their semantics, they
/// just can no longer interleave.
///
/// Error contract: a failing pass completes ITS OWN returned future with
/// that error (so an awaiting caller sees it, same as the un-serialized
/// version) and never blocks or poisons the chain — the next pass still
/// runs. A previous pass failing does not stop later passes either.
/// Fire-and-forget callers should submit passes that do not throw
/// (catch-and-log inside) to keep the zone clean.
class SerializedRunner {
  Future<void>? _tail;

  /// Runs [pass] after every previously submitted pass drained.
  Future<void> run(Future<void> Function() pass) {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    unawaited(() async {
      Object? error;
      StackTrace? stack;
      try {
        await prev;
      } catch (_) {
        // A previous pass failing must not block this one — each pass
        // owns its own outcome.
      }
      try {
        await pass();
      } catch (e, s) {
        error = e;
        stack = s;
      }
      if (error != null) {
        done.completeError(error, stack);
      } else {
        done.complete();
      }
    }());
    return done.future;
  }

  /// Completes when every submitted pass has drained (test convenience).
  Future<void> get idle => _tail ?? Future.value();
}
