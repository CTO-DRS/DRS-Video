import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:drs_video/core/storage/database_service.dart';
import 'package:drs_video/core/storage/preferences_service.dart';
import 'package:drs_video/data/models/media_item.dart';
import 'package:drs_video/data/repositories/library_repository.dart';
import 'package:drs_video/services/player/subtitle_charset.dart';
import 'package:drs_video/services/player/subtitle_parser.dart';
import 'package:drs_video/services/security/pin_lock.dart';
import 'package:drs_video/services/security/secure_flag.dart';
import 'package:drs_video/services/security/vault_controller.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  // =====================================================================
  // Private vault — repository layer (v1.10.0)
  // =====================================================================
  group('vault repository', () {
    late DatabaseService db;
    late LibraryRepository library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = DatabaseService.instance;
      await db.database;
      library = LibraryRepository(db);
    });

    tearDown(() async {
      await db.deleteAllData();
    });

    Future<MediaItem> insert(String id, {bool hidden = false}) {
      final item = MediaItem(
        id: id,
        title: 'video-$id',
        uri: 'file:///data/$id.mp4',
        type: MediaItemType.local,
      )..isHidden = hidden;
      return library.upsert(item);
    }

    test('hidden rows are excluded from every default query', () async {
      await insert('a');
      await insert('b', hidden: true);
      await insert('c');

      final visible = await library.query(const LibraryQuery());
      expect(visible.map((m) => m.id), unorderedEquals(['a', 'c']));

      final searched = await library.query(const LibraryQuery(search: 'video'));
      expect(searched, hasLength(2));

      expect(await library.countByType(MediaItemType.local), 2);
    });

    test('includeHidden opts back in (backup / vault paths)', () async {
      await insert('a');
      await insert('b', hidden: true);
      final all = await library
          .query(const LibraryQuery(limit: 100000, includeHidden: true));
      expect(all.length, 2);
    });

    test('setHidden round-trip + vaultItems + hiddenCount', () async {
      await insert('a');
      await insert('b');

      await library.setHidden('a', true);
      expect((await library.query(const LibraryQuery())).map((m) => m.id),
          unorderedEquals(['b']));
      expect(await library.hiddenCount(), 1);

      final vault = await library.vaultItems();
      expect(vault.map((m) => m.id), ['a']);
      expect(vault.first.isHidden, isTrue);

      await library.setHidden('a', false);
      expect(await library.hiddenCount(), 0);
      expect((await library.query(const LibraryQuery())).length, 2);
    });

    test('rescan upsert preserves the hidden flag (same id, same uri)',
        () async {
      await insert('a');
      await library.setHidden('a', true);

      // A device rescan re-inserts the same row with the flag reset.
      final rescanned = MediaItem(
        id: 'a',
        title: 'video-a (renamed)',
        uri: 'file:///data/a.mp4',
        type: MediaItemType.local,
        durationMs: 42000,
      );
      await library.upsert(rescanned);
      expect(rescanned.isHidden, isTrue); // carried over in memory too

      final visible = await library.query(const LibraryQuery());
      expect(visible, isEmpty);
      expect(await library.hiddenCount(), 1);
    });

    test('hidden favorites do not leak into countFavorites', () async {
      final item = await insert('a');
      await library.setFavorite(item.id, true);
      await library.setHidden('a', true);
      expect(await library.countFavorites(), 0);
    });

    test('backup payload round-trips the hidden flag', () async {
      // The backup collector uses includeHidden:true and plain toMap();
      // restore goes through MediaItem.fromMap + upsert. Verify the full
      // map path keeps the flag.
      await insert('a');
      await library.setHidden('a', true);

      final collected = await library
          .query(const LibraryQuery(limit: 100000, includeHidden: true));
      expect(collected.single.id, 'a');

      // Simulate restore on a fresh DB state (delete + merge back).
      await db.deleteAllData();
      await library.upsert(MediaItem.fromMap(collected.single.toMap()));
      expect(await library.hiddenCount(), 1);
      expect((await library.vaultItems()).single.title, 'video-a');
    });
  });

  // =====================================================================
  // VaultController (v1.10.0)
  // =====================================================================
  group('VaultController', () {
    test('without a PIN: needsSetup, unlock is a no-op success', () {
      final c = VaultController(storedHash: null);
      expect(c.needsSetup, isTrue);
      expect(c.hasPin, isFalse);
      expect(c.unlock('0000'), UnlockResult.success);
      expect(c.isUnlocked, isFalse); // no PIN = never "unlocked"
    });

    test('setPin opens the vault and persists a verifiable hash', () {
      final c = VaultController(storedHash: null);
      final packed = c.setPin('1357');
      expect(packed, isNotNull);
      expect(c.hasPin, isTrue);
      expect(c.isUnlocked, isTrue);
      expect(PinHasher.verify('1357', packed!), isTrue);
      expect(PinHasher.verify('1358', packed), isFalse);
    });

    test('setPin rejects short / non-numeric PINs', () {
      final c = VaultController(storedHash: null);
      expect(c.setPin('123'), isNull);
      expect(c.setPin('abcd'), isNull);
      expect(c.setPin(''), isNull);
    });

    test('unlock success / wrong pin / lockout after 5 with fake clock',
        () {
      var now = DateTime(2026, 1, 1, 12);
      final c = VaultController(
        storedHash: PinHasher.pack(PinHasher.newSalt(),
            PinHasher.hash('9999', PinHasher.newSalt())),
        clock: () => now,
      );
      // Fix the stored hash properly (salt must match the hash):
      final salt = PinHasher.newSalt();
      c.restore(PinHasher.pack(salt, PinHasher.hash('9999', salt)));

      for (var i = 0; i < 4; i++) {
        expect(c.unlock('0000'), UnlockResult.wrongPin);
      }
      expect(c.isLockedOut, isFalse);
      expect(c.unlock('0000'), UnlockResult.wrongPin);
      expect(c.isLockedOut, isTrue);

      // Locked out even with the right PIN.
      expect(c.unlock('9999'), UnlockResult.lockedOut);

      // 29s later: still locked. 31s later: free to try again.
      now = now.add(const Duration(seconds: 29));
      expect(c.lockoutRemaining, isNotNull);
      now = now.add(const Duration(seconds: 2));
      expect(c.lockoutRemaining, isNull);
      expect(c.unlock('9999'), UnlockResult.success);
      expect(c.isUnlocked, isTrue);
    });

    test('lock() re-locks a session; restore() re-gates', () {
      final salt = PinHasher.newSalt();
      final stored = PinHasher.pack(salt, PinHasher.hash('1234', salt));
      final c = VaultController(storedHash: stored);
      expect(c.unlock('1234'), UnlockResult.success);
      c.lock();
      expect(c.isUnlocked, isFalse);
      expect(c.unlock('1234'), UnlockResult.success);

      c.restore(stored);
      expect(c.isUnlocked, isFalse);
    });

    test('changePin verifies the current PIN', () {
      final salt = PinHasher.newSalt();
      final c = VaultController(
          storedHash: PinHasher.pack(salt, PinHasher.hash('1111', salt)));
      expect(c.changePin('wrong', '2222'), isNull);
      final packed = c.changePin('1111', '2222');
      expect(packed, isNotNull);
      expect(PinHasher.verify('2222', packed!), isTrue);
    });

    test('removePin verifies then disables the gate', () {
      final salt = PinHasher.newSalt();
      final c = VaultController(
          storedHash: PinHasher.pack(salt, PinHasher.hash('1111', salt)));
      expect(c.removePin('0000'), isFalse);
      expect(c.removePin('1111'), isTrue);
      expect(c.hasPin, isFalse);
      expect(c.needsSetup, isTrue);
    });
  });

  // =====================================================================
  // SecureFlagKeeper (v1.10.0) — ref-counted FLAG_SECURE
  // =====================================================================
  group('SecureFlagKeeper', () {
    test('flag stays on while any holder remains', () async {
      final calls = <bool>[];
      SecureFlagKeeper.holders.clear();
      SecureFlagKeeper.apply = (secure) async => calls.add(secure);

      await SecureFlagKeeper.acquire('vault');
      await SecureFlagKeeper.acquire('player:x');
      await SecureFlagKeeper.release('vault');
      expect(calls, [true, true, true]); // player still holds it

      await SecureFlagKeeper.release('player:x');
      expect(calls, [true, true, true, false]);
    });

    test('releasing an unknown holder clears the flag honestly', () async {
      final calls = <bool>[];
      SecureFlagKeeper.holders.clear();
      SecureFlagKeeper.apply = (secure) async => calls.add(secure);
      await SecureFlagKeeper.release('ghost');
      expect(calls, [false]);
    });

    test('releaseAll drops everything', () async {
      final calls = <bool>[];
      SecureFlagKeeper.holders.clear();
      SecureFlagKeeper.apply = (secure) async => calls.add(secure);
      await SecureFlagKeeper.acquire('a');
      await SecureFlagKeeper.acquire('b');
      await SecureFlagKeeper.releaseAll();
      expect(calls, [true, true, false]);
      expect(SecureFlagKeeper.holders, isEmpty);
    });
  });

  // =====================================================================
  // SubtitleCharset (v1.10.0) — tables verified against Python codecs
  // =====================================================================
  group('SubtitleCharset decode', () {
    // Generated with scripts/gen_charset_tables.py (Windows-1256 codec).
    test('windows-1256 decodes Arabic correctly', () {
      final bytes = hex('e3d1cdc8c7'); // مرحبا
      expect(
        SubtitleCharset.decode(bytes, encoding: SubtitleEncoding.windows1256),
        'مرحبا',
      );
    });

    test('iso-8859-6 decodes Arabic correctly', () {
      final bytes = hex('c7e4d3e4c7e520d9e4eae3e520e8d1cde5c920c7e4e4e720'
          'e8c8d1e3c7cae7'); // السلام عليكم ورحمة الله وبركاته
      expect(
        SubtitleCharset.decode(bytes, encoding: SubtitleEncoding.iso8859_6),
        'السلام عليكم ورحمة الله وبركاته',
      );
    });

    test('utf-8 decodes as-is', () {
      final bytes = utf8.encode('مرحبا بالعالم');
      expect(SubtitleCharset.decode(bytes, encoding: SubtitleEncoding.utf8),
          'مرحبا بالعالم');
    });

    test('undefined bytes degrade to replacement, never throw', () {
      // 0xA1-0xA3 are undefined in ISO-8859-6.
      final out = SubtitleCharset.decode(
        [0x41, 0xA1, 0x42],
        encoding: SubtitleEncoding.iso8859_6,
      );
      expect(out.codeUnits.contains(0xFFFD), isTrue);
    });

    test('empty input decodes to empty', () {
      expect(SubtitleCharset.decode(const []), '');
    });

    test('encoding ids round-trip', () {
      for (final e in SubtitleEncoding.values) {
        expect(SubtitleEncoding.fromId(e.id), e);
      }
      expect(SubtitleEncoding.fromId('nonsense'), SubtitleEncoding.auto);
    });
  });

  group('SubtitleCharset.detect', () {
    test('BOM and strict UTF-8 win immediately', () {
      expect(SubtitleCharset.detect(utf8.encode('مرحبا بالعالم')),
          SubtitleEncoding.utf8);
      expect(
          SubtitleCharset.detect(
              [0xEF, 0xBB, 0xBF, ...ascii.encode('plain english text')]),
          SubtitleEncoding.utf8);
      expect(SubtitleCharset.detect(
              ascii.encode('1\n00:00:01,000 --> 00:00:02,000\nHello world\n')),
          SubtitleEncoding.utf8);
    });

    test('windows-1256 Arabic payloads detect as windows-1256', () {
      // مرحبا / punct sample / الحلقة 12 - الجزء 2
      expect(SubtitleCharset.detect(hex('e3d1cdc8c7')),
          SubtitleEncoding.windows1256);
      expect(
          SubtitleCharset.detect(
              hex('dec7e1ba20e5e120d3e3dacabf20e4dae3a120c3dfedcf')),
          SubtitleEncoding.windows1256);
      expect(
          SubtitleCharset.detect(hex(
              'c7e1cde1dec9203132202d20c7e1ccd2c12032')),
          SubtitleEncoding.windows1256);
    });

    test('iso-8859-6 payloads detect as iso-8859-6', () {
      // Same phrase encoded with ISO-8859-6: the correct decode yields
      // common letters, the windows-1256 misread yields rare ones.
      expect(
          SubtitleCharset.detect(hex(
              'c7e4d3e4c7e520d9e4eae3e520e8d1cde5c920c7e4e4e720e8c8d1e3c7cae7')),
          SubtitleEncoding.iso8859_6);
    });

    test('legacy Latin text falls back to windows-1252', () {
      // "café naïve — résumé" in windows-1252: accented vowels misread
      // through the Arabic tables score far below real Arabic prose.
      expect(SubtitleCharset.detect(hex('636166e9206e61ef766520972072e973756de9')),
          SubtitleEncoding.windows1252);
      // Pure ASCII that is NOT valid UTF-8 structure is impossible — ASCII
      // always validates, so this branch is only about non-Arabic 8-bit.
    });

    test('empty bytes default to utf8', () {
      expect(SubtitleCharset.detect(const []), SubtitleEncoding.utf8);
    });
  });

  group('subtitle pipeline', () {
    test('cp1256 SRT: decode → parse yields real Arabic cues', () {
      final text = SubtitleCharset.decode(
        hex('31 0a 30 30 3a 30 30 3a 30 31 2c 30 30 30 20 2d 2d 3e 20'
            '30 30 3a 30 30 3a 30 33 2c 35 30 30 0a e3 d1 cd c8 c7'),
        encoding: SubtitleEncoding.windows1256,
      );
      final cues = SubtitleParser.parse(text);
      expect(cues, hasLength(1));
      expect(cues.first.startMs, 1000);
      expect(cues.first.endMs, 3500);
      expect(cues.first.text, 'مرحبا');
    });

    test('auto-detect + parse on the same bytes', () {
      final bytes = hex('31 0a 30 30 3a 30 30 3a 30 31 2c 30 30 30 20 2d 2d'
          '3e 20 30 30 3a 30 30 3a 30 33 2c 35 30 30 0a e3 d1 cd c8 c7');
      final text = SubtitleCharset.decode(bytes); // encoding: auto
      expect(SubtitleParser.parse(text).first.text, 'مرحبا');
    });

    test('garbage input throws FormatException (honest validation)', () {
      expect(() => SubtitleParser.parse('not a subtitle'), throwsFormatException);
      expect(
          () => SubtitleParser.parse(
              SubtitleCharset.decode(utf8.encode('no cues here'))),
          throwsFormatException);
    });
  });

  // =====================================================================
  // Preferences glue (per-media delay + audio-only default)
  // =====================================================================
  group('v1.10.0 preferences', () {
    test('per-media subtitle delay persists and clears', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(await SharedPreferences.getInstance());

      expect(prefs.subtitleDelayFor('m1'), isNull);
      await prefs.setSubtitleDelayFor('m1', 2.5);
      expect(prefs.subtitleDelayFor('m1'), 2.5);
      await prefs.setSubtitleDelayFor('m1', -99);
      expect(prefs.subtitleDelayFor('m1'), -60.0); // clamped
      await prefs.setSubtitleDelayFor('m1', 99);
      expect(prefs.subtitleDelayFor('m1'), 60.0);

      await prefs.clearSubtitleDelayFor('m1');
      expect(prefs.subtitleDelayFor('m1'), isNull);
    });

    test('audio-only default persists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(await SharedPreferences.getInstance());
      expect(prefs.audioOnlyDefault, isFalse);
      prefs.audioOnlyDefault = true;
      expect(prefs.audioOnlyDefault, isTrue);
    });

    test('vault hash persists in prefs (excluded keys untouched)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PreferencesService(await SharedPreferences.getInstance());
      expect(prefs.vaultHash, isNull);
      prefs.vaultHash = 'aa:bb';
      expect(prefs.vaultHash, 'aa:bb');
      prefs.vaultHash = null;
      expect(prefs.vaultHash, isNull);
    });
  });
}

List<int> hex(String src) {
  final clean = src.replaceAll(RegExp(r'\s+'), '');
  final out = <int>[];
  for (var i = 0; i + 1 < clean.length; i += 2) {
    out.add(int.parse(clean.substring(i, i + 2), radix: 16));
  }
  return out;
}
