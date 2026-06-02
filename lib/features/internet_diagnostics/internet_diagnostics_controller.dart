import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/services/internet_diagnostics_service.dart';
import '../../core/services/cdn_ips.dart';

/// Current state status of the diagnostic engine
enum DiagnosticEngineStatus { idle, running, completed }

/// Controller that coordinates executing tests and updating diagnostic UI states.
class InternetDiagnosticsController extends ChangeNotifier {
  DiagnosticEngineStatus _engineStatus = DiagnosticEngineStatus.idle;
  int _currentRunId = 0;

  // Track status of individual checks
  bool _dnsSuccess = false;
  bool _ipv4Success = false;
  bool _ipv6Success = false;
  bool _httpsSuccess = false;
  bool _dnsAnalysisSuccess = false;
  bool _tlsAnalysisSuccess = false;
  bool _domesticIpSuccess = false;
  bool _internationalIpSuccess = false;
  bool _overallInternetAccess = false;

  // Hold detailed results
  DiagnosticTestResult? _dnsResult;
  DiagnosticTestResult? _ipv4Result;
  DiagnosticTestResult? _ipv6Result;
  DiagnosticTestResult? _httpsResult;
  DnsAnalysisSummary? _dnsAnalysisSummary;
  TlsAnalysisSummary? _tlsAnalysisSummary;
  DiagnosticTestResult? _domesticIpResult;
  DiagnosticTestResult? _internationalIpResult;
  DiagnosticTestResult? _routingAnalysisResult;

  // Website Reachability State
  List<WebsiteReachabilityResult> _websiteResults = [];
  bool _isScanningWebsites = false;

  // CDN Reachability State
  List<WebsiteReachabilityResult> _cdnResults = [];
  bool _isScanningCdns = false;

  // TLS / HTTPS Analysis State
  bool _isScanningTlsTargets = false;

  // Social Media Reachability State
  List<SocialMediaResult> _socialMediaResults = [];
  bool _isScanningSocialMedia = false;

  // List of major targets to verify
  static const List<Map<String, String>> targetWebsites = [
    {'name': 'Google', 'domain': 'www.google.com'},
    {'name': 'YouTube', 'domain': 'www.youtube.com'},
    {'name': 'GitHub', 'domain': 'github.com'},
    {'name': 'Wikipedia', 'domain': 'wikipedia.org'},
    {'name': 'Reddit', 'domain': 'www.reddit.com'},
    {'name': 'Stack Overflow', 'domain': 'stackoverflow.com'},
    {'name': 'ChatGPT', 'domain': 'chatgpt.com'},
    {'name': 'Claude', 'domain': 'claude.ai'},
    {'name': 'Gemini', 'domain': 'gemini.google.com'},
  ];

  // List of CDN targets to verify
  static const List<Map<String, dynamic>> targetCdns = [
    {
      'name': 'Cloudflare',
      'domain': 'cloudflare.com',
      'ips': cloudflareIps,
    },
    {
      'name': 'Akamai',
      'domain': 'akamai.com',
      'ips': akamaiIps,
    },
    {
      'name': 'Fastly',
      'domain': 'fastly.com',
      'ips': fastlyIps,
    },
    {
      'name': 'AWS CloudFront',
      'domain': 'aws.amazon.com',
      'ips': cloudfrontIps,
    },
    {
      'name': 'Azure CDN',
      'domain': 'azure.microsoft.com',
      'ips': azureIps,
    },
    {
      'name': 'Google CDN',
      'domain': 'cloud.google.com',
      'ips': googleIps,
    },
  ];

