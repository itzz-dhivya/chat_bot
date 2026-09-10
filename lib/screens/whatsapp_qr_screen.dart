import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/user_service.dart';
import 'chat_screen.dart';
import 'payments_screen.dart';

class WhatsAppQrCodeScreen extends StatefulWidget {
  final String userName;
  final String? avatarUrl;
  final String phoneNumber;

  const WhatsAppQrCodeScreen({
    super.key,
    required this.userName,
    this.avatarUrl,
    required this.phoneNumber,
  });

  @override
  State<WhatsAppQrCodeScreen> createState() => _WhatsAppQrCodeScreenState();
}

class _WhatsAppQrCodeScreenState extends State<WhatsAppQrCodeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isScanned = false;
  bool _isFlashOn = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _toggleFlash() {
    setState(() => _isFlashOn = !_isFlashOn);
    _scannerController.toggleTorch();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_isScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue != null && rawValue.trim().isNotEmpty) {
      setState(() => _isScanned = true);
      _processScannedData(rawValue.trim());
    }
  }

  Future<void> _processScannedData(String data) async {
    // 1. Check if UPI payment QR
    if (data.startsWith('upi://pay') || (data.contains('@') && !data.contains(' '))) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.currency_rupee_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('UPI QR Detected'),
            ],
          ),
          content: Text('Would you like to open ChatApp Pay to transfer money to:\n\n$data'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Proceed to Pay'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PaymentsScreen()),
        );
        return;
      }
    }

    // 2. Check if Contact QR
    String phone = '';
    if (data.startsWith('whatsapp://contact')) {
      final uri = Uri.tryParse(data);
      phone = uri?.queryParameters['phone'] ?? '';
    } else if (RegExp(r'^\+?[0-9]{10,13}$').hasMatch(data.replaceAll(RegExp(r'\s+'), ''))) {
      phone = data.replaceAll(RegExp(r'\s+'), '');
    }

    if (phone.isNotEmpty) {
      final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
      final user = await UserService().findUserByPhoneNumber(cleanPhone);

      if (user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              targetUser: user,
            ),
          ),
        );
        return;
      }
    }

    // 3. Fallback generic dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('QR Code Scanned'),
          content: SelectableText(data),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: data));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _isScanned = false);
              },
              child: const Text('Scan Again'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _pickQrFromGallery() async {
    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(source: ImageSource.gallery);
      if (img == null) return;

      final capture = await _scannerController.analyzeImage(img.path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        final raw = capture.barcodes.first.rawValue;
        if (raw != null && raw.isNotEmpty && mounted) {
          _processScannedData(raw);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No QR code found in selected image'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171B2D),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF171B2D)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'QR code',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF171B2D)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF171B2D)),
            tooltip: 'Share',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: 'whatsapp://contact?phone=${widget.phoneNumber}&name=${widget.userName}',
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Contact QR link copied to clipboard ✓'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF5B50E6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF5B50E6),
          indicatorWeight: 3,
          labelColor: const Color(0xFF5B50E6),
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
          tabs: const [
            Tab(text: 'MY CODE'),
            Tab(text: 'SCAN CODE'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyCodeTab(),
          _buildScanCodeTab(),
        ],
      ),
    );
  }

  Widget _buildMyCodeTab() {
    final displayName = widget.userName.isNotEmpty ? widget.userName : 'My Profile';
    final qrPayload = 'whatsapp://contact?phone=${widget.phoneNumber}&name=${widget.userName}';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Card with authentic QR code
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 40),
                  padding: const EdgeInsets.fromLTRB(28, 56, 28, 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Color(0xFF171B2D),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.phoneNumber.isNotEmpty ? widget.phoneNumber : 'ChatApp Contact',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Real Scannable QR Code Container
                      Container(
                        width: 210,
                        height: 210,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6FC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: QrImageView(
                          data: qrPayload,
                          version: QrVersions.auto,
                          size: 186,
                          backgroundColor: Colors.transparent,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF171B2D),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF171B2D),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Overlapping avatar at top
                Positioned(
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5B50E6).withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: const Color(0xFFEDE9FE),
                      backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                          ? NetworkImage(widget.avatarUrl!)
                          : null,
                      child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
                          ? const Icon(Icons.person_rounded, color: Color(0xFF5B50E6), size: 42)
                          : null,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Disclaimer text
            Text(
              'Your QR code is private. If you share it with someone, they can scan it with their camera to connect or chat with you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanCodeTab() {
    return Stack(
      children: [
        // Live Real-Time Camera QR Scanner
        MobileScanner(
          controller: _scannerController,
          onDetect: _handleBarcode,
        ),

        // Darkened overlay with square scan cutout
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF10B981), width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
        ),

        // Bottom Controls (Torch, Switch Camera, Gallery)
        Positioned(
          bottom: 36,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _isFlashOn ? Colors.amber : Colors.white,
                  size: 28,
                ),
                onPressed: _toggleFlash,
              ),
              IconButton(
                icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 28),
                onPressed: () => _scannerController.switchCamera(),
              ),
              IconButton(
                icon: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 28),
                tooltip: 'Scan from Gallery',
                onPressed: _pickQrFromGallery,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
