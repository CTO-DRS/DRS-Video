import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// v1.14.4 stall-proof download engine.
///
/// The native flutter_downloader engine streams one long GET. On networks
/// where the CDN throttles or drops the connection mid-body (the exact
/// user report: task stuck at 0% forever) that engine has no recovery —
/// TCP reads just block forever.
///
/// This engine:
///  1. splits the file into 2–4 parallel Range segments (defeats per-
///     connection throttling and multiplies throughput),
///  2. fetches each segment in ~1 MiB chunked requests — a dead connection
///     only ever costs one chunk, and Dio's receiveTimeout turns a stalled
///     body into an exception that triggers an automatic resume at the
///     exact byte offset (Range),
///  3. keeps every segment in its own `<file>.partN` side file written
///     sequentially (append mode), with per-segment watermarks persisted
///     in a tiny `<file>.drsmeta` sidecar after every chunk — pausing,
///     killing the app, or process death resumes where it stopped,
///  4. concatenates the parts into the final file at completion.
///
/// The pure planning/persistence helpers are unit-tested; the IO class is
/// the runtime wrapper.

// ---------------------------------------------------------------------------
// Pure planning logic (unit-tested, no IO)
// ---------------------------------------------------------------------------

const int kMinEngineSize = 4 * 1024 * 1024; // < 4 MiB → native engine is fine
const int kChunkSize = 1024 * 1024; // 1 MiB per Range request
const Duration kChunkReceiveTimeout = Duration(seconds: 20);
const int kMaxChunkRetries = 8;

/// One contiguous piece of the file. [received] is the segment-local
/// watermark (bytes of THIS segment already written to its part file).
class SegmentSpec {
  SegmentSpec({
    required this.start,
    required this.endInclusive,
    this.received = 0,
  });

  final int start;
  final int endInclusive;
  int received;

  int get length => endInclusive - start + 1;
  int get remaining => length - received;
  bool get done => received >= length;

  int get absoluteCursor => start + received;

  Map<String, Object?> toMap() => {
        's': start,
        'e': endInclusive,
        'r': received,
      };

  static SegmentSpec fromMap(Map<Object?, Object?> m) => SegmentSpec(
        start: (m['s'] as num).toInt(),
        endInclusive: (m['e'] as num).toInt(),
        received: ((m['r'] as num?) ?? 0).toInt(),
      );
}

/// Splits [total] bytes into at most [maxSegments] contiguous segments.
/// Guarantees: no gaps, no overlaps, every segment non-empty.
/// [seedOffset] marks bytes already present at the head of the final file
/// (a partial download promoted from the native engine) — segments only
/// cover [seedOffset, total) and part files hold ONLY their own span.
List<SegmentSpec> planSegments(
  int total,
  int maxSegments, {
  int seedOffset = 0,
}) {
  final span = total - seedOffset;
  if (total <= 0 || span <= 0) return const [];
  final count = span < maxSegments ? span : maxSegments;
  final base = span ~/ count;
  final extra = span % count;
  final segments = <SegmentSpec>[];
  var cursor = seedOffset;
  for (var i = 0; i < count; i++) {
    final len = base + (i < extra ? 1 : 0);
    segments.add(SegmentSpec(start: cursor, endInclusive: cursor + len - 1));
    cursor += len;
  }
  return segments;
}

/// How many parallel segments a download of [total] bytes should use.
/// [freeBytes] is the device free space: concatenating parts at the end
/// needs the file size a second time, so tight storage forces a single
/// segment (its part file is renamed directly — zero extra space).
int segmentCountFor(int total, {int freeBytes = -1}) {
  if (total < 16 * 1024 * 1024) return 2;
  final spacious = freeBytes < 0 || freeBytes >= total * 2;
  return spacious ? 4 : 2;
}

/// End offset (inclusive) of the chunk window starting at [cursor].
int chunkWindowEnd(int cursor, int segEndInclusive, int chunkSize) {
  final end = cursor + chunkSize - 1;
  return end > segEndInclusive ? segEndInclusive : end;
}

/// Whether a task should run on this engine instead of flutter_downloader.
bool engineEligible(int? expectedSize) =>
    expectedSize != null && expectedSize >= kMinEngineSize;

double percentOf(int received, int total) {
  if (total <= 0) return 0;
  if (received >= total) return 100;
  final p = received * 100 / total;
  return p < 0 ? 0 : p;
}

/// Final name of the part file holding segment [index].
String partFileName(String filePath, int index) => '$filePath.part$index';

