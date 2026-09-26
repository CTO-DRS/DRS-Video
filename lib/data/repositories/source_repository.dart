import 'package:sqflite/sqflite.dart';
import '../../core/storage/database_service.dart';
import '../models/playlist.dart';

/// CRUD for user-registered sources.
class SourceRepository {
  SourceRepository(this._db);

  final DatabaseService _db;

  Future<List<SourceInfo>> list() async {
    final database = await _db.database;
    final rows = await database.query('sources', orderBy: 'created_at DESC');
    return rows.map(SourceInfo.fromMap).toList();
  }

  Future<void> insert(SourceInfo s) async {
    final database = await _db.database;
    await database.insert('sources', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final database = await _db.database;
    await database
        .update('sources', {'enabled': enabled ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final database = await _db.database;
    await database.delete('sources', where: 'id = ?', whereArgs: [id]);
  }
}
