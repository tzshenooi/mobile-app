import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/clinic_config.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // --- 📝 STATE & CONTROLLERS ---
  final _pageController = PageController();
  int _currentStep = 1;
  bool _isLoading = false;
  bool _isScanningMyKad = false;
  final ImagePicker _picker = ImagePicker();

  // Document Files
  File? _icFile;
  File? _licenseFile;

  // Step 1 Controllers
  final _nameController = TextEditingController();
  final _icController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final Color primaryBlue = const Color(0xFF1E40AF);
  final Color bgGray = const Color(0xFFF8FAFC);
  
  // Updated for USM Network / Physical Device
  static const String _myKadExtractUrl = String.fromEnvironment(
    'MYKAD_EXTRACT_URL',
    defaultValue: 'http://10.207.154.87:8001/extract',
  );

  /// Supabase Storage bucket — must exist in Dashboard → Storage.
  /// If you see "Bucket not found", create a bucket with this exact id or change the value below.
  static const String _storageBucket = 'documents';

  // --- 📸 CAMERA & PICKER LOGIC ---
  Future<void> _pickImage(String type, ImageSource source) async {
    final XFile? selected = await _picker.pickImage(
      source: source,
      imageQuality: type == 'ic' ? 70 : 35, // Higher quality for OCR
      maxWidth: 1400,
    );
    if (selected != null) {
      setState(() {
        if (type == 'ic') _icFile = File(selected.path);
        if (type == 'license') _licenseFile = File(selected.path);
      });
      if (type == 'ic') {
        await _scanMyKadFromFile(File(selected.path));
      }
    }
  }

  void _showPickerOptions(String type) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(type, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Upload from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(type, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- 🌐 NETWORK HELPERS ---
  MediaType _mimeFromExtension(String ext) {
    switch (ext) {
      case '.png': return MediaType('image', 'png');
      case '.webp': return MediaType('image', 'webp');
      default: return MediaType('image', 'jpeg');
    }
  }

  String _safeUploadExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  Future<void> _scanMyKadFromFile(File file) async {
    if (mounted) setState(() => _isScanningMyKad = true);
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_myKadExtractUrl));
      final ext = _safeUploadExtension(file.path);
      final bytes = await file.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: 'mykad_upload$ext',
          contentType: _mimeFromExtension(ext),
        ),
      );
      final streamed = await request.send().timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _icController.text = (data['ic_number'] ?? '').toString().trim();
          _nameController.text = (data['name'] ?? '').toString().trim();
        });
        _showSnackBar('IC and name autofilled from MyKad scan.');
      }
    } catch (e) {
      _showSnackBar('MyKad scan error: $e');
    } finally {
      if (mounted) setState(() => _isScanningMyKad = false);
    }
  }

  // --- 🛡️ VALIDATION & NAVIGATION ---
  void _validateAndProceed() {
    if (_currentStep == 1) {
      if (_icFile == null || _nameController.text.isEmpty || _icController.text.isEmpty || _emailController.text.isEmpty) {
        _showSnackBar("Please upload your IC and complete all personal info.");
        return;
      }
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      if (_licenseFile == null) {
        _showSnackBar("Please upload your Driving License.");
        return;
      }
      _handleCompleteRegistration();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange[800], behavior: SnackBarBehavior.floating),
    );
  }

  // --- 🚀 SUPABASE SUBMISSION ---
  Future<void> _handleCompleteRegistration() async {
    setState(() => _isLoading = true);
    try {
      final AuthResponse res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'role': 'driver',
          'name': _nameController.text.trim(),
        },
      );

      if (res.user != null) {
        final userId = res.user!.id;
        final icFile = _icFile;
        final licenseFile = _licenseFile;
        if (icFile == null || licenseFile == null) {
          if (mounted) _showSnackBar('Missing IC or license file. Please re-select your documents.');
          return;
        }

        /// Uses [uploadBinary] so gallery picks on Android/iOS read reliably (not only [File] paths).
        Future<String> uploadDocToStorage(File file, String bucket, String folder) async {
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) throw Exception('Selected image is empty.');
          final ext = _safeUploadExtension(file.path);
          final fileName = '$folder/$userId/${DateTime.now().microsecondsSinceEpoch}$ext';
          final contentType = ext == '.png'
              ? 'image/png'
              : ext == '.webp'
                  ? 'image/webp'
                  : 'image/jpeg';
          await Supabase.instance.client.storage.from(bucket).uploadBinary(
                fileName,
                bytes,
                fileOptions: FileOptions(contentType: contentType, upsert: true),
              );
          return Supabase.instance.client.storage.from(bucket).getPublicUrl(fileName);
        }

        final icUrl = await uploadDocToStorage(icFile, _storageBucket, 'ic_verify');
        final licenseUrl = await uploadDocToStorage(licenseFile, _storageBucket, 'licenses');

        // No certification_level here — do not rely on DB default (e.g. EMT-B).
        final driverRow = <String, dynamic>{
          'id': userId,
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'ic_number': _icController.text.trim(),
          'phone_number': _phoneController.text.trim(),
          'ic_front_url': icUrl,
          'license_front_url': licenseUrl,
          'status': 'Offline',
        };
        if (ClinicConfig.hasClinicId) {
          driverRow['base_clinic_id'] = ClinicConfig.clinicId;
        }
        await Supabase.instance.client.from('drivers').upsert(driverRow);

        if (mounted) {
          _showSnackBar("Registration Successful!");
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar("Error: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: primaryBlue), 
          onPressed: () => _currentStep == 2 
            ? _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) 
            : Navigator.pop(context)
        )
      ),
      body: Column(
        children: [
          _buildLogo(),
          _buildStepper(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (page) => setState(() => _currentStep = page + 1),
              children: [_buildStepOne(), _buildStepTwo()],
            ),
          ),
        ],
      ),
    );
  }

  // --- 🎨 UI BUILDERS ---

  Widget _buildStepOne() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            const Text("Account & Identity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            _docTile("Upload IC Front View", _icFile, () => _showPickerOptions('ic')),
            if (_isScanningMyKad) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 10),
            _buildInputField(_nameController, "Full Name (from IC)", Icons.person_outline),
            const SizedBox(height: 12),
            _buildInputField(_icController, "IC Number", Icons.badge_outlined),
            const SizedBox(height: 12),
            _buildInputField(_phoneController, "Phone Number", Icons.phone_android_outlined),
            const SizedBox(height: 12),
            _buildInputField(_emailController, "Email Address", Icons.mail_outline),
            const SizedBox(height: 12),
            _buildInputField(_passwordController, "Password", Icons.lock_outline, isPass: true),
            const SizedBox(height: 25),
            _buildActionButton("Next Step", _validateAndProceed),
          ],
        ),
      ),
    );
  }

  Widget _buildStepTwo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Professional Verification", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            // Only License Upload Tile remains
            _docTile("Driving License", _licenseFile, () => _showPickerOptions('license')),
            const SizedBox(height: 25),
            _buildActionButton("Complete Registration", _validateAndProceed, isLoading: _isLoading),
          ],
        ),
      ),
    );
  }

  Widget _docTile(String label, File? file, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          border: Border.all(color: file != null ? Colors.green : Colors.grey[200]!), 
          borderRadius: BorderRadius.circular(15), 
          color: file != null ? Colors.green[50] : Colors.white
        ),
        child: Row(
          children: [
            Icon(file != null ? Icons.check_circle : Icons.upload_file, color: file != null ? Colors.green : primaryBlue), 
            const SizedBox(width: 15), 
            Text(label), 
            const Spacer(), 
            if (file != null) const Text("Uploaded", style: TextStyle(color: Colors.green, fontSize: 12))
          ]
        ),
      ),
    ),
  );

  Widget _buildLogo() => Center(child: Container(width: 50, height: 50, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryBlue, const Color(0xFF1E3A8A)]), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.shield, color: Colors.white, size: 25)));
  
  Widget _buildStepper() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15), 
    child: Row(children: [
      _stepCircle(1, _currentStep >= 1, _currentStep > 1), 
      Expanded(child: Container(height: 2, color: _currentStep > 1 ? Colors.green : Colors.grey[300])), 
      _stepCircle(2, _currentStep == 2, false)
    ])
  );

  Widget _stepCircle(int s, bool a, bool d) => Container(
    width: 30, height: 30, 
    decoration: BoxDecoration(color: d ? Colors.green : (a ? primaryBlue : Colors.grey[200]), shape: BoxShape.circle), 
    child: Center(child: d ? const Icon(Icons.check, color: Colors.white, size: 16) : Text("$s", style: TextStyle(color: a ? Colors.white : Colors.grey, fontSize: 12)))
  );

  BoxDecoration _cardDecoration() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15)]);

  Widget _buildInputField(TextEditingController ctrl, String hint, IconData icon, {bool isPass = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10), 
    child: TextField(
      controller: ctrl, 
      obscureText: isPass, 
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18), 
        hintText: hint, 
        filled: true, 
        fillColor: Colors.white, 
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey[200]!)), 
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: primaryBlue))
      )
    )
  );

  Widget _buildActionButton(String text, VoidCallback onPressed, {bool isLoading = false}) => SizedBox(
    width: double.infinity, 
    height: 55, 
    child: ElevatedButton(
      onPressed: isLoading ? null : onPressed, 
      style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
      child: isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
    )
  );
}