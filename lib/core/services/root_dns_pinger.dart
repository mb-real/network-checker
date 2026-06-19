import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

/// Result of pinging a root DNS server
class RootDnsPingResult {
  final String name;          // e.g., "A.root-servers.net"
  final String ip;
  final int? latencyMs;
  final bool isReachable;
  final String? error;
  final List<String>? referralIps;  // IPs of TLD servers it referred to

  RootDnsPingResult({
    required this.name,
    required this.ip,
    this.latencyMs,
    required this.isReachable,
    this.error,
    this.referralIps,
  });

  @override
  String toString() {
    final status = isReachable ? '✅' : '❌';
    final latency = latencyMs != null ? '${latencyMs}ms' : 'N/A';
    return '$status $name ($ip) - Latency: $latency - ${referralIps ?? 'No referral'}';
  }
}

/// Service for pinging root DNS servers
class RootDnsPinger {
  static const Duration defaultTimeout = Duration(seconds: 3);
  static const int defaultConcurrency = 5;

  // 13 Root DNS Servers (as of 2026)
  static const List<Map<String, String>> rootServers = [
    {'name': 'A.root-servers.net', 'ip': '198.41.0.4'},
    {'name': 'B.root-servers.net', 'ip': '199.9.14.201'},
    {'name': 'C.root-servers.net', 'ip': '192.33.4.12'},
    {'name': 'D.root-servers.net', 'ip': '199.7.91.13'},
    {'name': 'E.root-servers.net', 'ip': '192.203.230.10'},
    {'name': 'F.root-servers.net', 'ip': '192.5.5.241'},
    {'name': 'G.root-servers.net', 'ip': '192.112.36.4'},
    {'name': 'H.root-servers.net', 'ip': '198.97.190.53'},
    {'name': 'I.root-servers.net', 'ip': '192.36.148.17'},
    {'name': 'J.root-servers.net', 'ip': '192.58.128.30'},
    {'name': 'K.root-servers.net', 'ip': '193.0.14.129'},
    {'name': 'L.root-servers.net', 'ip': '199.7.83.42'},
    {'name': 'M.root-servers.net', 'ip': '202.12.27.33'},
  ];

  /// Build a DNS query for the root zone (.)
  static List<int> _buildRootQuery() {
    // Standard DNS query for the root zone
    return [
      0xAA, 0xBB, // Transaction ID (random)
      0x01, 0x00, // Flags: standard query, recursion desired
      0x00, 0x01, // Questions: 1
      0x00, 0x00, // Answer RRs: 0
      0x00, 0x00, // Authority RRs: 0
      0x00, 0x00, // Additional RRs: 0
      0x00, // Root domain (empty label)
      0x00, 0x01, // Type: A
      0x00, 0x01, // Class: IN
    ];
  }

  /// Parse root DNS response and extract referral IPs (NS + glue records)
  static List<String> _parseRootResponse(List<int> data) {
    if (data.length < 12) return [];

    // Check if it's a valid response (QR bit set)
    if ((data[2] & 0x80) == 0) return [];

    // Check response code (should be 0 for no error)
    final rcode = data[3] & 0x0F;
    if (rcode != 0) return [];

    final referralIps = <String>[];
    var offset = 12;

    // Skip question section (root domain is 1 byte: 0x00)
    offset++; // Skip the root domain null byte
    offset += 4; // Skip QTYPE and QCLASS

    // Get counts
    final answerCount = (data[6] << 8) | data[7];
    final authorityCount = (data[8] << 8) | data[9];
    final additionalCount = (data[10] << 8) | data[11];

    // Skip answer section (if any)
    for (var i = 0; i < answerCount && offset < data.length; i++) {
      offset = _skipName(data, offset);
      if (offset + 10 > data.length) break;
      offset += 10; // Skip TYPE, CLASS, TTL, RDLENGTH
      final rdLength = (data[offset - 2] << 8) | data[offset - 1];
      offset += rdLength;
    }

    // Skip authority section (we want the NS records, but they don't have IPs directly)
    for (var i = 0; i < authorityCount && offset < data.length; i++) {
      offset = _skipName(data, offset);
      if (offset + 10 > data.length) break;
      // Type NS (2) we skip, as we need glue from additional
      offset += 10;
      final rdLength = (data[offset - 2] << 8) | data[offset - 1];
      offset += rdLength;
    }

    // Parse additional section (glue records - A records for name servers)
    for (var i = 0; i < additionalCount && offset < data.length - 10; i++) {
      offset = _skipName(data, offset);
      if (offset + 10 > data.length) break;

      final type = (data[offset] << 8) | data[offset + 1];
      offset += 8; // Skip TYPE, CLASS, TTL

      final rdLength = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // Type A record (1) with length 4
      if (type == 1 && rdLength == 4 && offset + 4 <= data.length) {
        final ip =
            '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
        referralIps.add(ip);
      }

      offset += rdLength;
    }

    return referralIps;
  }