// ---------------------------------------------------------------------------
// Sidecar persistence
// ---------------------------------------------------------------------------

/// Crash-safe watermark sidecar, stored next to the final file.
class EngineState {
  EngineState({
    required this.version,
    required this.url,
    required this.total,
    required this.segments,
  });

  static const int kVersion = 1;

  final int version;
  String url;
  final int total;
  final List<SegmentSpec> segments;

  int get received => segments.fold(
      0, (sum, s) => sum + s.received.clamp(0, s.length));

  Map<String, Object?> toMap() => {
        'v': version,
        'url': url,
        'total': total,
        'segs': segments.map((s) => s.toMap()).toList(),
      };

  String encode() => jsonEncode(toMap());

  /// Null on any inconsistency (corrupt JSON, wrong version, layout that
  /// doesn't tile [0, total)) — callers then re-plan from the seed.
  ///
  /// [url] is the LIVE task url and always wins: signed CDN urls refresh
  /// across retries while byte watermarks stay valid.
  static EngineState? decode(String? raw, {required String url}) {
    if (raw == null || raw.isEmpty) return null;
    Map<String, Object?> m;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      m = decoded;
    } catch (_) {
      return null;
    }
    if ((m['v'] as num?)?.toInt() != kVersion) return null;
    final total = (m['total'] as num?)?.toInt();
    if (total == null || total <= 0) return null;
    final segsRaw = m['segs'];
    if (segsRaw is! List || segsRaw.isEmpty) return null;
    final segments = <SegmentSpec>[];
    for (final s in segsRaw) {
      if (s is! Map) return null;
      segments.add(SegmentSpec.fromMap(s));
    }
    // Layout must tile [0, total); each watermark must fit its segment.
    var expected = 0;
    for (final s in segments) {
      if (s.start != expected || s.endInclusive < s.start) return null;
      if (s.received < 0 || s.received > s.length) return null;
      expected = s.endInclusive + 1;
    }
    if (expected != total) return null;
    return EngineState(
      version: kVersion,
      url: url,
      total: total,
      segments: segments,
    );
  }
}

// ---------------------------------------------------------------------------
// Stall watchdog decision (pure, unit-tested)
// ---------------------------------------------------------------------------

/// Decides when a native flutter_downloader task is "stalled" (no progress
/// for [stallAfter]) and when kicks are exhausted.
class StallTracker {
  StallTracker({
    this.stallAfter = const Duration(seconds: 45),
    this.maxKicks = 3,
  });

  final Duration stallAfter;
  final int maxKicks;

  final _lastChange = <String, DateTime>{};
  final _kicks = <String, int>{};

  /// Call on every progress event (even 0-byte ticks).
  void touch(String id, {DateTime? now}) =>
      _lastChange[id] = now ?? DateTime.now();

  /// True when the task has shown no progress for [stallAfter].
  bool isStalled(String id, {DateTime? now}) {
    final last = _lastChange[id];
    if (last == null) return false;
    final t = now ?? DateTime.now();
    return t.difference(last) >= stallAfter;
  }

  /// Records a kick; true when the task should be escalated (kicks
  /// exhausted). A kick also resets the stall clock.
  bool kick(String id, {DateTime? now}) {
    final k = (_kicks[id] ?? 0) + 1;
    _kicks[id] = k;
    touch(id);
    return k >= maxKicks;
  }

  void forget(String id) {
    _lastChange.remove(id);
    _kicks.remove(id);
  }
}

// ---------------------------------------------------------------------------
// IO engine
// ---------------------------------------------------------------------------

enum ChunkedEngineOutcome { completed, nonResumable, failed }

enum _SegmentResult { done, failed, nonResumable, stopped }

/// Runtime engine for one task. See the library doc above.
class ChunkedDownloadEngine {
  ChunkedDownloadEngine({
    required this.url,
    required this.headers,
    required this.filePath,
    required this.total,
    this.maxSegments = 4,
    this.seedOffset = 0,
    this.onProgress,
    this.onLog,
  });

  final String url;
  final Map<String, String> headers;
  final String filePath;
  final int total;
  final int maxSegments;

  /// Bytes already present at the head of [filePath] from a previous
  /// (native) partial attempt — segments start after them.
  final int seedOffset;

  /// Exact byte watermark, throttled to ~2 Hz.
  final void Function(int receivedBytes)? onProgress;
  final void Function(String message)? onLog;

