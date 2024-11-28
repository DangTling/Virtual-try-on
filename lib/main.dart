import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  await dotenv.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Try on App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Scaffold(
        appBar: AppBar(title: Text('Try on App')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: AIModelScreen(),
        ),
      ),
    );
  }
}

class AIModelScreen extends StatefulWidget {
  @override
  _AIModelScreenState createState() => _AIModelScreenState();
}

class _AIModelScreenState extends State<AIModelScreen> {
  bool restoreBackground = false;
  String selectedCategory = "tops";
  String selectedPhotoType = "Model";

  final GlobalKey<_ImageSelectorState> _modelImageKey = GlobalKey();
  final GlobalKey<_ImageSelectorState> _garmentImageKey = GlobalKey();

  Future<String?> uploadImageToCloudinary(File image) async {
    final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'];
    final apiKey = dotenv.env['CLOUDINARY_API_KEY'];
    final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'];
    final uploadPreset = dotenv.env['CLOUDINARY_UPLOAD_PRESET'];

    if (cloudName == null ||
        apiKey == null ||
        apiSecret == null ||
        uploadPreset == null) {
      throw Exception("Cloudinary credentials not found");
    }

    final url =
        Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = 'demo-try-on'
      ..files.add(await http.MultipartFile.fromPath('file', image.path));

    final response = await request.send();

    if (response.statusCode == 200) {
      final responseJson = json.decode(await response.stream.bytesToString());
      return responseJson['secure_url'] as String;
    } else {
      print("Failed to upload image: ${response.statusCode}");
      return null;
    }
  }

  Future<void> generateTryOn() async {
    final File? modelImage = _modelImageKey.currentState?._selectedImage;
    final File? garmentImage = _garmentImageKey.currentState?._selectedImage;

    if (modelImage == null || garmentImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please select both model and garment images")),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Uploading images...")),
      );

      final modelImageUrl = await uploadImageToCloudinary(modelImage);
      final garmentImageUrl = await uploadImageToCloudinary(garmentImage);

      if (modelImageUrl != null || garmentImageUrl != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Images uploaded successfully")),
        );

        final result = await fetchTryOn(modelImageUrl!, garmentImageUrl!);
        if (result != null && result['id'] != null) {
          final id = result['id'] as String;
          await processTryOn(context, id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to initiate try-on process")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to upload images")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("An error occurred: $e")),
      );
      print("Error: $e");
    }
  }

  Future<dynamic> fetchTryOn(
      String modelImageUrl, String garmentImageUrl) async {
    final apiKey = dotenv.env['API_KEY'];
    final res = await http.post(
      Uri.parse('https://api.fashn.ai/v1/run'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model_image': modelImageUrl,
        'garment_image': garmentImageUrl,
        'category': selectedCategory,
        'flat_lay': selectedPhotoType == 'Model' ? false : true,
        'remove_garment_background':
            selectedPhotoType == 'Model' ? false : true,
        'nsfw_filter': false,
      }),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      print("Failed to process try-on: ${res.statusCode}");
      return null;
    }
  }

  Future<void> processTryOn(BuildContext context, String id) async {
    final apiKey = dotenv.env['API_KEY'];
    bool isProcessing = true;

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()));

    while (isProcessing) {
      final res = await http.get(
        Uri.parse('https://api.fashn.ai/v1/status/$id'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (res.statusCode == 200) {
        final statusRes = jsonDecode(res.body);
        final status = statusRes['status'];

        if (status == 'completed') {
          isProcessing = false;
          Navigator.of(context).pop();

          final outputUrl = statusRes['output']?.first;

          if (outputUrl != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (context) =>
                      OutputImageScreen(outputUrl: outputUrl)),
            );
          }
        } else if (status == 'processing') {
          await Future.delayed(Duration(seconds: 2));
        } else {
          isProcessing = false;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Try-on failed: ${statusRes['error']}")),
          );
        }
      } else {
        isProcessing = false;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to check status: ${res.statusCode}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child: Row(
          children: [
            Expanded(
                child: ImageSelector(
                    key: _modelImageKey, title: "Select Model: ")),
            SizedBox(width: 16),
            Expanded(
                child: ImageSelector(
                    key: _garmentImageKey, title: "Select Garment: ")),
          ],
        )),
        SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
              onPressed: generateTryOn, child: Text("Generate Try-on")),
        ),
        SizedBox(height: 16),
        Text("Model Image Controls",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SwitchListTile(
            title: Text("Restore Background"),
            value: restoreBackground,
            onChanged: (value) {
              setState(() {
                restoreBackground = value;
              });
            }),
        SizedBox(height: 16),
        Text("Photo Type",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildPhotoTypeButton('Flat Lay'),
            _buildPhotoTypeButton('Model', isRecommended: true),
          ],
        ),
        SizedBox(height: 16),
        Text("Category",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCategoryButton('Top'),
            _buildCategoryButton('Bottom'),
            _buildCategoryButton('Full-body'),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoTypeButton(String type, {bool isRecommended = false}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selectedPhotoType == type ? Colors.blue : Colors.grey,
      ),
      onPressed: () {
        setState(() {
          selectedPhotoType = type;
        });
      },
      child: Row(
        children: [
          Text(type),
          if (isRecommended) SizedBox(width: 4),
          if (isRecommended)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.yellow,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Recommended',
                style: TextStyle(fontSize: 10, color: Colors.black),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryButton(String category) {
    final Map<String, String> categoryMap = {
      'Top': 'tops',
      'Bottom': 'bottoms',
      'Full-body': 'one-pieces',
    };

    final String apiCategory = categoryMap[category] ?? 'tops';

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            selectedCategory == apiCategory ? Colors.blue : Colors.grey,
      ),
      onPressed: () {
        setState(() {
          selectedCategory = apiCategory;
        });
      },
      child: Text(category),
    );
  }
}

class ImageSelector extends StatefulWidget {
  final String title;

  ImageSelector({required this.title, Key? key}) : super(key: key);

  @override
  _ImageSelectorState createState() => _ImageSelectorState();
}

class _ImageSelectorState extends State<ImageSelector> {
  File? _selectedImage;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _resetImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          widget.title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 10),
        Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _selectedImage == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image, size: 50, color: Colors.grey),
                        SizedBox(height: 10),
                        Text("Paste/drop image here OR"),
                        TextButton(
                          onPressed: _pickImage,
                          child: Text("Choose file"),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_selectedImage!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200),
                      ),
                      Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: _resetImage,
                            child: Container(
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle),
                              child: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ))
                    ],
                  )),
      ],
    );
  }
}

class OutputImageScreen extends StatelessWidget {
  final String outputUrl;

  OutputImageScreen({required this.outputUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Try-On Result")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.network(outputUrl),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _downloadImage(context),
              child: Text("Tải ảnh xuống"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadImage(BuildContext context) async {
    try {
      // Tải ảnh từ URL
      final response = await http.get(Uri.parse(outputUrl));

      if (response.statusCode == 200) {
        // Lưu vào thư mục công khai "Pictures"
        String downloadsDirectory =
            await ExternalPath.getExternalStoragePublicDirectory(
          ExternalPath.DIRECTORY_DOWNLOADS,
        );

        String fileName = 'try_on_result.jpg';
        File file = File(path.join(downloadsDirectory, fileName));

        await file.writeAsBytes(response.bodyBytes);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tải ảnh thành công: ${file.path}")),
        );
      } else {
        throw Exception("Không thể tải ảnh");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi tải ảnh: $e")),
      );
    }
  }
}