  // List of social media targets to verify
  static const List<Map<String, String>> targetSocialMedia = [
    {
      'name': 'Telegram',
      'primary': 'telegram.org',
      'secondary': 'api.telegram.org',
    },
    {
      'name': 'WhatsApp',
      'primary': 'web.whatsapp.com',
      'secondary': 'graph.whatsapp.com',
    },
    {
      'name': 'Discord',
      'primary': 'discord.com',
      'secondary': 'gateway.discord.gg',
    },
    {
      'name': 'Instagram',
      'primary': 'instagram.com',
      'secondary': 'scontent.cdninstagram.com',
    },
    {'name': 'X (Twitter)', 'primary': 'x.com', 'secondary': 'api.x.com'},
    {
      'name': 'Facebook',
      'primary': 'facebook.com',
      'secondary': 'graph.facebook.com',
    },
    {'name': 'TikTok', 'primary': 'tiktok.com', 'secondary': 'api.tiktokv.com'},
    {
      'name': 'Snapchat',
      'primary': 'snapchat.com',
      'secondary': 'aws.api.snapchat.com',
    },
    {'name': 'Signal', 'primary': 'signal.org', 'secondary': 'chat.signal.org'},
  ];

  // Track progress
  int _completedTestsCount = 0;
  static const int totalTestsCount = 11; // 11 progressive sequence tasks

  // Getters
  DiagnosticEngineStatus get engineStatus => _engineStatus;
  bool get dnsSuccess => _dnsSuccess;
  bool get ipv4Success => _ipv4Success;
  bool get ipv6Success => _ipv6Success;
  bool get httpsSuccess => _httpsSuccess;
  bool get dnsAnalysisSuccess => _dnsAnalysisSuccess;
  bool get tlsAnalysisSuccess => _tlsAnalysisSuccess;
  bool get domesticIpSuccess => _domesticIpSuccess;
  bool get internationalIpSuccess => _internationalIpSuccess;
  bool get overallInternetAccess => _overallInternetAccess;

  DiagnosticTestResult? get dnsResult => _dnsResult;
  DiagnosticTestResult? get ipv4Result => _ipv4Result;
  DiagnosticTestResult? get ipv6Result => _ipv6Result;
  DiagnosticTestResult? get httpsResult => _httpsResult;
  DnsAnalysisSummary? get dnsAnalysisSummary => _dnsAnalysisSummary;
  TlsAnalysisSummary? get tlsAnalysisSummary => _tlsAnalysisSummary;
  DiagnosticTestResult? get domesticIpResult => _domesticIpResult;
  DiagnosticTestResult? get internationalIpResult => _internationalIpResult;
  DiagnosticTestResult? get routingAnalysisResult => _routingAnalysisResult;

  List<WebsiteReachabilityResult> get websiteResults => _websiteResults;
  bool get isScanningWebsites => _isScanningWebsites;
  bool get isScanningTlsTargets => _isScanningTlsTargets;

  List<WebsiteReachabilityResult> get cdnResults => _cdnResults;
  bool get isScanningCdns => _isScanningCdns;

  List<SocialMediaResult> get socialMediaResults => _socialMediaResults;
  bool get isScanningSocialMedia => _isScanningSocialMedia;

  int get completedTestsCount => _completedTestsCount;
  double get progressFraction => _completedTestsCount / totalTestsCount;

  bool get isIdle => _engineStatus == DiagnosticEngineStatus.idle;
  bool get isRunning => _engineStatus == DiagnosticEngineStatus.running;
  bool get isCompleted => _engineStatus == DiagnosticEngineStatus.completed;

  // Website reachability summary statistics
  int get reachableWebsitesCount => _websiteResults
      .where((w) => w.status == ReachabilityStatus.reachable)
      .length;

  int get blockedWebsitesCount => _websiteResults
      .where((w) => w.status == ReachabilityStatus.blocked)
      .length;

  int get failedWebsitesCount => _websiteResults
      .where(
        (w) =>
            w.status == ReachabilityStatus.dnsFailure ||
            w.status == ReachabilityStatus.tlsFailure ||
            w.status == ReachabilityStatus.timeout,
      )
      .length;

  int get averageWebsiteLatencyMs {
    final latencies = _websiteResults
        .where(
          (w) =>
              w.latencyMs != null && w.status == ReachabilityStatus.reachable,
        )
        .map((w) => w.latencyMs!)
        .toList();
    if (latencies.isEmpty) return 0;
    final total = latencies.reduce((a, b) => a + b);
    return (total / latencies.length).round();
  }

