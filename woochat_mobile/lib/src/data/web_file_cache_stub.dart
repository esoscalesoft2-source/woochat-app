/// Not the web: files go to disk, and this is never used.
class WebFileCache {
  const WebFileCache();

  Future<bool> has(String url) async => false;
  Future<void> put(String url) async {}
  Future<bool> open(String url) async => false;
  Future<int> totalBytes() async => 0;
  Future<void> clear() async {}
}
