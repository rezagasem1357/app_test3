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
      title: 'شمارش اشیاء با دوربین',
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
  int _objectCount = 0;
  List<Map<String, dynamic>> _detectedObjects = [];

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
        _updateDetections(detectedObjects);
      });
    } catch (e) {
      print('❌ خطا در پردازش: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    try {
      final int width = image.width;
      final int height = image.height;
      
      final Plane plane = image.planes[0];
      final int bufferSize = plane.bytes.length;
      
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

  void _updateDetections(List<DetectedObject> objects) {
    // فقط اشیاء با اطمینان بالا را در نظر بگیر
    List<Map<String, dynamic>> validObjects = [];
    
    for (var object in objects) {
      String label = 'شیء';
      double maxConfidence = 0.0;

      for (var labelObj in object.labels) {
        if (labelObj.confidence > maxConfidence) {
          maxConfidence = labelObj.confidence;
          label = labelObj.text;
        }
      }

      // اشیاء با اطمینان بالای 0.5 را قبول کن
      if (maxConfidence > 0.5) {
        validObjects.add({
          'label': label,
          'confidence': maxConfidence,
        });
      }
    }

    _objectCount = validObjects.length;
    _detectedObjects = validObjects;
  }

  void _resetCount() {
    setState(() {
      _objectCount = 0;
      _detectedObjects = [];
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

  void _showResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue),
            SizedBox(width: 8),
            Text('نتیجه شمارش'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.blue.shade100],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'تعداد کل اشیاء:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$_objectCount',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _objectCount > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_detectedObjects.isNotEmpty) ...[
              const Text(
                'جزئیات تشخیص داده شده:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ..._detectedObjects.map((obj) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(_getEmojiForLabel(obj['label'])),
                          const SizedBox(width: 8),
                          Text(obj['label']),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${(obj['confidence'] * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
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
              _showSuccessMessage('✅ تعداد $_objectCount شیء ثبت شد');
            },
            child: const Text('تأیید'),
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
        title: const Text('📷 شمارش اشیاء با دوربین'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleScanning,
            tooltip: _isScanning ? 'توقف اسکن' : 'شروع اسکن',
          ),
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: _showResultDialog,
            tooltip: 'مشاهده نتیجه',
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
                                width: 280,
                                height: 180,
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
                          Positioned(
                            top: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _objectCount > 0 
                                      ? Colors.green.shade400 
                                      : Colors.orange.shade400,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _objectCount > 0 
                                        ? Icons.check_circle 
                                        : Icons.search,
                                    color: _objectCount > 0 
                                        ? Colors.green 
                                        : Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$_objectCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
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
                                        ? 'در حال شمارش... 🔴'
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
                          
                          // راهنمای کاربر
                          if (_isScanning && _objectCount == 0)
                            const Positioned(
                              bottom: 60,
                              right: 0,
                              left: 0,
                              child: Text(
                                'اشیاء را در کادر سبز قرار دهید',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
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

          // پنل پایین
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
                // نمایش تعداد
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📊 تعداد اشیاء شناسایی شده:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _objectCount > 0
                              ? [Colors.green.shade600, Colors.green.shade800]
                              : [Colors.grey.shade600, Colors.grey.shade800],
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
                          Icon(
                            _objectCount > 0 ? Icons.check : Icons.search,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$_objectCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // دکمه‌ها
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
                        label: const Text('شروع مجدد'),
                        onPressed: _resetCount,
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
                        icon: const Icon(Icons.analytics),
                        label: const Text('مشاهده نتیجه'),
                        onPressed: _showResultDialog,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // نمایش نمونه اشیاء تشخیص داده شده
                if (_detectedObjects.isNotEmpty)
                  Container(
                    height: 30,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _detectedObjects.length > 5 ? 5 : _detectedObjects.length,
                      itemBuilder: (context, index) {
                        final obj = _detectedObjects[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade300),
                          ),
                          child: Row(
                            children: [
                              Text(_getEmojiForLabel(obj['label'])),
                              const SizedBox(width: 4),
                              Text(
                                obj['label'],
                                style: const TextStyle(
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
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
