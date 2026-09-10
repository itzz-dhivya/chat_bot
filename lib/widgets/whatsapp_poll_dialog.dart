import 'package:flutter/material.dart';

class WhatsAppPollDialog extends StatefulWidget {
  final Function(String question, List<String> options, bool allowMultiple) onCreatePoll;

  const WhatsAppPollDialog({
    super.key,
    required this.onCreatePoll,
  });

  @override
  State<WhatsAppPollDialog> createState() => _WhatsAppPollDialogState();
}

class _WhatsAppPollDialogState extends State<WhatsAppPollDialog> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;

  void _addOption() {
    if (_optionControllers.length < 12) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > 2) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  void _submit() {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a question')),
      );
      return;
    }

    final validOptions = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (validOptions.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least 2 options')),
      );
      return;
    }

    widget.onCreatePoll(question, validOptions, _allowMultiple);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2C34),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Create Poll',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Question field
              const Text(
                'Question',
                style: TextStyle(color: Color(0xFF00A884), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _questionController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ask a question...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF2A3942),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Options field
              const Text(
                'Options',
                style: TextStyle(color: Color(0xFF00A884), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),

              ...List.generate(_optionControllers.length, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _optionControllers[index],
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Option ${index + 1}',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: const Color(0xFF2A3942),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (_optionControllers.length > 2)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                          onPressed: () => _removeOption(index),
                        ),
                    ],
                  ),
                );
              }),

              if (_optionControllers.length < 12)
                TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add, color: Color(0xFF00A884)),
                  label: const Text('Add option', style: TextStyle(color: Color(0xFF00A884))),
                ),

              const SizedBox(height: 10),
              const Divider(color: Color(0xFF2A3942)),

              // Multiple answers switch
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Allow multiple answers',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  Switch(
                    value: _allowMultiple,
                    activeThumbColor: const Color(0xFF00A884),
                    onChanged: (val) {
                      setState(() {
                        _allowMultiple = val;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _submit,
                  child: const Text('Create Poll', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
