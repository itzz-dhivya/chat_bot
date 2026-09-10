import 'package:flutter/material.dart';

typedef OnCreateEventCallback = void Function({
  required String title,
  required DateTime date,
  required TimeOfDay time,
  String? location,
  String? description,
});

class WhatsAppEventDialog extends StatefulWidget {
  final OnCreateEventCallback onCreateEvent;

  const WhatsAppEventDialog({
    super.key,
    required this.onCreateEvent,
  });

  @override
  State<WhatsAppEventDialog> createState() => _WhatsAppEventDialogState();
}

class _WhatsAppEventDialogState extends State<WhatsAppEventDialog> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Default to CURRENT DATE and CURRENT TIME
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedTime = TimeOfDay.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String _formatDisplayDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    String prefix = '';
    if (_isSameDay(dt, today)) {
      prefix = 'Today, ';
    } else if (_isSameDay(dt, tomorrow)) {
      prefix = 'Tomorrow, ';
    } else {
      prefix = '${_getDayName(dt.weekday)}, ';
    }

    return '$prefix${dt.day} ${_getMonthName(dt.month)} ${dt.year}';
  }

  String _formatDisplayTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    final min = t.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: 'SELECT EVENT DATE',
      confirmText: 'SELECT',
      cancelText: 'CANCEL',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF5B50E6),
              onPrimary: Colors.white,
              onSurface: Color(0xFF171B2D),
              surface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'SELECT EVENT TIME',
      confirmText: 'SET',
      cancelText: 'CANCEL',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF5B50E6),
              onPrimary: Colors.white,
              onSurface: Color(0xFF171B2D),
              surface: Colors.white,
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final title = _titleController.text.trim();
      final location = _locationController.text.trim();
      final desc = _descController.text.trim();

      widget.onCreateEvent(
        title: title,
        date: _selectedDate,
        time: _selectedTime,
        location: location.isNotEmpty ? location : null,
        description: desc.isNotEmpty ? desc : null,
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      elevation: 12,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Calendar badge
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF5B50E6).withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5B50E6).withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: const BoxDecoration(
                              color: Color(0xFF5B50E6),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
                            ),
                            child: Text(
                              _getMonthName(_selectedDate.month).toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                _selectedDate.day.toString(),
                                style: const TextStyle(
                                  color: Color(0xFF171B2D),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Event',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF171B2D),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Plan a meetup, call, or reminder',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Event Title Input
                const Text(
                  'Event Name *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF171B2D),
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _titleController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF171B2D)),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter event name';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'e.g. Project Review, Birthday, Lunch Meet',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    prefixIcon: const Icon(Icons.event_note_rounded, color: Color(0xFF5B50E6), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF4F6FC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.8),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Quick Date Pills (Today, Tomorrow, Weekend, Calendar)
                Row(
                  children: [
                    _buildDateChip(
                      label: 'Today',
                      isSelected: _isSameDay(_selectedDate, today),
                      onTap: () {
                        setState(() => _selectedDate = today);
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildDateChip(
                      label: 'Tomorrow',
                      isSelected: _isSameDay(_selectedDate, tomorrow),
                      onTap: () {
                        setState(() => _selectedDate = tomorrow);
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildDateChip(
                      label: 'Calendar',
                      icon: Icons.date_range_rounded,
                      isSelected: !_isSameDay(_selectedDate, today) && !_isSameDay(_selectedDate, tomorrow),
                      onTap: _pickDate,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Interactive Date & Time Cards
                Row(
                  children: [
                    // Date Selector Card
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6FC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF5B50E6).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF5B50E6).withValues(alpha: 0.25)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF5B50E6),
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                                      ),
                                      child: Text(
                                        _getMonthName(_selectedDate.month).toUpperCase(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          _selectedDate.day.toString(),
                                          style: const TextStyle(
                                            color: Color(0xFF171B2D),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Date',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDisplayDate(_selectedDate),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF171B2D),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Time Selector Card
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _pickTime,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6FC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF5B50E6).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.access_time_rounded,
                                    color: Color(0xFF7C3AED),
                                    size: 19,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Time',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDisplayTime(_selectedTime),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF171B2D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Location field (optional)
                TextFormField(
                  controller: _locationController,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF171B2D)),
                  decoration: InputDecoration(
                    hintText: 'Location / Link (e.g. Google Meet, Cafe)',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.location_on_outlined, color: Colors.grey, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF4F6FC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Description field (optional)
                TextFormField(
                  controller: _descController,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF171B2D)),
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Description or notes (optional)',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.notes_rounded, color: Colors.grey, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF4F6FC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Actions: Cancel & Create Event
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B50E6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: const Text(
                        'Create Event',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateChip({
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF5B50E6)
              : const Color(0xFFF4F6FC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF5B50E6)
                : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF171B2D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
