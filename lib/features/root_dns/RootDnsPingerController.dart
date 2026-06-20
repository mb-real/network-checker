class RootDnsPingerController extends ChangeNotifier {
  // ... سایر کدها ...

  Future<void> pingRootServers() async { /* ... */ }
  void stopPinging() { /* ... */ }
  Future<void> pingSingle({required RootDnsPingResult result}) async { /* ... */ }
  void reset() { /* ... */ }
  bool get isPinging => _state == RootDnsPingerState.pinging;
  bool get isLoading => _state == RootDnsPingerState.loading;
  List<RootDnsPingResult> get results => _results;
}
