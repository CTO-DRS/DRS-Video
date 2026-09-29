import 'package:flutter_test/flutter_test.dart';
import 'package:drs_video/services/player/ab_repeat.dart';
import 'package:drs_video/services/player/audio_enhancer.dart';
import 'package:drs_video/services/security/pin_lock.dart';

void main() {
  group('PinHasher', () {
    test('hash is deterministic for the same pin+salt', () {
      final h1 = PinHasher.hash('1234', 'aabbccdd');
      final h2 = PinHasher.hash('1234', 'aabbccdd');
      expect(h1, h2);
    });

    test('hash differs for different salts (unique salt per install)', () {
      final s1 = PinHasher.newSalt();
      final s2 = PinHasher.newSalt();
      expect(s1, isNot(s2));
      expect(PinHasher.hash('1234', s1), isNot(PinHasher.hash('1234', s2)));
    });

    test('verify accepts the correct pin and rejects wrong ones', () {
      final stored = PinHasher.pack(PinHasher.newSalt(), PinHasher.hash('9513', PinHasher.newSalt()));
      // Build properly: same salt both times.
      final salt = PinHasher.newSalt();
      final stored2 = PinHasher.pack(salt, PinHasher.hash('9513', salt));
      expect(PinHasher.verify('9513', stored2), isTrue);
      expect(PinHasher.verify('9514', stored2), isFalse);
      expect(PinHasher.verify('', stored2), isFalse);
      expect(PinHasher.verify('95133', stored2), isFalse);
      expect(PinHasher.verify('9513', stored), isFalse); // random salt mismatch
    });

    test('pack/unpack round-trips and rejects malformed records', () {
      final packed = PinHasher.pack('salt', 'hash');
      final rec = PinHasher.unpack(packed);
      expect(rec, isNotNull);
      expect(rec!.salt, 'salt');
      expect(rec.hash, 'hash');
      expect(PinHasher.unpack(null), isNull);
      expect(PinHasher.unpack(''), isNull);
      expect(PinHasher.unpack('no-colon'), isNull);
      expect(PinHasher.unpack(':hash'), isNull);
      expect(PinHasher.unpack('salt:'), isNull);
    });

    test('verify against a malformed record never throws', () {
      expect(PinHasher.verify('1234', 'garbage'), isFalse);
    });
  });

  group('AppLockController', () {
    test('no pin configured: gate is always open', () {
      final c = AppLockController(storedHash: null);
      expect(c.hasPin, isFalse);
      expect(c.isLocked, isFalse);
      expect(c.unlock('0000'), UnlockResult.success);
      c.lock(); // must be a no-op
      expect(c.isLocked, isFalse);
    });

    test('cold start with a pin boots locked and unlocks with it', () {
      final c = AppLockController(storedHash: null);
      final packed = c.setPin('2468')!;
      expect(packed, contains(':'));
      expect(c.hasPin, isTrue);
      expect(c.isLocked, isFalse);

      final c2 = AppLockController(storedHash: packed);
      expect(c2.isLocked, isTrue);
      expect(c2.unlock('1111'), UnlockResult.wrongPin);
      expect(c2.isLocked, isTrue);
      expect(c2.unlock('2468'), UnlockResult.success);
      expect(c2.isLocked, isFalse);
    });

    test('setPin rejects short or non-numeric PINs', () {
      final c = AppLockController(storedHash: null);
      expect(c.setPin('123'), isNull); // too short
      expect(c.setPin('12ab'), isNull); // not numeric
      expect(c.setPin('123456'), isNotNull); // longer numeric is allowed
    });

    test('five wrong attempts trigger a 30s lockout, then reset on time', () {
      var now = DateTime(2026, 1, 1, 10);
      final c = AppLockController(
        storedHash: null,
        clock: () => now,
      );
      final packed = c.setPin('9999')!;
      final c2 = AppLockController(storedHash: packed, clock: () => now);

      for (var i = 0; i < 5; i++) {
        expect(c2.unlock('0000'), UnlockResult.wrongPin);
      }
      expect(c2.isLockedOut, isTrue);
      expect(c2.unlock('9999'), UnlockResult.lockedOut); // even the right PIN

      now = now.add(const Duration(seconds: 31));
      expect(c2.isLockedOut, isFalse);
      expect(c2.unlock('9999'), UnlockResult.success);
    });

    test('immediate delay: returning from background re-locks', () {
      var now = DateTime(2026, 1, 1, 10);
      final salt = PinHasher.newSalt();
      final packed = PinHasher.pack(salt, PinHasher.hash('1111', salt));
      final c = AppLockController(
        storedHash: packed,
        delay: AppLockDelay.immediate,
        clock: () => now,
      );
      expect(c.unlock('1111'), UnlockResult.success);
      expect(c.isLocked, isFalse);

      c.onPaused();
      now = now.add(const Duration(seconds: 5));
      c.onResumed();
      expect(c.isLocked, isTrue);
    });

    test('one-minute delay: quick switches do not lock, longer absence does', () {
      var now = DateTime(2026, 1, 1, 10);
      final salt = PinHasher.newSalt();
      final packed = PinHasher.pack(salt, PinHasher.hash('1111', salt));
      final c = AppLockController(
        storedHash: packed,
        delay: AppLockDelay.oneMinute,
        clock: () => now,
      );
      c.unlock('1111');

      c.onPaused();
      now = now.add(const Duration(seconds: 20)); // permission-dialog scale
      c.onResumed();
      expect(c.isLocked, isFalse);

      c.onPaused();
      now = now.add(const Duration(seconds: 61));
      c.onResumed();
      expect(c.isLocked, isTrue);
    });

    test('removePin requires the current pin', () {
      final c = AppLockController(storedHash: null);
      final packed = c.setPin('5555')!;
      final c2 = AppLockController(storedHash: packed);
      expect(c2.removePin('4444'), isFalse);
      expect(c2.hasPin, isTrue);
      expect(c2.removePin('5555'), isTrue);
      expect(c2.hasPin, isFalse);
      expect(c2.isLocked, isFalse);
    });

    test('AppLockDelay ids round-trip', () {
      expect(AppLockDelayX.fromId(AppLockDelay.immediate.id),
          AppLockDelay.immediate);
      expect(AppLockDelayX.fromId(AppLockDelay.oneMinute.id),
          AppLockDelay.oneMinute);
      expect(AppLockDelayX.fromId(AppLockDelay.fiveMinutes.id),
          AppLockDelay.fiveMinutes);
      expect(AppLockDelayX.fromId(null), AppLockDelay.immediate);
      expect(AppLockDelayX.fromId('bogus'), AppLockDelay.immediate);
    });
  });

  group('AbRepeat', () {
    test('inactive by default and without both markers', () {
      final ab = AbRepeat();
      expect(ab.isActive, isFalse);
      expect(ab.rewindTargetMs(60_000), isNull);
    });

    test('set B without A defaults A to 0', () {
      final ab = AbRepeat();
      expect(ab.setB(10_000), isTrue);
      expect(ab.aMs, 0);
      expect(ab.bMs, 10_000);
      expect(ab.isActive, isTrue);
    });

    test('segment shorter than the minimum is rejected', () {
      final ab = AbRepeat();
      ab.setA(5000);
      expect(ab.setB(5000 + AbRepeat.minSegmentMs - 100), isFalse);
      expect(ab.isActive, isFalse);
      expect(ab.setB(5000 + AbRepeat.minSegmentMs), isTrue);
      expect(ab.isActive, isTrue);
    });

    test('rewind triggers at/after B and lands exactly on A', () {
      final ab = AbRepeat();
      ab.setA(10_000);
      ab.setB(20_000);
      expect(ab.rewindTargetMs(19_999), isNull);
      expect(ab.rewindTargetMs(20_000), 10_000);
      expect(ab.rewindTargetMs(25_000), 10_000);
    });

    test('seeking before A does not snap the user back', () {
      final ab = AbRepeat();
      ab.setA(10_000);
      ab.setB(20_000);
      expect(ab.rewindTargetMs(5000), isNull);
      expect(ab.rewindTargetMs(9999), isNull);
    });

    test('setting A after B clears the stale B', () {
      final ab = AbRepeat();
      ab.setA(1000);
      ab.setB(9000);
      ab.setA(9500); // past the old B
      expect(ab.bMs, isNull);
      expect(ab.isActive, isFalse);
      expect(ab.setB(12_000), isTrue);
      expect(ab.isActive, isTrue);
    });

    test('clear resets both markers', () {
      final ab = AbRepeat();
      ab.setA(1000);
      ab.setB(4000);
      ab.clear();
      expect(ab.aMs, isNull);
      expect(ab.bMs, isNull);
      expect(ab.isActive, isFalse);
    });

    test('clearB keeps A for a fresh segment', () {
      final ab = AbRepeat();
      ab.setA(2000);
      ab.setB(8000);
      ab.clearB();
      expect(ab.aMs, 2000);
      expect(ab.bMs, isNull);
    });
  });

  group('AudioEnhancer.buildAf', () {
    test('flat with no boost is an empty chain', () {
      expect(AudioEnhancer.buildAf(AudioPreset.flat, 0), '');
      expect(AudioEnhancer.isActive(AudioPreset.flat, 0), isFalse);
    });

    test('boost alone produces a volume filter', () {
      expect(AudioEnhancer.buildAf(AudioPreset.flat, 6), 'volume=6.0');
      expect(AudioEnhancer.isActive(AudioPreset.flat, 6), isTrue);
    });

    test('every preset emits a valid equalizer chain', () {
      for (final p in AudioPreset.values) {
        if (p == AudioPreset.flat) continue;
        final af = AudioEnhancer.buildAf(p, 0);
        expect(af, isNotEmpty, reason: '$p must produce filters');
        expect(af, contains('equalizer='), reason: '$p must equalize');
        // Every part must be a well-formed filter.
        for (final part in af.split(',')) {
          expect(part, matches(RegExp(r'^[a-z]+=')),
              reason: '$p part "$part" malformed');
        }
      }
    });

    test('preset and boost compose in a single chain', () {
      final af = AudioEnhancer.buildAf(AudioPreset.vocal, 3.5);
      expect(af, startsWith('volume=3.5'));
      expect(af, contains('equalizer='));
      expect(af.split(',').length, 3); // volume + 2 equalizer bands
    });

    test('boost is clamped to the safe maximum', () {
      final af = AudioEnhancer.buildAf(AudioPreset.flat, 100);
      expect(af, 'volume=${AudioEnhancer.maxBoostDb.toStringAsFixed(1)}');
      final negative = AudioEnhancer.buildAf(AudioPreset.flat, -5);
      expect(negative, ''); // negative clamp -> no filter at all
    });

    test('fractional boost keeps one decimal for mpv', () {
      expect(AudioEnhancer.buildAf(AudioPreset.flat, 2.25), 'volume=2.3');
    });
  });
}
