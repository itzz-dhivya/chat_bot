import 'package:flutter/material.dart';

class WhatsAppAttachmentSheet extends StatelessWidget {
  final VoidCallback onGalleryTap;
  final VoidCallback onCameraTap;
  final VoidCallback onLocationTap;
  final VoidCallback onContactTap;
  final VoidCallback onDocumentTap;
  final VoidCallback onPollTap;
  final VoidCallback onEventTap;
  final VoidCallback? onVideoTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onAiImagesTap;
  final VoidCallback? onPaymentTap;
  final bool isDark;

  const WhatsAppAttachmentSheet({
    super.key,
    required this.onGalleryTap,
    required this.onCameraTap,
    required this.onLocationTap,
    required this.onContactTap,
    required this.onDocumentTap,
    required this.onPollTap,
    required this.onEventTap,
    this.onVideoTap,
    this.onAudioTap,
    this.onAiImagesTap,
    this.onPaymentTap,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final textColor = isDark ? Colors.white70 : const Color(0xFF171B2D);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Row 1: 4 items (Gallery, Video, Camera, Location)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAttachmentItem(
                context,
                icon: Icons.photo_size_select_actual_rounded,
                label: 'Gallery',
                color: const Color(0xFF7F66FF),
                textColor: textColor,
                onTap: onGalleryTap,
              ),
              _buildAttachmentItem(
                context,
                icon: Icons.videocam_rounded,
                label: 'Video',
                color: const Color(0xFFEF4444),
                textColor: textColor,
                onTap: onVideoTap ?? onGalleryTap,
              ),
              _buildAttachmentItem(
                context,
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                color: const Color(0xFFE91E63),
                textColor: textColor,
                onTap: onCameraTap,
              ),
              _buildAttachmentItem(
                context,
                icon: Icons.location_on_rounded,
                label: 'Location',
                color: const Color(0xFF1EA952),
                textColor: textColor,
                onTap: onLocationTap,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Row 2: 4 items (Contact, Document, Poll, Audio)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAttachmentItem(
                context,
                icon: Icons.person_rounded,
                label: 'Contact',
                color: const Color(0xFF007BFF),
                textColor: textColor,
                onTap: onContactTap,
              ),
              _buildAttachmentItem(
                context,
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                color: const Color(0xFF5F33E1),
                textColor: textColor,
                onTap: onDocumentTap,
              ),
              _buildAttachmentItem(
                context,
                icon: Icons.bar_chart_rounded,
                label: 'Poll',
                color: const Color(0xFFFFB300),
                textColor: textColor,
                onTap: onPollTap,
              ),
              _buildAttachmentItem(
                context,
                icon: Icons.headphones_rounded,
                label: 'Audio',
                color: const Color(0xFFFF9800),
                textColor: textColor,
                onTap: onAudioTap ?? onDocumentTap,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Row 3: Payment & Event
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAttachmentItem(
                context,
                icon: Icons.account_balance_wallet_rounded,
                label: 'Payment',
                color: const Color(0xFF10B981),
                textColor: textColor,
                onTap: onPaymentTap ?? () {},
              ),
              _buildAttachmentItem(
                context,
                customIcon: _buildDynamicCalendarIcon(),
                label: 'Event',
                color: const Color(0xFFE53935),
                textColor: textColor,
                onTap: onEventTap,
              ),
              const SizedBox(width: 58),
              const SizedBox(width: 58),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDynamicCalendarIcon() {
    final now = DateTime.now();
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final monthStr = months[now.month - 1];
    final dayStr = now.day.toString();

    return Container(
      width: 32,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 11,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Center(
              child: Text(
                monthStr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  height: 1.0,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                dayStr,
                style: const TextStyle(
                  color: Color(0xFF171B2D),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentItem(
    BuildContext context, {
    IconData? icon,
    Widget? customIcon,
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Center(
              child: customIcon ?? Icon(icon, color: color, size: 27),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
