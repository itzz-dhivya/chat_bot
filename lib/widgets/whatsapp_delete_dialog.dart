import 'package:flutter/material.dart';

class WhatsAppDeleteMessageDialog extends StatelessWidget {
  final VoidCallback onDeleteForEveryone;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onCancel;

  const WhatsAppDeleteMessageDialog({
    super.key,
    required this.onDeleteForEveryone,
    required this.onDeleteForMe,
    this.onCancel,
  });

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onDeleteForEveryone,
    required VoidCallback onDeleteForMe,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => WhatsAppDeleteMessageDialog(
        onDeleteForEveryone: () {
          Navigator.pop(ctx);
          onDeleteForEveryone();
        },
        onDeleteForMe: () {
          Navigator.pop(ctx);
          onDeleteForMe();
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      elevation: 12,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Delete message?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF171B2D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'You can delete this message for everyone or delete it for yourself only.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Option 1: Delete for everyone
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onDeleteForEveryone,
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text(
                  'Delete for everyone',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Option 2: Delete for me
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF4F6FC),
                  foregroundColor: const Color(0xFF171B2D),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                onPressed: onDeleteForMe,
                icon: const Icon(Icons.person_remove_outlined, size: 18, color: Color(0xFF5B50E6)),
                label: const Text(
                  'Delete for me',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Option 3: Cancel
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: onCancel ?? () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