  // CDN reachability summary statistics
  int get reachableCdnsCount => _cdnResults
      .where((w) => w.status == ReachabilityStatus.reachable)
      .length;

  int get blockedCdnsCount => _cdnResults
      .where((w) => w.status == ReachabilityStatus.blocked)
      .length;

  int get failedCdnsCount => _cdnResults
      .where(
        (w) =>
            w.status == ReachabilityStatus.dnsFailure ||
            w.status == ReachabilityStatus.tlsFailure ||
            w.status == ReachabilityStatus.timeout,
      )
      .length;

  int get averageCdnLatencyMs {
    final latencies = _cdnResults
        .where(
          (w) =>
              w.latencyMs != null && w.status == ReachabilityStatus.reachable,
        )
        .map((w) => w.latencyMs!)
        .toList();
    if (latencies.isEmpty) return 0;
    final total = latencies.reduce((a, b) => a + b);
    return (total / latencies.length).round();
  }

  int get tlsHandshakeSuccessCount =>
      _tlsAnalysisSummary?.successfulHandshakes ?? 0;

  int get tlsCertificateMismatchCount =>
      _tlsAnalysisSummary?.certificateMismatches ?? 0;

  int get tlsTraceMismatchCount => _tlsAnalysisSummary?.traceMismatches ?? 0;

  int get averageTlsHandshakeLatencyMs =>
      _tlsAnalysisSummary?.averageHandshakeLatencyMs ?? 0;

  // Social Media accessibility summary statistics
  int get accessibleSocialCount => _socialMediaResults
      .where((w) => w.status == SocialMediaStatus.accessible)
      .length;

  int get partialSocialCount => _socialMediaResults
      .where((w) => w.status == SocialMediaStatus.partial)
      .length;

  int get blockedSocialCount => _socialMediaResults
      .where((w) => w.status == SocialMediaStatus.blocked)
      .length;

  int get averageSocialLatencyMs {
    final latencies = _socialMediaResults
        .where(
          (w) => w.latencyMs != null && w.status != SocialMediaStatus.blocked,
        )
        .map((w) => w.latencyMs!)
        .toList();
    if (latencies.isEmpty) return 0;
    final total = latencies.reduce((a, b) => a + b);
    return (total / latencies.length).round();
  }

