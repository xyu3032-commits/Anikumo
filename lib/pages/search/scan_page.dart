import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/deep_links/app_deep_links.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/services/search/scan_dispatch.dart';

/// Batch 284 (#19): the in-app scanner.
///
/// Two modes, chosen by the caller:
/// - dispatch mode (from the search page): a code is
///   classified by [dispatchScanResult] — deep links open
///   in place through the shared deep-link landing, and
///   search/LAN actions are handed back as the route
///   result for the search page to act on.
/// - raw mode (`rawResultOnly`, from the backup page):
///   the first code's raw text is the route result, and
///   the caller interprets it (a LAN transfer payload).
///
/// The camera session belongs to this page: leaving the
/// page disposes the controller and stops the camera.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.rawResultOnly = false});

  final bool rawResultOnly;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null) return;
    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    if (widget.rawResultOnly) {
      Navigator.of(context).pop(raw);
      return;
    }
    final action = dispatchScanResult(raw);
    switch (action) {
      case ScanOpenDeepLink(:final link):
        Navigator.of(context).pop();
        await AppDeepLinks().openParsedLink(link);
      case ScanLanReceive() || ScanSearch():
        Navigator.of(context).pop(action);
      case ScanIgnored():
        if (mounted) {
          setState(() => _handled = false);
          unawaited(_controller.start());
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SysAppBar(title: Text(S.t('扫码'))),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Text(
                    S.t('将相机对准二维码'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) {
                  final torchOn = state.torchState == TorchState.on;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton(
                        heroTag: 'scan-torch',
                        tooltip: S.t('手电筒'),
                        onPressed: () => _controller.toggleTorch(),
                        child: Icon(
                          torchOn
                              ? Icons.flashlight_on
                              : Icons.flashlight_off,
                        ),
                      ),
                      const SizedBox(width: 20),
                      FloatingActionButton(
                        heroTag: 'scan-cancel',
                        tooltip: S.t('取消'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Icon(AnikumoIcons.close_rounded),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
