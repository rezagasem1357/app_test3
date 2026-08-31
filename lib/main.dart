import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:flutter/services.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: ObjectCounterScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ObjectCounterScreen extends StatefulWidget {
  const ObjectCounterScreen({Key? key}) : super(key: key);

  @override
  State<ObjectCounterScreen> createState() => _ObjectCounterScreenState();
}

class _ObjectCounterScreenState extends State<ObjectCounterScreen> {
  CameraController? _cameraController;
  ObjectDetector? _objectDetector;
  
  bool _isProcessing = false;
  int _objectCount = 0;

  @override
  void initState() {
    super.initState();
    _initDetector();
    _initCamera();
  }

  // ۱. مقداردهی اولیه پردازشگر ML Kit
  void _initDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream, // حالت استریم زنده ویدیو
      classifyObjects: true,      // دسته‌بندی اشیاء
      multipleObjects: true,      // اجازه شناسایی چند شیء همزمان در تصویر
    );
    _objectDetector = ObjectDetector(options: options);
  }

  // ۲. راه‌اندازی دوربین
  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;

    // استفاده از اولین دوربین (دوربین پشت)
    _cameraController = CameraController(
      _cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (!mounted) return;

    // شروع استریم تصویر
    _cameraController!.startImageStream((CameraImage image) {
      if (!_isProcessing && _objectDetector != null) {
        _isProcessing = true;
        _processFrame(image);
      }
    });

    setState(() {});
  }

  // ۳. پردازش زنده فریم دوربین
  Future<void> _processFrame(CameraImage image) async {
    final InputImage? inputImage = _convertCameraImageToInputImage(image);
    if (inputImage == null) {
      _isProcessing = false;
      return;
    }

    try {
      // شناسایی اشیاء توسط ML Kit
      final List<DetectedObject> detectedObjects = 
          await _objectDetector!.processImage(inputImage);

      if (mounted) {
        setState(() {
          _objectCount = detectedObjects.length; // تعداد کارهای پردازش شده
        });
      }
    } catch (e) {
      print("خطا در پردازش تصویر: $e");
    } finally {
      _isProcessing = false;
    }
  }

  // تبدیل فریم دوربین به فرمت قابل فهم برای Google ML Kit
  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    final camera = _cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _objectDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("شمارشگر هوشمند کالا"),
        backgroundColor: Colors.blueAccent,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // نمایش تصویر زنده دوربین
          CameraPreview(_cameraController!),

          // باکس نمایش تعداد اجسام در پایین صفحه
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "تعداد کالا/اجسام شناسایی شده",
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "$_objectCount",
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 50,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
