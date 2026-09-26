import 'package:sqflite/sqflite.dart';
import '../../core/storage/database_service.dart';
import '../models/download_task.dart';

/// Persistence for the download queue.
class DownloadRepository {
  DownloadRepository(this._db);

  final DatabaseService _db;

  Future<void> insert(DownloadTaskModel t) async {
    final database = await _db.database;
    await database.insert('downloads', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(DownloadTaskModel t) => insert(t);

  Future<List<DownloadTaskModel>> all() async {
    final database = await _db.database;
    final rows = await database.query('downloads', orderBy: 'created_at DESC');
    return rows.map(DownloadTaskModel.fromMap).toList();
  }

  Future<DownloadTaskModel?> byTaskId(String taskId) async {
    final database = await _db.database;
    final rows = await database
        .query('downloads', where: 'task_id = ?', whereArgs: [taskId], limit: 1);
    return rows.isEmpty ? null : DownloadTaskModel.fromMap(rows.first);
  }

  Future<DownloadTaskModel?> byId(String id) async {
    final database = await _db.database;
    final rows = await database
        .query('downloads', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : DownloadTaskModel.fromMap(rows.first);
  }

  Future<void> delete(String id, {bool deleteContentRow = true}) async {
    final database = await _db.database;
    await database.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearFinished() async {
    final database = await _db.database;
    await database
        .delete('downloads', where: "status IN ('completed','failed','cancelled')");
  }
}