  /// Run all tests sequentially to create a gorgeous scanning effect in the UI
  Future<void> runDiagnosticsSuite() async {
    if (_engineStatus == DiagnosticEngineStatus.running) return;

    _currentRunId++;
    final runId = _currentRunId;

    _engineStatus = DiagnosticEngineStatus.running;
    _completedTestsCount = 0;

    _dnsSuccess = false;
    _ipv4Success = false;
    _ipv6Success = false;
    _httpsSuccess = false;
    _dnsAnalysisSuccess = false;
    _tlsAnalysisSuccess = false;
    _domesticIpSuccess = false;
    _internationalIpSuccess = false;
    _overallInternetAccess = false;

    _dnsResult = null;
    _ipv4Result = null;
    _ipv6Result = null;
    _httpsResult = null;
    _dnsAnalysisSummary = null;
    _tlsAnalysisSummary = null;
    _domesticIpResult = null;
    _internationalIpResult = null;
    _routingAnalysisResult = null;
    _websiteResults = [];
    _isScanningWebsites = false;
    _isScanningTlsTargets = false;
    _cdnResults = [];
    _isScanningCdns = false;
    _socialMediaResults = [];
    _isScanningSocialMedia = false;

    notifyListeners();

    // 1. DNS Resolution Test
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _dnsResult = await InternetDiagnosticsService.checkDnsResolution();
    if (runId != _currentRunId) return;
    _dnsSuccess = _dnsResult!.success;
    _completedTestsCount++;
    notifyListeners();

    // 2. IPv4 Connectivity Test
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _ipv4Result = await InternetDiagnosticsService.checkIpv4Connectivity();
    if (runId != _currentRunId) return;
    _ipv4Success = _ipv4Result!.success;
    _completedTestsCount++;
    notifyListeners();

    // 3. IPv6 Connectivity Test
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _ipv6Result = await InternetDiagnosticsService.checkIpv6Connectivity();
    if (runId != _currentRunId) return;
    _ipv6Success = _ipv6Result!.success;
    _completedTestsCount++;
    notifyListeners();

    // 4. HTTPS Traffic Test
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _httpsResult = await InternetDiagnosticsService.checkHttpsTraffic();
    if (runId != _currentRunId) return;
    _httpsSuccess = _httpsResult!.success;
    _completedTestsCount++;
    notifyListeners();

    // 5. DNS Provider Analysis
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _dnsAnalysisSummary =
        await InternetDiagnosticsService.analyzeDnsProviders();
    if (runId != _currentRunId) return;
    _dnsAnalysisSuccess = _dnsAnalysisSummary!.success;
    _completedTestsCount++;
    notifyListeners();

    // 6. Domestic IP Discovery Test
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _domesticIpResult = await InternetDiagnosticsService.fetchPublicIp(
      domestic: true,
    );
    if (runId != _currentRunId) return;
    _domesticIpSuccess = _domesticIpResult!.success;
    _completedTestsCount++;
    notifyListeners();

    // 7. International IP Discovery Test
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _internationalIpResult = await InternetDiagnosticsService.fetchPublicIp(
      domestic: false,
    );
    if (runId != _currentRunId) return;
    _internationalIpSuccess = _internationalIpResult!.success;
    _completedTestsCount++;
    notifyListeners();

    // 8. Perform IP Routing and Discrepancy Analysis
    _routingAnalysisResult = InternetDiagnosticsService.analyzePublicIps(
      domesticResult: _domesticIpResult!,
      internationalResult: _internationalIpResult!,
    );
    notifyListeners();

    // 9. TLS / HTTPS Analysis Step
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _isScanningTlsTargets = true;
    _completedTestsCount++;
    notifyListeners();

    final tlsSummary = await InternetDiagnosticsService.analyzeTlsTargets(
      publicIp:
          _extractRetrievedIp(_internationalIpResult) ??
          _extractRetrievedIp(_domesticIpResult),
    );
    if (runId != _currentRunId) return;
    _tlsAnalysisSummary = tlsSummary;
    _tlsAnalysisSuccess = _tlsAnalysisSummary!.success;
    _isScanningTlsTargets = false;
    notifyListeners();

    // 10. Website Reachability Scan Step
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _isScanningWebsites = true;
    _completedTestsCount++;
    notifyListeners();

    for (final target in targetWebsites) {
      if (runId != _currentRunId) return;
      final name = target['name']!;
      final domain = target['domain']!;

      final result = await InternetDiagnosticsService.testWebsiteReachability(
        name,
        domain,
      );
      if (runId != _currentRunId) return;
      _websiteResults.add(result);
      notifyListeners();

      // Subtle stagger delay between sequential checks to render scanning effect
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (runId != _currentRunId) return;
    }

    _isScanningWebsites = false;
    notifyListeners();

    // 10. CDN Reachability Scan Step
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _isScanningCdns = true;
    _completedTestsCount++;
    notifyListeners();

    for (final target in targetCdns) {
      if (runId != _currentRunId) return;
      final name = target['name']!;
      final domain = target['domain']!;
      final List<String> ips = target['ips'] as List<String>;

      // Pick a random list of 50 IPs from each CDN
      final random = Random();
      final List<String> shuffledIps = List<String>.from(ips)..shuffle(random);
      final List<String> selectedIps = shuffledIps.take(50).toList();

      final scanResult = await InternetDiagnosticsService.scanCdnIps(
        selectedIps,
        maxConcurrency: 50,
        timeout: const Duration(milliseconds: 500),
      );
      if (runId != _currentRunId) return;

      final isReachable = scanResult.reachable > 0;
      final accessibilityPercent = (scanResult.accessibilityRate * 100).toStringAsFixed(1);
      
      final detailsText = 'Edge IP Range Scan Results (Tested 50 Random IPs):\n'
          'Total tested random IPs: ${scanResult.totalTested}\n'
          'Reachable edge IPs: ${scanResult.reachable}\n'
          'Blocked/Offline IPs: ${scanResult.totalTested - scanResult.reachable}\n'
          'CDN Accessibility: $accessibilityPercent%\n'
          'Average Handshake Latency: ${scanResult.averageLatencyMs}ms\n\n'
          'Note: This test scanned 50 randomly selected IPs from the CDN\'s public ranges to determine edge network accessibility and performance.';

      final result = WebsiteReachabilityResult(
        name: name,
        domain: domain,
        status: isReachable ? ReachabilityStatus.reachable : ReachabilityStatus.blocked,
        latencyMs: scanResult.averageLatencyMs,
        errorDetails: detailsText,
        statusCode: isReachable ? 200 : null,
      );

      _cdnResults.add(result);
      notifyListeners();

      // Subtle stagger delay between sequential checks to render scanning effect
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (runId != _currentRunId) return;
    }

    _isScanningCdns = false;
    notifyListeners();

    // 11. Social Media Accessibility Scan Step
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (runId != _currentRunId) return;
    _isScanningSocialMedia = true;
    _completedTestsCount++;
    notifyListeners();

    for (final target in targetSocialMedia) {
      if (runId != _currentRunId) return;
      final name = target['name']!;
      final primary = target['primary']!;
      final secondary = target['secondary']!;

      final result =
          await InternetDiagnosticsService.testSocialMediaAccessibility(
            name: name,
            primaryDomain: primary,
            secondaryDomain: secondary,
          );
      if (runId != _currentRunId) return;
      _socialMediaResults.add(result);
      notifyListeners();

      // Subtle stagger delay between sequential checks to render scanning effect
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (runId != _currentRunId) return;
    }

    _isScanningSocialMedia = false;

    // Compute Overall Internet Access
    _overallInternetAccess =
        _dnsSuccess ||
        _ipv4Success ||
        _ipv6Success ||
        _httpsSuccess ||
        _dnsAnalysisSuccess ||
        _tlsAnalysisSuccess ||
        _domesticIpSuccess ||
        _internationalIpSuccess ||
        _websiteResults.any((w) => w.status == ReachabilityStatus.reachable) ||
        _cdnResults.any((c) => c.status == ReachabilityStatus.reachable) ||
        _socialMediaResults.any(
          (s) =>
              s.status == SocialMediaStatus.accessible ||
              s.status == SocialMediaStatus.partial,
        );

    _engineStatus = DiagnosticEngineStatus.completed;
    notifyListeners();
  }