  late final String _sidecarPath = '$filePath.drsmeta';
  final _cancelTokens = <CancelToken>[];
  EngineState? _state;
  bool _stopped = false;
  Timer? _progressTimer;
  int _lastReported = -1;

  int get received => _state?.received ?? 0;

  /// Loads an existing sidecar (same layout + total) or plans fresh.
  /// Signed URLs refresh across retries — byte offsets stay valid, so a
  /// restored state always adopts the current [url].
  Future<EngineState> _prepareState() async {
    final restored = EngineState.decode(await _readSidecar(), url: url);
    if (restored != null && restored.total == total) {
      restored.url = url;
      return restored;
    }
    // Fresh plan: stale part files from an earlier crashed attempt would
    // misalign append writes — remove them first.
    for (var i = 0; i < maxSegments; i++) {
      try {
        final p = File(partFileName(filePath, i));
        if (p.existsSync()) await p.delete();
      } catch (_) {}
    }
    return EngineState(
      version: EngineState.kVersion,
      url: url,
      total: total,
      segments:
          planSegments(total, maxSegments, seedOffset: seedOffset),
    );
  }

  Future<String?> _readSidecar() async {
    try {
      final f = File(_sidecarPath);
      if (!f.existsSync()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistState() async {
    final state = _state;
    if (state == null) return;
    try {
      final tmp = File('$_sidecarPath.tmp');
      await tmp.writeAsString(state.encode(), flush: true);
      await tmp.rename(_sidecarPath);
    } catch (e) {
      onLog?.call('sidecar write failed: $e');
    }
  }

  CancelToken _newToken() {
    final t = CancelToken();
    _cancelTokens.add(t);
    return t;
  }

  /// Runs to completion (or pause/failure). Safe to await from the service.
  Future<ChunkedEngineOutcome> run() async {
    try {
      _state = await _prepareState();
      final state = _state!;

      _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _report();
      });

      final outcomes = await Future.wait(
        List<int>.generate(state.segments.length, (i) => i)
            .map((i) => _runSegment(i, state.segments[i])),
        eagerError: false,
      );
      _progressTimer?.cancel();
      if (_stopped) return ChunkedEngineOutcome.failed; // paused/cancelled
      if (outcomes.contains(_SegmentResult.nonResumable)) {
        return ChunkedEngineOutcome.nonResumable;
      }
      if (outcomes.contains(_SegmentResult.failed)) {
        await _persistState();
        return ChunkedEngineOutcome.failed;
      }

      return await _assemble();
    } catch (e) {
      onLog?.call('engine crash: $e');
      await _persistState();
      return ChunkedEngineOutcome.failed;
    }
  }

  Future<_SegmentResult> _runSegment(int index, SegmentSpec seg) async {
    var attempt = 0;
    while (!seg.done && !_stopped) {
      final cursor = seg.absoluteCursor;
      final winEnd = chunkWindowEnd(cursor, seg.endInclusive, kChunkSize);
      final token = _newToken();
      try {
        final res = await Dio().get(
          url,
          options: Options(
            headers: {
              ...headers,
              'Range': 'bytes=$cursor-$winEnd',
            },
            responseType: ResponseType.stream,
            receiveTimeout: kChunkReceiveTimeout,
            connectTimeout: const Duration(seconds: 15),
            validateStatus: (code) => code != null && code < 400,
          ),
          cancelToken: token,
        );

        final status = res.statusCode ?? 0;
        if (status == 200) {
          // Server ignored Range: a full-body answer cannot resume any
          // segment (and would loop the same window forever). Escalate to
          // the caller, which falls back to the native single-GET engine.
          if (!token.isCancelled) token.cancel(); // drop the open socket
          _stopped = true; // stop sibling segments promptly
          return _SegmentResult.nonResumable;
        }
        if (status != 206) {
          throw DioException.connectionError(
              requestOptions: res.requestOptions, reason: 'HTTP $status');
        }

        final body = res.data as ResponseBody;
        final written = await _pumpChunk(index, body, seg, winEnd);
        seg.received += written;
        if (seg.received > seg.length) seg.received = seg.length;
        await _persistState();
        attempt = 0; // a healthy chunk resets the retry ladder
      } catch (e) {
        if (_stopped) return _SegmentResult.stopped;
        attempt++;
        if (attempt > kMaxChunkRetries) {
          onLog?.call(
              'segment[$index] gave up after $attempt attempts: $e');
          return _SegmentResult.failed;
        }
        await Future.delayed(
            Duration(milliseconds: 300 * attempt.clamp(1, 5)));
      } finally {
        _cancelTokens.remove(token);
      }
    }
    return _SegmentResult.done;
  }

  /// Streams one chunk window sequentially into the segment's part file.
  /// Append mode means no positioned writes are needed; the returned count
  /// is added to the watermark by the caller and persisted in the sidecar.
  Future<int> _pumpChunk(
      int index, ResponseBody body, SegmentSpec seg, int winEnd) async {
    final part = File(partFileName(filePath, index));
    final windowLen = winEnd - seg.absoluteCursor + 1;
    final cap =
        windowLen < seg.remaining ? windowLen : seg.remaining;
    final raf = await part.open(mode: FileMode.append);
    var written = 0;
    try {
      await for (final chunk in body.stream) {
        if (_stopped) break;
        if (chunk.isEmpty) continue;
        var take = chunk;
        if (written + take.length > cap) {
          take = take.sublist(0, cap - written);
        }
        await raf.writeFrom(take);
        written += take.length;
        if (written >= cap) break;
      }
      await raf.flush();
    } finally {
      await raf.close();
      // The await-for subscription is cancelled automatically on break,
      // which tears down the socket — nothing to close by hand here.
    }
    // Hostile/buggy server sent more than the window: realign the part
    // file with the watermark we are about to return so the next append
    // (after resume) lands at the right offset.
    final len = await part.length();
    if (len > seg.received + written) {
      final fix = await part.open(mode: FileMode.append);
      try {
        await fix.truncate(seg.received + written);
      } finally {
        await fix.close();
      }
    }
    return written;
  }

  /// All segments done: verify part sizes, then either rename (single
  /// segment, no seed — zero extra space) or concatenate in order into the
  /// final file (keeping any seeded head bytes from a promoted native
  /// partial), then remove parts + sidecar.
  Future<ChunkedEngineOutcome> _assemble() async {
    final state = _state!;
    try {
      final canRename = state.segments.length == 1 && seedOffset == 0;
      if (canRename) {
        final part = File(partFileName(filePath, 0));
        if (await part.length() != total) {
          onLog?.call('size mismatch after single-segment: '
              '${await part.length()} != $total');
          return ChunkedEngineOutcome.failed;
        }
        await part.rename(filePath);
      } else {
        final out = File(filePath).openSync(mode: FileMode.writeOnlyAppend);
        try {
          // Re-seed: when the head bytes already live in the final file
          // (promoted native partial), keep exactly that span.
          if (await out.length() > seedOffset) {
            await out.truncate(seedOffset);
          }
          for (var i = 0; i < state.segments.length; i++) {
            final seg = state.segments[i];
            final part = File(partFileName(filePath, i));
            if (await part.length() != seg.length) {
              onLog?.call('part[$i] size mismatch: '
                  '${await part.length()} != ${seg.length}');
              return ChunkedEngineOutcome.failed;
            }
            await for (final chunk in part.openRead()) {
              await out.writeFrom(chunk);
            }
          }
          await out.flush();
        } finally {
          await out.close();
        }
        for (var i = 0; i < state.segments.length; i++) {
          final p = File(partFileName(filePath, i));
          if (await p.exists()) await p.delete();
        }
      }
      try {
        final sidecar = File(_sidecarPath);
        if (sidecar.existsSync()) await sidecar.delete();
      } catch (_) {}
      _report(force: true);
      return ChunkedEngineOutcome.completed;
    } catch (e) {
      onLog?.call('assemble failed: $e');
      return ChunkedEngineOutcome.failed;
    }
  }

  void _report({bool force = false}) {
    final cb = onProgress;
    if (cb == null || _state == null) return;
    final r = _state!.received;
    if (!force && r == _lastReported) return;
    _lastReported = r;
    cb(r);
  }

  /// Pauses: stops all segments; watermarks are already persisted.
  void pause() {
    _stopped = true;
    for (final t in List<CancelToken>.from(_cancelTokens)) {
      if (!t.isCancelled) t.cancel();
    }
    _progressTimer?.cancel();
  }

  /// Same as [pause] but also removes the partial file + sidecar.
  Future<void> cancelAndCleanup() async {
    pause();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final sidecarState = _state;
    for (final p in [
      filePath,
      _sidecarPath,
      '$_sidecarPath.tmp',
      if (sidecarState != null)
        for (var i = 0; i < sidecarState.segments.length; i++)
          partFileName(filePath, i),
    ]) {
      try {
        final f = File(p);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }
}
