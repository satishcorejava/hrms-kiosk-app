import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';

/// Serves assets/face (the face page, face-api.js and its models) on localhost, which the WebView
/// treats as a secure origin, so the page may use the camera. Started once, in main().
final faceServer = InAppLocalhostServer(documentRoot: 'assets/face', port: 8765);

/// The camera with the live-person check. [onCaptured] sends the capture to the server and returns
/// null when it worked, or the message to show (the page then offers "Try again").
class FaceScan extends StatefulWidget {
  const FaceScan({super.key, required this.onCaptured});

  final Future<String?> Function(FaceEvidence face) onCaptured;

  @override
  State<FaceScan> createState() => _FaceScanState();
}

class _FaceScanState extends State<FaceScan> {
  bool? _allowed;
  InAppWebViewController? _web;

  @override
  void initState() {
    super.initState();
    _askCamera();
  }

  Future<void> _askCamera() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _allowed = status.isGranted);
  }

  @override
  void dispose() {
    _web?.evaluateJavascript(source: 'window.stopCamera && window.stopCamera()');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed == null) return const Center(child: CircularProgressIndicator());
    if (_allowed == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('The app needs the camera to recognise faces.', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () async { await openAppSettings(); _askCamera(); }, child: const Text('Open settings')),
          ]),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('http://localhost:${faceServer.port}/index.html?mode=verify')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          transparentBackground: true,
          supportZoom: false,
          disableContextMenu: true,
        ),
        onWebViewCreated: (c) {
          _web = c;
          c.addJavaScriptHandler(
            handlerName: 'captured',
            callback: (args) async {
              final m = Map<String, dynamic>.from(args.first as Map);
              final face = FaceEvidence(
                (m['descriptor'] as List).map((v) => (v as num).toDouble()).toList(),
                m['photo'] as String,
              );
              final error = await widget.onCaptured(face);
              return error == null ? {'ok': true} : {'error': error};
            },
          );
        },
        // Only our own page runs here, so its camera request is granted.
        onPermissionRequest: (c, request) async =>
            PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT),
      ),
    );
  }
}