  /// Reset the engine state
  void resetSuite() {
    _currentRunId++; // Increment to cancel any active runs
    _engineStatus = DiagnosticEngineStatus.idle;
    _completedTestsCount = 0;

    _dnsSuccess = false;
    _ipv4Success = false;
    _ipv6Success = false;
    _httpsSuccess = false;
    _dnsAnalysisSuccess = false;
    _tlsAnalysisSuccess = false;
    _domesticIpSuccess = false;
    _internationalIpSuccess = false;
    _overallInternetAccess = false;

    _dnsResult = null;
    _ipv4Result = null;
    _ipv6Result = null;
    _httpsResult = null;
    _dnsAnalysisSummary = null;
    _tlsAnalysisSummary = null;
    _domesticIpResult = null;
    _internationalIpResult = null;
    _routingAnalysisResult = null;
    _websiteResults = [];
    _isScanningWebsites = false;
    _isScanningTlsTargets = false;
    _cdnResults = [];
    _isScanningCdns = false;
    _socialMediaResults = [];
    _isScanningSocialMedia = false;

    notifyListeners();
  }

  String? _extractRetrievedIp(DiagnosticTestResult? result) {
    if (result == null || !result.success) return null;
    return result.message.replaceFirst('IP retrieved: ', '').trim();
  }
}
