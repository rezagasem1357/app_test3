import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

List<CameraDescription>? _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const ObjectCounterApp());
}

class ObjectCounterApp extends StatelessWidget {
  const ObjectCounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'شمارش کالا با دوربین',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      locale: const Locale('fa'),
      home: const ObjectCounterScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ObjectCounterScreen extends StatefulWidget {
  const ObjectCounterScreen({super.key});

  @override
  State<ObjectCounterScreen> createState() => _ObjectCounterScreenState();
}

class _ObjectCounterScreenState extends State<ObjectCounterScreen> {
  CameraController? _cameraController;
  late ObjectDetector _objectDetector;

  bool _isCameraInitialized = false;
  bool _isScanning = true;
  bool _isProcessing = false;
  Map<String, int> _objectCounts = {};
  int _totalObjects = 0;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _objectDetector.close();
    super.dispose();
  }

  void _initializeDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<void> _initCamera() async {
    if (_cameras == null || _cameras!.isEmpty) {
      print('❌ دوربین در دسترس نیست');
      return;
    }

    _cameraController = CameraController(
      _cameras![0],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();

    if (!mounted) return;

    setState(() {
      _isCameraInitialized = true;
    });

    _startImageStream();
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream(_processCameraImage);
  }

  void _stopImageStream() {
    _cameraController?.stopImageStream();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing || !_isScanning) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final List<DetectedObject> detectedObjects =
          await _objectDetector.processImage(inputImage);

      if (!mounted) {
        _isProcessing = false;
        return;
      }

      setState(() {
        _updateCounts(detectedObjects);
      });
    } catch (e) {
      print('❌ خطا در پردازش: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      // روش ساده‌تر برای تبدیل تصویر
      final int width = image.width;
      final int height = image.height;
      
      // گرفتن داده‌های تصویر
      final Plane plane = image.planes[0];
      final int bufferSize = plane.bytes.length;
      
      // ایجاد لیست بایت
      final bytes = Uint8List(bufferSize);
      bytes.setAll(0, plane.bytes);

      final size = Size(width.toDouble(), height.toDouble());

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: size,
          format: InputImageFormat.nv21,
          bytesPerRow: plane.bytesPerRow ?? width,
          rotation: InputImageRotation.rotation0deg,
        ),
      );
    } catch (e) {
      print('❌ خطا در تبدیل تصویر: $e');
      return null;
    }
  }

  void _updateCounts(List<DetectedObject> objects) {
    Map<String, int> newCounts = {};

    for (var object in objects) {
      String label = 'شیء ناشناس';
      double maxConfidence = 0.0;

      for (var labelObj in object.labels) {
        if (labelObj.confidence > maxConfidence) {
          maxConfidence = labelObj.confidence;
          label = labelObj.text;
        }
      }

      if (maxConfidence > 0.5) {
        newCounts[label] = (newCounts[label] ?? 0) + 1;
      }
    }

    if (newCounts.isNotEmpty) {
      _objectCounts = newCounts;
      _totalObjects = newCounts.values.fold(0, (sum, count) => sum + count);
    }
  }

  void _resetCounts() {
    setState(() {
      _objectCounts.clear();
      _totalObjects = 0;
    });
  }

  void _toggleScanning() {
    setState(() {
      _isScanning = !_isScanning;
      if (_isScanning) {
        _startImageStream();
      } else {
        _stopImageStream();
      }
    });
  }

  void _showSnapshotDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.photo_camera, color: Colors.blue),
            SizedBox(width: 8),
            Text('لحظه ثبت شد'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'نتایج شمارش در این لحظه:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_objectCounts.isEmpty)
              const Text('هیچ کالایی تشخیص داده نشد')
            else
              ..._objectCounts.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.value}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'مجموع کالاها:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$_totalObjects',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccessMessage('✅ لحظه با $_totalObjects کالا ثبت شد');
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📷 شمارش کالا با دوربین'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleScanning,
            tooltip: _isScanning ? 'توقف اسکن' : 'شروع اسکن',
          ),
        ],
      ),
      body: Column(
        children: [
          // ویجت دوربین
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade300, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _isCameraInitialized
                    ? Stack(
                        children: [
                          CameraPreview(_cameraController!),
                          // نمایش کادر دوربین
                          if (_isScanning)
                            Center(
                              child: Container(
                                width: 250,
                                height: 150,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.green.shade400,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // نمایش تعداد لحظه‌ای روی دوربین
                          if (_isScanning && _totalObjects > 0)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.green.shade400,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.circle,
                                      color: Colors.green,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$_totalObjects کالا',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // وضعیت اسکن
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isScanning
                                        ? Icons.fiber_manual_record
                                        : Icons.pause_circle_filled,
                                    color: _isScanning
                                        ? Colors.green
                                        : Colors.orange,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isScanning
                                        ? 'اسکن فعال 🔴'
                                        : 'متوقف شده ⏸️',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),

          // پنل نمایش آمار
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📊 آمار شمارش:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade600, Colors.blue.shade800],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            color: Colors.green,
                            size: 10,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$_totalObjects',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // لیست اشیاء تشخیص داده شده
                _objectCounts.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'کالایی تشخیص داده نشد 🧐',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'کالا را در کادر سبز قرار دهید',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _objectCounts.entries.map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.blue.shade300,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _getEmojiForLabel(entry.key),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue.shade600,
                                        Colors.blue.shade800,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${entry.value}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('ریست شمارش'),
                        onPressed: _resetCounts,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('ثبت لحظه'),
                        onPressed: _showSnapshotDialog,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getEmojiForLabel(String label) {
    final emojiMap = {
      'person': '👤',
      'bicycle': '🚲',
      'car': '🚗',
      'motorcycle': '🏍️',
      'airplane': '✈️',
      'bus': '🚌',
      'train': '🚂',
      'truck': '🚛',
      'boat': '⛵',
      'traffic light': '🚦',
      'fire hydrant': '🧯',
      'stop sign': '🛑',
      'parking meter': '🅿️',
      'bench': '🪑',
      'bird': '🐦',
      'cat': '🐱',
      'dog': '🐶',
      'horse': '🐴',
      'sheep': '🐑',
      'cow': '🐄',
      'elephant': '🐘',
      'bear': '🐻',
      'zebra': '🦓',
      'giraffe': '🦒',
      'backpack': '🎒',
      'umbrella': '☂️',
      'handbag': '👜',
      'tie': '👔',
      'suitcase': '🧳',
      'frisbee': '🥏',
      'skis': '⛷️',
      'snowboard': '🏂',
      'sports ball': '⚽',
      'kite': '🪁',
      'baseball bat': '⚾',
      'baseball glove': '🧤',
      'skateboard': '🛹',
      'surfboard': '🏄',
      'tennis racket': '🎾',
      'bottle': '🍾',
      'wine glass': '🍷',
      'cup': '☕',
      'fork': '🍴',
      'knife': '🔪',
      'spoon': '🥄',
      'bowl': '🥣',
      'banana': '🍌',
      'apple': '🍎',
      'sandwich': '🥪',
      'orange': '🍊',
      'broccoli': '🥦',
      'carrot': '🥕',
      'hot dog': '🌭',
      'pizza': '🍕',
      'donut': '🍩',
      'cake': '🎂',
      'chair': '🪑',
      'couch': '🛋️',
      'potted plant': '🪴',
      'bed': '🛏️',
      'dining table': '🍽️',
      'toilet': '🚽',
      'tv': '📺',
      'laptop': '💻',
      'mouse': '🖱️',
      'remote': '📟',
      'keyboard': '⌨️',
      'cell phone': '📱',
      'microwave': '📡',
      'oven': '🔥',
      'toaster': '🍞',
      'sink': '🚰',
      'refrigerator': '🧊',
      'book': '📚',
      'clock': '🕐',
      'vase': '🏺',
      'scissors': '✂️',
      'teddy bear': '🧸',
      'hair drier': '💨',
      'toothbrush': '🪥',
    };

    for (var key in emojiMap.keys) {
      if (label.toLowerCase().contains(key)) {
        return emojiMap[key]!;
      }
    }

    return '📦';
  }
}