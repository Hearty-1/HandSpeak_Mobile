import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'fsl_classifier_service (1).dart';

class CameraRecognitionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraRecognitionScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<CameraRecognitionScreen> createState() => _CameraRecognitionScreenState();
}

class _CameraRecognitionScreenState extends State<CameraRecognitionScreen> {
  CameraController? _cameraController;
  final FslClassifierService _classifierService = FslClassifierService();

  bool _isRecording = false;
  final List<List<double>> _sequenceBuffer = [];

  String _mainText = "HANDA: Pindutin ang RECORD bago sumenyas";
  String _subMetric = "";
  Color _displayColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    await _classifierService.loadModel();

    final frontCamera = widget.cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    _cameraController!.startImageStream((CameraImage image) {
      if (_isRecording) {
        // Landmark buffer hook
      }
    });

    setState(() {});
  }

  void _toggleRecording() {
    if (!_isRecording) {
      setState(() {
        _isRecording = true;
        _sequenceBuffer.clear();
        _mainText = "Sumesenyas...";
        _subMetric = "Itinatala ang buong kumpas...";
        _displayColor = Colors.amber;
      });
    } else {
      setState(() {
        _isRecording = false;
      });

      final result = _classifierService.predict(_sequenceBuffer);

      setState(() {
        _mainText = result['label'] == "Walang tiyak na hula"
            ? "Walang tiyak na hula"
            : "HULA: ${result['label']}";
        _subMetric = result['subtext'] ?? "";
        _displayColor = result['isSuccess'] == true ? Colors.green : Colors.red;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _classifierService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize!.height,
                height: _cameraController!.value.previewSize!.width,
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _displayColor.withOpacity(0.6), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isRecording ? "NAGTATALA (${_sequenceBuffer.length} frames)..." : "KATAYUAN: HANDA",
                    style: TextStyle(
                      color: _isRecording ? Colors.redAccent : Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mainText,
                    style: TextStyle(color: _displayColor, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  if (_subMetric.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_subMetric, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.white,
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.play_arrow,
                    color: _isRecording ? Colors.white : Colors.black,
                    size: 38,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
