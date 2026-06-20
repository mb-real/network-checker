import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import 'root_dns_pinger_controller.dart';

class RootDnsPingerScreen extends StatelessWidget {
  const RootDnsPingerScreen({super.key});

  bool get _isDesktop => Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Root DNS Pinger'),
        actions: [
          Consumer<RootDnsPingerController>(
            builder: (context, controller, _) {
              final reachableServers = controller.results
                  .where((r) => r.isReachable)
                  .map((r) => '${r.name} (${r.ip}) - ${r.latencyMs ?? "?"}ms')
                  .toList();

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reachableServers.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy_all),
                      tooltip: 'Copy reachable servers',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: reachableServers.join('\n')));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${reachableServers.length} servers copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  if (controller.results.isNotEmpty && !controller.isPinging)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Reset results',
                      onPressed: controller.reset,
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<RootDnsPingerController>(
        builder: (context, controller, _) {
          if (controller.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          return Column(
            children: [
              // Progress and stats bar
              if (controller.isPinging || controller.results.isNotEmpty)
                _buildProgressBar(context, controller),
              
              // Results list
              Expanded(
                child: _isDesktop 
                    ? _buildDesktopLayout(context, controller)
                    : _buildMobileLayout(context, controller),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<RootDnsPingerController>(
        builder: (context, controller, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Refresh FAB (small)
              FloatingActionButton.small(
                heroTag: 'refresh_ping',
                onPressed: controller.isPinging 
                    ? null 
                    : controller.pingRootServers,
                child: const Icon(Icons.refresh),
              ).animate().fadeIn(delay: 200.ms).scale(delay: 200.ms),
              const SizedBox(width: 12),
              // Ping/Stop FAB
              FloatingActionButton.extended(
                heroTag: 'ping_stop',
                onPressed: controller.isPinging 
                    ? controller.stopPinging 
                    : controller.pingRootServers,
                icon: Icon(controller.isPinging ? Icons.stop : Icons.play_arrow),
                label: Text(controller.isPinging ? 'Stop' : 'Ping All'),
              ).animate().fadeIn(delay: 100.ms).scale(delay: 100.ms),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, RootDnsPingerController controller) {
    final colorScheme = Theme.of(context).colorScheme;
    final reachableCount = controller.results.where((r) => r.isReachable).length;
    final totalCount = controller.results.length;
    final progress = totalCount > 0 ? reachableCount / totalCount : 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Progress indicator
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: controller.isPinging ? progress : (totalCount > 0 ? 1.0 : 0),
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Stats row
          _buildStatChip(
            context,
            icon: Icons.check_circle,
            label: '$reachableCount',
            color: colorScheme.success,
          ),
          const SizedBox(width: 16),
          _buildStatChip(
            context,
            icon: Icons.cancel,
            label: '${totalCount - reachableCount}',
            color: colorScheme.error,
          ),
          const SizedBox(width: 16),
          _buildStatChip(
            context,
            icon: Icons.pending,
            label: controller.isPinging ? '...' : 'Done',
            color: colorScheme.outline,
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.2, end: 0);
  }

  Widget _buildStatChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context, RootDnsPingerController controller) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (int i = 0; i < controller.results.length; i++)
            _ServerChip(
              result: controller.results[i],
              index: i,
              onTap: () => controller.pingSingle(result: controller.results[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, RootDnsPingerController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 400 ? 2 : 3;
        
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 8, left: 8, right: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: controller.results.length,
          itemBuilder: (context, index) {
            final result = controller.results[index];
            return _ServerGridItem(
              result: result,
              index: index,
              onTap: () => controller.pingSingle(result: result),
            );
          },
        );
      },
    );
  }
}

/// Compact chip design for desktop (مشابه _DomainChip)
class _ServerChip extends StatelessWidget {
  final RootDnsPingResult result;
  final int index;
  final VoidCallback onTap;

  const _ServerChip({
    required this.result,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    final (bgColor, borderColor) = result.isReachable
        ? (
            colorScheme.success.withValues(alpha: 0.15),
            colorScheme.success.withValues(alpha: 0.4),
          )
        : (
            colorScheme.error.withValues(alpha: 0.15),
            colorScheme.error.withValues(alpha: 0.4),
          );

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusIndicator(colorScheme),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    result.ip,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              if (result.isReachable && result.latencyMs != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${result.latencyMs}ms',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.success,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate()
        .fadeIn(delay: Duration(milliseconds: 10 * (index % 50)))
        .slideX(begin: 0.05, end: 0, delay: Duration(milliseconds: 10 * (index % 50)));
  }

  Widget _buildStatusIndicator(ColorScheme colorScheme) {
    const double size = 16;
    
    if (result.isReachable) {
      return Icon(
        Icons.check_circle,
        color: colorScheme.success,
        size: size,
      );
    } else {
      return Icon(
        Icons.cancel,
        color: colorScheme.error,
        size: size,
      );
    }
  }
}

/// Card design for mobile (مشابه _DomainGridItem)
class _ServerGridItem extends StatelessWidget {
  final RootDnsPingResult result;
  final int index;
  final VoidCallback onTap;

  const _ServerGridItem({
    required this.result,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    final cardColor = result.isReachable
        ? colorScheme.success.withValues(alpha: 0.15)
        : colorScheme.error.withValues(alpha: 0.15);
    
    return Card(
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusIcon(colorScheme),
              const SizedBox(height: 6),
              Text(
                result.name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                result.ip,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              if (result.isReachable && result.latencyMs != null) ...[
                const Spacer(),
                Text(
                  '${result.latencyMs}ms',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.success,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 15 * (index % 30)))
        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), delay: Duration(milliseconds: 15 * (index % 30)));
  }

  Widget _buildStatusIcon(ColorScheme colorScheme) {
    const double iconSize = 24;
    
    if (result.isReachable) {
      return Icon(
        Icons.check_circle,
        color: colorScheme.success,
        size: iconSize,
      );
    } else {
      return Icon(
        Icons.cancel,
        color: colorScheme.error,
        size: iconSize,
      );
    }
  }
}