  /// Skip a DNS name (supports compression pointers)
  static int _skipName(List<int> data, int offset) {
    if (offset >= data.length) return offset;

    // Check for compression pointer (0xC0)
    if ((data[offset] & 0xC0) == 0xC0) {
      return offset + 2;
    }

    while (offset < data.length && data[offset] != 0) {
      if ((data[offset] & 0xC0) == 0xC0) {
        return offset + 2;
      }
      offset += data[offset] + 1;
    }
    return offset + 1; // Skip null byte
  }

  /// Ping a single root DNS server
  static Future<RootDnsPingResult> pingRootServer(
    String name,
    String ip, {
    Duration timeout = defaultTimeout,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final addr = InternetAddress.tryParse(ip);
      if (addr == null) {
        return RootDnsPingResult(
          name: name,
          ip: ip,
          isReachable: false,
          error: 'Invalid IP',
        );
      }

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      try {
        final query = _buildRootQuery();
        socket.send(query, addr, 53);

        final completer = Completer<List<int>?>();
        Timer? timeoutTimer;

        timeoutTimer = Timer(timeout, () {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        });

        socket.listen((event) {
          if (event == RawSocketEvent.read && !completer.isCompleted) {
            final datagram = socket.receive();
            if (datagram != null &&
                datagram.data.length > 2 &&
                datagram.data[0] == 0xAA &&
                datagram.data[1] == 0xBB) {
              completer.complete(datagram.data);
            }
          }
        });

        final response = await completer.future;
        stopwatch.stop();
        timeoutTimer.cancel();

        if (response == null) {
          return RootDnsPingResult(
            name: name,
            ip: ip,
            isReachable: false,
            latencyMs: stopwatch.elapsedMilliseconds,
            error: 'Timeout - No response from root server',
          );
        }

        final referralIps = _parseRootResponse(response);

        return RootDnsPingResult(
          name: name,
          ip: ip,
          isReachable: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          referralIps: referralIps.isNotEmpty ? referralIps : null,
        );
      } finally {
        socket.close();
      }
    } on SocketException catch (e) {
      stopwatch.stop();
      return RootDnsPingResult(
        name: name,
        ip: ip,
        isReachable: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: e.message,
      );
    } catch (e) {
      stopwatch.stop();
      return RootDnsPingResult(
        name: name,
        ip: ip,
        isReachable: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }

  /// Ping all root DNS servers in parallel
  static Future<List<RootDnsPingResult>> pingAllRootServers({
    Duration timeout = defaultTimeout,
    int concurrency = defaultConcurrency,
  }) async {
    final results = <RootDnsPingResult>[];
    final futures = <Future<RootDnsPingResult>>[];

    for (final server in rootServers) {
      final name = server['name']!;
      final ip = server['ip']!;

      if (futures.length >= concurrency) {
        // Wait for one to complete before adding more
        final result = await Future.any(futures);
        results.add(result);
        futures.remove(result);
      }

      futures.add(pingRootServer(name, ip, timeout: timeout));
    }

    // Wait for remaining futures
    final remainingResults = await Future.wait(futures);
    results.addAll(remainingResults);

    // Sort by latency (fastest first)
    results.sort((a, b) {
      if (a.latencyMs == null && b.latencyMs == null) return 0;
      if (a.latencyMs == null) return 1;
      if (b.latencyMs == null) return -1;
      return a.latencyMs!.compareTo(b.latencyMs!);
    });

    return results;
  }

  /// Find the fastest reachable root DNS server
  static Future<RootDnsPingResult?> findFastestRoot({
    Duration timeout = defaultTimeout,
  }) async {
    final results = await pingAllRootServers(timeout: timeout);
    final reachable = results.where((r) => r.isReachable).toList();
    return reachable.isNotEmpty ? reachable.first : null;
  }
}

/// Example usage
void main() async {
  print('🔍 Pinging all root DNS servers...\n');

  final results = await RootDnsPinger.pingAllRootServers(
    timeout: Duration(seconds: 3),
    concurrency: 5,
  );

  for (final result in results) {
    print(result);
  }

  print('\n📊 Summary:');
  final reachable = results.where((r) => r.isReachable);
  print('✅ Reachable: ${reachable.length} / ${results.length}');

  if (reachable.isNotEmpty) {
    final fastest = reachable.first;
    print('⚡ Fastest: ${fastest.name} (${fastest.ip}) - ${fastest.latencyMs}ms');
    
    if (fastest.referralIps != null && fastest.referralIps!.isNotEmpty) {
      print('🔗 Referral IPs: ${fastest.referralIps!.join(', ')}');
    }
  }
}
