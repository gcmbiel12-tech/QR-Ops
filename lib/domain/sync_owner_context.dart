/// Mutable session identity shared by local repositories and the sync runtime.
/// The local store remains usable when [userId] is null.
class SyncOwnerContext {
  String? _userId;

  String? get userId => _userId;

  void update(String? userId) {
    final normalized = userId?.trim();
    _userId = normalized == null || normalized.isEmpty ? null : normalized;
  }
}
