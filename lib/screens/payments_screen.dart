import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_model.dart';
import '../services/user_service.dart';
import '../widgets/qr_scanner_screen.dart';

class PaymentsScreen extends StatefulWidget {
  final UserModel? targetUser;
  final String? initialReceiverUpi;
  final String? initialReceiverName;

  const PaymentsScreen({
    super.key,
    this.targetUser,
    this.initialReceiverUpi,
    this.initialReceiverName,
  });

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late TabController _tabController;

  UserModel? _currentUser;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUser();
  }

  Future<void> _loadUser() async {
    final profile = await _userService.getCurrentUserProfile();
    if (mounted) {
      setState(() {
        _currentUser = profile;
        _isLoadingUser = false;
      });

      // If opened with a target recipient from chat or contact, auto prefill payment sheet
      if (widget.targetUser != null || widget.initialReceiverUpi != null) {
        final targetUpi =
            widget.initialReceiverUpi ??
            widget.targetUser?.effectiveUpiId ??
            '';
        final targetName =
            widget.initialReceiverName ?? widget.targetUser?.name ?? '';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && targetUpi.isNotEmpty) {
            _showSendMoneyDialog(
              initialUpi: targetUpi,
              initialName: targetName,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _myUpiId {
    if (_currentUser?.upiId != null && _currentUser!.upiId!.trim().isNotEmpty) {
      return _currentUser!.upiId!.trim();
    }
    if (_currentUser?.name.toLowerCase().contains('dhivya') == true ||
        _currentUser == null) {
      return 'dhivya032005-1@okhdfcbank';
    }
    return _currentUser!.effectiveUpiId;
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? Colors.red.shade700
            : const Color(0xFF5B50E6),
      ),
    );
  }

  // ============================================================
  // SCAN ANY UPI QR CODE
  // ============================================================

  Future<void> _scanUpiQr() async {
    final String? scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(title: 'Scan UPI QR Code'),
      ),
    );

    if (scannedCode == null || scannedCode.trim().isEmpty || !mounted) return;

    final String raw = scannedCode.trim();
    String receiverUpi = '';
    String receiverName = '';
    String amountStr = '';
    String note = '';

    if (raw.startsWith('upi://pay')) {
      final Uri? uri = Uri.tryParse(raw);
      if (uri != null) {
        receiverUpi = uri.queryParameters['pa'] ?? '';
        receiverName = uri.queryParameters['pn'] ?? '';
        amountStr = uri.queryParameters['am'] ?? '';
        note = uri.queryParameters['tn'] ?? '';
      }
    } else if (raw.contains('@')) {
      receiverUpi = raw;
    } else {
      receiverUpi = raw;
    }

    _showSendMoneyDialog(
      initialUpi: receiverUpi,
      initialName: receiverName,
      initialAmount: amountStr,
      initialNote: note,
    );
  }

  String _historyFilter = 'all'; // 'all', 'sent', 'received'

  // ============================================================
  // REAL UPI PAYMENT INITIATION
  // ============================================================

  Future<void> _initiateRealUpiPayment({
    required String receiverUpi,
    required String receiverName,
    required double amount,
    required String note,
    String? knownReceiverUid, // pass when receiver's UID is already known
  }) async {
    final cleanUpi = receiverUpi.trim();
    if (cleanUpi.isEmpty || !cleanUpi.contains('@')) {
      _showSnack('Please enter a valid UPI ID (e.g. name@upi)', isError: true);
      return;
    }

    if (amount <= 0) {
      _showSnack('Please enter a valid amount', isError: true);
      return;
    }

    final String finalReceiverName = receiverName.trim().isNotEmpty
        ? receiverName.trim()
        : cleanUpi;
    final String finalNote = note.trim().isNotEmpty
        ? note.trim()
        : 'Payment via ChatApp';

    // 1. Pre-record transaction as 'Initiated' / 'Pending' in Firestore
    final txRefs = await _recordTransaction(
      receiverUpi: cleanUpi,
      receiverName: finalReceiverName,
      amount: amount,
      note: finalNote,
      status: 'Initiated',
      knownReceiverUid: knownReceiverUid,
    );

    final String senderTxId = txRefs['senderTxId'] ?? '';
    final String? receiverUid = txRefs['receiverUid'];
    final String? receiverTxId = txRefs['receiverTxId'];

    // UPI P2P deep link — tn (transaction note) removed intentionally.
    // Sending 'tn=Payment via ChatApp' can cause some banks (ICICI) to
    // flag this as a third-party initiated payment with stricter limits.
    final String upiUrl =
        'upi://pay?pa=$cleanUpi&pn=${Uri.encodeComponent(finalReceiverName)}&am=${amount.toStringAsFixed(2)}&cu=INR';

    final Uri uri = Uri.parse(upiUrl);

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _showSnack(
          'No UPI payment app (GPay/PhonePe/Paytm) found on this device.',
          isError: true,
        );
      }

      // 2. When user returns from UPI app, ask them to confirm payment status
      if (mounted) {
        _showPaymentConfirmationDialog(
          senderTxId: senderTxId,
          receiverUid: receiverUid,
          receiverTxId: receiverTxId,
          receiverName: finalReceiverName,
          receiverUpi: cleanUpi,
          amount: amount,
        );
      }
    } catch (e) {
      debugPrint('Error launching UPI deep link: $e');
      if (mounted) {
        _showPaymentConfirmationDialog(
          senderTxId: senderTxId,
          receiverUid: receiverUid,
          receiverTxId: receiverTxId,
          receiverName: finalReceiverName,
          receiverUpi: cleanUpi,
          amount: amount,
        );
      }
    }
  }

  /// Records transaction in sender's history AND receiver's history if registered.
  Future<Map<String, String?>> _recordTransaction({
    required String receiverUpi,
    required String receiverName,
    required double amount,
    required String note,
    required String status,
    String? knownReceiverUid, // UID passed directly when known (chat partner or app users list)
  }) async {
    final senderUid = _userService.currentUserId;
    if (senderUid == null) return {};

    String senderTxId = '';
    // Priority: explicit knownReceiverUid → widget.targetUser.id → Firestore UPI lookup
    String? receiverUid = knownReceiverUid ?? widget.targetUser?.id;
    String? receiverTxId;

    try {
      // 1. Add to sender's transactions
      final senderDoc = await _firestore
          .collection('users')
          .doc(senderUid)
          .collection('transactions')
          .add({
            'receiverUpi': receiverUpi,
            'receiverName': receiverName,
            'senderUpi': _myUpiId,
            'senderName': _currentUser?.name ?? 'User',
            'amount': amount,
            'type': 'sent',
            'note': note,
            'status': status,
            'createdAt': FieldValue.serverTimestamp(),
          });
      senderTxId = senderDoc.id;

      // 2. Resolve receiver in Firestore if not already provided
      if (receiverUid == null) {
        final upiQuery = await _firestore
            .collection('users')
            .where('upiId', isEqualTo: receiverUpi)
            .limit(1)
            .get();

        if (upiQuery.docs.isNotEmpty) {
          receiverUid = upiQuery.docs.first.id;
        } else {
          // Check by clean phone if upi contains phone
          final digits = receiverUpi
              .split('@')
              .first
              .replaceAll(RegExp(r'\D'), '');
          if (digits.length >= 10) {
            final phoneQuery = await _firestore
                .collection('users')
                .where(
                  'phoneNumber',
                  isGreaterThanOrEqualTo: digits.substring(digits.length - 10),
                )
                .limit(1)
                .get();
            if (phoneQuery.docs.isNotEmpty) {
              receiverUid = phoneQuery.docs.first.id;
            }
          }
        }
      }

      // 3. Add to receiver's transactions as 'received'
      // Write with status='Pending' — will be upgraded to 'Completed' when sender confirms.
      // This ensures receiver sees the transaction even before confirmation.
      if (receiverUid != null && receiverUid != senderUid) {
        final recDoc = await _firestore
            .collection('users')
            .doc(receiverUid)
            .collection('transactions')
            .add({
              'receiverUpi': receiverUpi,
              'receiverName': receiverName,
              'senderUpi': _myUpiId,
              'senderName': _currentUser?.name ?? 'User',
              'amount': amount,
              'type': 'received',
              'note': note,
              'status': 'Pending', // Always start Pending, update after confirmation
              'createdAt': FieldValue.serverTimestamp(),
            });
        receiverTxId = recDoc.id;
        debugPrint('Receiver tx recorded: $receiverTxId for uid: $receiverUid');
      } else {
        debugPrint('Could not find receiver uid for upi: $receiverUpi — receiver history not written');
      }
    } catch (e) {
      debugPrint('Error recording transaction: $e');
    }

    return {
      'senderTxId': senderTxId,
      'receiverUid': receiverUid,
      'receiverTxId': receiverTxId,
    };
  }

  /// Updates status of an existing transaction across sender and receiver
  Future<void> _updateTransactionStatus({
    required String senderTxId,
    String? receiverUid,
    String? receiverTxId,
    required String newStatus,
  }) async {
    final senderUid = _userService.currentUserId;
    if (senderUid == null || senderTxId.isEmpty) return;

    try {
      await _firestore
          .collection('users')
          .doc(senderUid)
          .collection('transactions')
          .doc(senderTxId)
          .update({'status': newStatus});

      if (receiverUid != null && receiverTxId != null) {
        await _firestore
            .collection('users')
            .doc(receiverUid)
            .collection('transactions')
            .doc(receiverTxId)
            .update({'status': newStatus});
      }
    } catch (e) {
      debugPrint('Error updating transaction status: $e');
    }
  }

  // ============================================================
  // PAYMENT STATUS CONFIRMATION DIALOG (ON RETURN FROM GPAY)
  // ============================================================

  void _showPaymentConfirmationDialog({
    required String senderTxId,
    String? receiverUid,
    String? receiverTxId,
    required String receiverName,
    required String receiverUpi,
    required double amount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF5B50E6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFF5B50E6),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Confirm Payment',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reminder banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFB45309),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GPay-ல open ஆச்சா? Amount ₹ ${amount.toStringAsFixed(2)} type பண்ணி UPI PIN enter பண்ணி pay பண்ணுங்க.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFB45309),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Amount to enter:',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      Text(
                        '₹ ${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pay to UPI:',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      Flexible(
                        child: Text(
                          receiverUpi,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF5B50E6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Pay பண்ணாச்சா? இல்லை bank error வந்துச்சா? Confirm பண்ணுங்க.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateTransactionStatus(
                senderTxId: senderTxId,
                receiverUid: receiverUid,
                receiverTxId: receiverTxId,
                newStatus: 'Failed',
              );
              _showSnack('Payment marked as Failed', isError: true);
            },
            child: const Text(
              'Failed / Cancelled',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _updateTransactionStatus(
                senderTxId: senderTxId,
                receiverUid: receiverUid,
                receiverTxId: receiverTxId,
                newStatus: 'Completed',
              );
              _showSnack('Payment recorded as Completed ✓');
            },
            child: const Text(
              'Payment Successful ✓',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SEND MONEY DIALOG
  // ============================================================

  void _showSendMoneyDialog({
    String initialUpi = '',
    String initialName = '',
    String initialAmount = '',
    String initialNote = '',
    String? knownReceiverUid, // pass when paying a known app user
  }) {
    final upiController = TextEditingController(text: initialUpi);
    final nameController = TextEditingController(text: initialName);
    final amountController = TextEditingController(text: initialAmount);
    final noteController = TextEditingController(text: initialNote);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Color(0xFF5B50E6),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Send Money via UPI',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: upiController,
                decoration: InputDecoration(
                  labelText: 'Receiver UPI ID *',
                  hintText: 'e.g. mobile@upi or username@oksbi',
                  prefixIcon: const Icon(
                    Icons.alternate_email_rounded,
                    color: Color(0xFF5B50E6),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Recipient Name (Optional)',
                  hintText: 'e.g. Friend / Shop Name',
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    color: Color(0xFF5B50E6),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount (₹) *',
                  hintText: '₹ 100.00',
                  prefixIcon: const Icon(
                    Icons.currency_rupee_rounded,
                    color: Color(0xFF5B50E6),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: InputDecoration(
                  labelText: 'Note (Optional)',
                  hintText: 'e.g. Payment via ChatApp',
                  prefixIcon: const Icon(
                    Icons.note_alt_outlined,
                    color: Color(0xFF5B50E6),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final upi = upiController.text.trim();
                    final name = nameController.text.trim();
                    final amount =
                        double.tryParse(amountController.text.trim()) ?? 0.0;
                    final note = noteController.text.trim();

                    Navigator.pop(ctx);
                    _initiateRealUpiPayment(
                      receiverUpi: upi,
                      receiverName: name,
                      amount: amount,
                      note: note,
                      knownReceiverUid: knownReceiverUid,
                    );
                  },
                  icon: const Icon(Icons.flash_on_rounded, size: 20),
                  label: const Text(
                    'Pay with Installed UPI App',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B50E6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Direct GPay / Search Fallback (bypasses bank deep link limits)
              OutlinedButton.icon(
                onPressed: () async {
                  final upi = upiController.text.trim();
                  if (upi.isEmpty) {
                    _showSnack('Please enter a UPI ID first', isError: true);
                    return;
                  }
                  Clipboard.setData(ClipboardData(text: upi));
                  Navigator.pop(ctx);
                  _showSnack(
                    'UPI ID "$upi" copied to clipboard! Paste it in GPay search ✓',
                  );

                  // Launch standard generic UPI app
                  try {
                    await launchUrl(
                      Uri.parse('upi://pay'),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
                },
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Copy UPI ID & Open GPay Manually'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF5B50E6),
                  side: const BorderSide(color: Color(0xFF5B50E6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MY QR / RECEIVE MONEY DIALOG (AUTHENTIC SCANNABLE UPI QR)
  // ============================================================

  void _showMyQrDialog() {
    final String upiPayload =
        'upi://pay?pa=$_myUpiId&pn=${Uri.encodeComponent(_currentUser?.name.isNotEmpty == true ? _currentUser!.name : "User")}&cu=INR';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Receive Payment via UPI',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scan this QR code with any UPI app (GPay, PhonePe, Paytm, BHIM)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),

            // Authentic 100% Scannable Standard QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  QrImageView(
                    data: upiPayload,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF1E293B),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _currentUser?.name.isNotEmpty == true
                        ? _currentUser!.name
                        : 'ChatApp User',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _myUpiId,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B50E6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _myUpiId));
                Navigator.pop(ctx);
                _showSnack('UPI ID copied to clipboard ✓');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy My UPI ID'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF5B50E6),
                side: const BorderSide(color: Color(0xFF5B50E6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD TABS
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),
      appBar: AppBar(
        title: const Text(
          'ChatApp Pay',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF5B50E6),
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Home'),
            Tab(text: 'History'),
            Tab(text: 'UPI ID'),
          ],
        ),
      ),
      body: _isLoadingUser
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF5B50E6)),
            )
          : TabBarView(
              controller: _tabController,
              children: [_buildHomeTab(), _buildHistoryTab(), _buildUpiTab()],
            ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // UPI Account Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5B50E6).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'UPI Powered',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _currentUser?.name.isNotEmpty == true
                      ? _currentUser!.name
                      : 'My Account',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _showEditMyUpiIdDialog,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'UPI ID: $_myUpiId',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.edit_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _showSendMoneyDialog,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Send Money'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF5B50E6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _showMyQrDialog,
                      icon: const Icon(Icons.qr_code_rounded, size: 16),
                      label: const Text('My QR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Quick Actions Grid
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionCard(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Scan QR',
                  subtitle: 'Pay any UPI QR',
                  color: const Color(0xFF10B981),
                  onTap: _scanUpiQr,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionCard(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'Pay to UPI',
                  subtitle: 'Enter UPI ID / No.',
                  color: const Color(0xFF5B50E6),
                  onTap: _showSendMoneyDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Security & Safety Notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF10B981),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% Secure UPI Payments',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Transactions are secured with your bank UPI PIN.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // REAL TRANSACTION HISTORY STREAM (FROM FIRESTORE)
  // ============================================================

  Widget _buildHistoryTab() {
    final uid = _userService.currentUserId;
    if (uid == null) {
      return const Center(child: Text('Please log in to view history'));
    }

    return Column(
      children: [
        // Filter Chips Bar (All / Sent / Received)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _buildHistoryFilterChip('All', 'all'),
              const SizedBox(width: 8),
              _buildHistoryFilterChip('Sent (Debited)', 'sent'),
              const SizedBox(width: 8),
              _buildHistoryFilterChip('Received', 'received'),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: Colors.grey,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (val) {
                  if (val == 'clear_all') _showClearHistoryDialog(uid, false);
                  if (val == 'clear_failed') _showClearHistoryDialog(uid, true);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'clear_failed',
                    child: Text(
                      'Clear Failed Attempts',
                      style: TextStyle(fontSize: 13.5),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear_all',
                    child: Text(
                      'Clear All History',
                      style: TextStyle(fontSize: 13.5, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('users')
                .doc(uid)
                .collection('transactions')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF5B50E6)),
                );
              }

              final allDocs = snapshot.data?.docs ?? [];

              // Filter docs based on selected tab chip
              final docs = allDocs.where((doc) {
                if (_historyFilter == 'all') return true;
                final type = doc.data()['type']?.toString() ?? 'sent';
                return type == _historyFilter;
              }).toList();

              // Genuine Empty State for New Users
              if (docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5B50E6)
                                .withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            size: 38,
                            color: Color(0xFF5B50E6),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _historyFilter == 'all'
                              ? 'No Transactions Yet'
                              : (_historyFilter == 'sent'
                                    ? 'No Sent Transactions'
                                    : 'No Received Transactions'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Transactions done via ChatApp Pay or received from other users will appear here live.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _showSendMoneyDialog,
                          icon: const Icon(Icons.send_rounded, size: 16),
                          label: const Text('Send Payment'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5B50E6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final type = data['type']?.toString() ?? 'sent';
                  final isReceived = type == 'received';

                  final name = isReceived
                      ? (data['senderName']?.toString().isNotEmpty == true
                            ? data['senderName']
                            : (data['senderUpi'] ?? 'Payment Received'))
                      : (data['receiverName']?.toString().isNotEmpty == true
                            ? data['receiverName']
                            : (data['receiverUpi'] ?? 'UPI Transaction'));

                  final upi = isReceived
                      ? (data['senderUpi']?.toString() ?? '')
                      : (data['receiverUpi']?.toString() ?? '');

                  final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                  final status = data['status']?.toString() ?? 'Completed';
                  final note = data['note']?.toString() ?? '';

                  DateTime? time;
                  if (data['createdAt'] is Timestamp) {
                    time = (data['createdAt'] as Timestamp).toDate();
                  }

                  final timeStr = time != null
                      ? '${time.day}/${time.month}/${time.year} • ${time.hour}:${time.minute.toString().padLeft(2, '0')}'
                      : 'Recent';

                  final Color statusBg;
                  final Color statusColor;
                  final String statusLabel;

                  if (status == 'Completed') {
                    statusBg = const Color(0xFFDCFCE7);
                    statusColor = const Color(0xFF15803D);
                    statusLabel = 'Completed ✓';
                  } else if (status == 'Failed') {
                    statusBg = const Color(0xFFFEE2E2);
                    statusColor = const Color(0xFFB91C1C);
                    statusLabel = 'Failed ✗';
                  } else {
                    statusBg = const Color(0xFFFEF3C7);
                    statusColor = const Color(0xFFB45309);
                    statusLabel = 'Pending ⏳';
                  }

                  return InkWell(
                    onTap: () => _showTransactionDetailsModal(doc.id, data),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Direction-aware circle icon
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isReceived
                                  ? const Color(0xFF10B981)
                                        .withValues(alpha: 0.12)
                                  : const Color(0xFFEF4444)
                                        .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isReceived
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: isReceived
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (note.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    note,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  '${isReceived ? "From" : "To"}: $upi • $timeStr',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isReceived ? "+" : "-"}₹ ${amount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isReceived
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryFilterChip(String label, String value) {
    final isSelected = _historyFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _historyFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5B50E6) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TRANSACTION DETAILS & MANAGEMENT MODAL (STATUS & DELETE)
  // ============================================================

  void _showTransactionDetailsModal(String docId, Map<String, dynamic> data) {
    final uid = _userService.currentUserId;
    if (uid == null) return;

    final type = data['type']?.toString() ?? 'sent';
    final isReceived = type == 'received';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final status = data['status']?.toString() ?? 'Completed';
    final receiverName = data['receiverName']?.toString() ?? '';
    final receiverUpi = data['receiverUpi']?.toString() ?? '';
    final senderName = data['senderName']?.toString() ?? '';
    final senderUpi = data['senderUpi']?.toString() ?? '';
    final note = data['note']?.toString() ?? '';

    DateTime? time;
    if (data['createdAt'] is Timestamp) {
      time = (data['createdAt'] as Timestamp).toDate();
    }
    final timeStr = time != null
        ? '${time.day}/${time.month}/${time.year} at ${time.hour}:${time.minute.toString().padLeft(2, '0')}'
        : 'Recent';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isReceived
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isReceived
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: isReceived
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReceived ? 'Payment Received' : 'Payment Sent',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${isReceived ? "+" : "-"}₹ ${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: isReceived
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildDetailRow('Status', status),
            _buildDetailRow(
              isReceived ? 'From' : 'To Name',
              isReceived ? senderName : receiverName,
            ),
            _buildDetailRow(
              isReceived ? 'Sender UPI' : 'Receiver UPI',
              isReceived ? senderUpi : receiverUpi,
            ),
            if (note.isNotEmpty) _buildDetailRow('Note', note),
            _buildDetailRow(
              'Transaction Ref',
              docId
                  .substring(0, (docId.length > 8 ? 8 : docId.length))
                  .toUpperCase(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _firestore
                          .collection('users')
                          .doc(uid)
                          .collection('transactions')
                          .doc(docId)
                          .delete();
                      _showSnack('Transaction record deleted ✓');
                    },
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    label: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final newStatus = status == 'Completed'
                          ? 'Failed'
                          : 'Completed';
                      await _firestore
                          .collection('users')
                          .doc(uid)
                          .collection('transactions')
                          .doc(docId)
                          .update({'status': newStatus});
                      _showSnack('Status updated to $newStatus ✓');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B50E6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      status == 'Completed' ? 'Mark Failed' : 'Mark Completed',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog(String uid, bool onlyFailed) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          onlyFailed
              ? 'Clear Failed Attempts?'
              : 'Clear All Transaction History?',
        ),
        content: Text(
          onlyFailed
              ? 'This will remove all failed or cancelled payment entries from your history.'
              : 'This will wipe all records from your transaction history. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final query = onlyFailed
                  ? await _firestore
                        .collection('users')
                        .doc(uid)
                        .collection('transactions')
                        .where('status', isEqualTo: 'Failed')
                        .get()
                  : await _firestore
                        .collection('users')
                        .doc(uid)
                        .collection('transactions')
                        .get();

              for (final doc in query.docs) {
                await doc.reference.delete();
              }
              _showSnack(
                onlyFailed
                    ? 'Failed entries removed ✓'
                    : 'Transaction history cleared ✓',
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showEditMyUpiIdDialog() {
    final controller = TextEditingController(text: _myUpiId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              color: Color(0xFF5B50E6),
            ),
            SizedBox(width: 8),
            Text(
              'Set Your UPI ID',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your personal UPI ID (GPay / PhonePe / Paytm / Bank) to receive money:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'e.g. dhivya032005-1@okhdfcbank',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final newUpi = controller.text.trim();
              if (newUpi.isNotEmpty && _currentUser != null) {
                Navigator.pop(ctx);
                await _userService.saveUserProfile(
                  name: _currentUser!.name,
                  phoneNumber: _currentUser!.phoneNumber,
                  avatarUrl: _currentUser!.avatarUrl,
                  about: _currentUser!.about,
                  upiId: newUpi,
                );
                await _loadUser();
                _showSnack('UPI ID updated to $newUpi ✓');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UPI ID & DETAILS TAB
  // ============================================================

  Widget _buildUpiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Registered UPI ID',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    InkWell(
                      onTap: _showEditMyUpiIdDialog,
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: Color(0xFF5B50E6),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF5B50E6),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _myUpiId,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5B50E6),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.copy_rounded,
                        color: Color(0xFF5B50E6),
                        size: 20,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _myUpiId));
                        _showSnack('UPI ID copied to clipboard ✓');
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_android_rounded,
                      color: Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Linked Phone: ${_currentUser?.phoneNumber ?? "Not linked"}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showMyQrDialog,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Show Payment QR Code'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _showEditMyUpiIdDialog,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Change / Customise UPI ID'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF5B50E6),
              side: const BorderSide(color: Color(0xFF5B50E6)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
