import 'package:flutter/foundation.dart';
import '../core/errors/app_exception.dart';
import '../core/network/dio_client.dart';
import '../core/utils/logger.dart';
import '../core/utils/validators.dart';
import '../data/models/playlist.dart';
import '../data/repositories/source_repository.dart';

/// Manages user-registered sources (named direct-URL adapters).
class SourcesController extends ChangeNotifier {
  SourcesController({required SourceRepository repo}) : _repo = repo;

  final SourceRepository _repo;

  List<SourceInfo> sources = [];
  bool loading = false;
  bool testing = false;
  String? testResult; // 'ok' | error message key

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      sources = await _repo.list();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> add({
    required String name,
    required String baseUrl,
    String? headerName,
    String? headerValue,
  }) async {
    if (!Validators.isValidVideoUrl(baseUrl)) {
      throw const AppException(AppErrorType.invalidInput);
    }
    final source = SourceInfo(
      id: 'src_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: name.trim().isEmpty ? Validators.titleFromUrl(baseUrl) : name.trim(),
      baseUrl: baseUrl.trim(),
      headerName: (headerName?.trim().isEmpty ?? true) ? null : headerName!.trim(),
      headerValue: (headerValue?.trim().isEmpty ?? true) ? null : headerValue!.trim(),
    );
    await _repo.insert(source);
    await load();
  }

  Future<void> toggle(String id, bool enabled) async {
    await _repo.setEnabled(id, enabled);
    await load();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await load();
  }

  /// Real connectivity probe (HEAD with 15s timeout + retry).
  Future<bool> testConnection(String url) async {
    testing = true;
    testResult = null;
    notifyListeners();
    try {
      final res = await DioClient.instance.head(url);
      testResult = res.statusCode != null && res.statusCode! < 400 ? 'ok' : 'fail';
      return testResult == 'ok';
    } on AppException catch (e) {
      testResult = e.type.name;
      return false;
    } catch (e) {
      AppLogger.instance.warning('sources', 'test failed: $e');
      testResult = 'fail';
      return false;
    } finally {
      testing = false;
      notifyListeners();
    }
  }

  /// Headers for a given registered source, used by playback/download.
  Map<String, String>? headersFor(String? sourceId) {
    if (sourceId == null) return null;
    for (final s in sources) {
      if (s.id == sourceId && s.headerName != null && s.headerValue != null) {
        return {s.headerName!: s.headerValue!};
      }
    }
    return null;
  }
}
