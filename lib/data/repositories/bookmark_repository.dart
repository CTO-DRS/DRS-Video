import 'package:sqflite/sqflite.dart';
import '../../core/storage/database_service.dart';

/// A saved position inside a video (v1.1.0). Loose item reference: the
/// media item may not exist in the local database (e.g. transient URLs),
/// so no FK constraint — bookmarks survive independently.
class VideoBookmark {
  VideoBookmark({
    this.id,
    required this.itemId,
    required this.positionMs,
    this.label,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final String itemId;
  final int positionMs;
  final String? label;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'item_id': itemId,
        'position_ms': positionMs,
        'label': label,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static VideoBookmark fromMap(Map<String, Object?> m) => VideoBookmark(
        id: m['id'] as int?,
        itemId: m['item_id'] as String,
        positionMs: m['position_ms'] as int,
        label: m['label'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

/// CRUD for [VideoBookmark]s.
class BookmarkRepository {
  BookmarkRepository(this._db);

  final DatabaseService _db;

  Future<int> add(VideoBookmark b) async {
    final database = await _db.database;
    return database.insert('video_bookmarks', b.toMap());
  }

  Future<List<VideoBookmark>> forItem(String itemId) async {
    final database = await _db.database;
    final rows = await database.query('video_bookmarks',
        where: 'item_id = ?',
        whereArgs: [itemId],
        orderBy: 'position_ms ASC');
    return rows.map(VideoBookmark.fromMap).toList();
  }

  Future<List<VideoBookmark>> all() async {
    final database = await _db.database;
    final rows = await database
        .query('video_bookmarks', orderBy: 'created_at DESC');
    return rows.map(VideoBookmark.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database
        .delete('video_bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteForItem(String itemId) async {
    final database = await _db.database;
    await database.delete('video_bookmarks',
        where: 'item_id = ?', whereArgs: [itemId]);
  }

  Future<void> upsertAll(List<VideoBookmark> bookmarks) async {
    if (bookmarks.isEmpty) return;
    final database = await _db.database;
    final batch = database.batch();
    for (final b in bookmarks) {
      batch.insert('video_bookmarks', b.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
