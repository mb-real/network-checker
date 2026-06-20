import 'package:flutter/foundation.dart';
import '../../core/services/root_dns_pinger.dart';

/// State for the Root DNS Pinger feature
enum RootDnsPingerState {
  idle,
  pinging,
  completed,
  error,
}

class RootDnsPingerController extends ChangeNotifier {
  // State
  RootDnsPingerState _state = RootDnsPingerState.idle;
  String? _errorMessage;
  
  // Results
  List<RootDnsPingResult> _results = [];
  
  // Control
  bool _stopRequested = false;
  
  // Getters
  RootDnsPingerState get state => _state;
  String? get errorMessage => _errorMessage;
  List<RootDnsPingResult> get results => _results;
  bool get isPinging => _state == RootDnsPingerState.pinging;
  bool get isLoading => _state == RootDnsPingerState.pinging || _state == RootDnsPingerState.idle && _results.isEmpty;
  bool get isCompleted => _state == RootDnsPingerState.completed;
  
  /// Get reachable servers (sorted by latency)
  List<RootDnsPingResult> get reachableServers {
    final reachable = _results.where((r) => r.isReachable).toList();
    reachable.sort((a, b) {
      if (a.latencyMs == null && b.latencyMs == null) return 0;
      if (a.latencyMs == null) return 1;
      if (b.latencyMs == null) return -1;
      return a.latencyMs!.compareTo(b.latencyMs!);
    });
    return reachable;
  }
  
  /// Get unreachable servers
  List<RootDnsPingResult> get unreachableServers {
    return _results.where((r) => !r.isReachable).toList();
  }
  
  /// Get the fastest reachable server
  RootDnsPingResult? get fastestServer {
    final reachable = reachableServers;
    return reachable.isNotEmpty ? reachable.first : null;
  }
  
  /// Get summary statistics
  Map<String, dynamic> get summary {
    final total = _results.length;
    final reachable = reachableServers.length;
    final unreachable = total - reachable;
    final avgLatency = reachableServers
        .where((r) => r.latencyMs != null)
        .map((r) => r.latencyMs!)
        .fold<double>(0, (sum, latency) => sum + latency) / 
        (reachableServers.where((r) => r.latencyMs != null).length);
    
    return {
      'total': total,
      'reachable': reachable,
      'unreachable': unreachable,
      'avgLatency': avgLatency.isNaN ? null : avgLatency,
    };
  }
  
  /// Ping all root DNS servers
  Future<void> pingRootServers() async {
    if (_state == RootDnsPingerState.pinging) return;
    
    _state = RootDnsPingerState.pinging;
    _stopRequested = false;
    _errorMessage = null;
    _results.clear();
    notifyListeners();
    
    try {
      // Use the service to ping all servers
      final pingResults = await RootDnsPinger.pingAllRootServers(
        timeout: RootDnsPinger.defaultTimeout,
        concurrency: RootDnsPinger.defaultConcurrency,
      );
      
      // Check if stop was requested during the operation
      if (_stopRequested) {
        _state = RootDnsPingerState.idle;
        notifyListeners();
        return;
      }
      
      _results = pingResults;
      _state = RootDnsPingerState.completed;
      notifyListeners();
    } catch (e) {
      _state = RootDnsPingerState.error;
      _errorMessage = 'Error pinging root servers: $e';
      notifyListeners();
    }
  }
  
  /// Ping a single root DNS server
  Future<void> pingSingle({required RootDnsPingResult result}) async {
    if (_state == RootDnsPingerState.pinging) return;
    
    // Remove the old result if it exists
    _results.removeWhere((r) => r.name == result.name);
    
    // Add a temporary loading state (we'll use the same object but mark as not reachable)
    final tempResult = RootDnsPingResult(
      name: result.name,
      ip: result.ip,
      isReachable: false,
      latencyMs: null,
      error: 'Checking...',
    );
    _results.add(tempResult);
    notifyListeners();
    
    try {
      // Use the service to ping a single server
      final pingResult = await RootDnsPinger.pingRootServer(
        result.name,
        result.ip,
        timeout: RootDnsPinger.defaultTimeout,
      );
      
      // Replace the temporary result with the actual one
      final index = _results.indexWhere((r) => r.name == result.name);
      if (index != -1) {
        _results[index] = pingResult;
      } else {
        _results.add(pingResult);
      }
      
      // Sort results by latency
      _results.sort((a, b) {
        if (a.latencyMs == null && b.latencyMs == null) return 0;
        if (a.latencyMs == null) return 1;
        if (b.latencyMs == null) return -1;
        return a.latencyMs!.compareTo(b.latencyMs!);
      });
      
      notifyListeners();
    } catch (e) {
      // Update the result with error
      final index = _results.indexWhere((r) => r.name == result.name);
      if (index != -1) {
        _results[index] = RootDnsPingResult(
          name: result.name,
          ip: result.ip,
          isReachable: false,
          error: 'Error: $e',
        );
        notifyListeners();
      }
    }
  }
  
  /// Find the fastest root DNS server
  Future<RootDnsPingResult?> findFastest() async {
    if (_state == RootDnsPingerState.pinging) return null;
    
    try {
      // Use the service to find the fastest server
      final fastest = await RootDnsPinger.findFastestRoot(
        timeout: RootDnsPinger.defaultTimeout,
      );
      
      if (fastest != null) {
        // Update or add the result
        final index = _results.indexWhere((r) => r.name == fastest.name);
        if (index != -1) {
          _results[index] = fastest;
        } else {
          _results.add(fastest);
        }
        notifyListeners();
      }
      
      return fastest;
    } catch (e) {
      _state = RootDnsPingerState.error;
      _errorMessage = 'Error finding fastest server: $e';
      notifyListeners();
      return null;
    }
  }
  
  /// Stop the current ping operation
  void stopPinging() {
    _stopRequested = true;
    _state = RootDnsPingerState.idle;
    notifyListeners();
  }
  
  /// Reset to initial state
  void reset() {
    _state = RootDnsPingerState.idle;
    _errorMessage = null;
    _results.clear();
    _stopRequested = false;
    notifyListeners();
  }
  
  /// Clear only results (keep state)
  void clearResults() {
    _results.clear();
    if (_state != RootDnsPingerState.pinging) {
      _state = RootDnsPingerState.idle;
    }
    notifyListeners();
  }
}
