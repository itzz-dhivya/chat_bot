import 'package:flutter/material.dart';

class WhatsAppEmojiPicker extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onEmojiSelected;
  final VoidCallback? onBackspace;
  final bool isDark;

  const WhatsAppEmojiPicker({
    super.key,
    required this.controller,
    this.onEmojiSelected,
    this.onBackspace,
    this.isDark = false,
  });

  @override
  State<WhatsAppEmojiPicker> createState() => _WhatsAppEmojiPickerState();
}

class _WhatsAppEmojiPickerState extends State<WhatsAppEmojiPicker> {
  int _selectedTabIndex = 0; // 0: Emoji, 1: GIF, 2: Sticker
  int _selectedCategoryIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  static const List<String> recentEmojis = [
    '😀', '😂', '🤣', '😍', '🥰', '😘', '😋', '😎', '🥳', '🥺',
    '😭', '😱', '👍', '❤️', '🔥', '🎉', '🙏', '👏', '💯', '✨',
    '💪', '🙌', '👀', '🤔', '😴', '🤤', '🤯', '🤩', '😡', '💀',
  ];

  static const Map<String, List<String>> emojiCategories = {
    'Smileys & Emotion': [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
      '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
      '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
      '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
      '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮',
      '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓',
      '🧐', '😕', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺', '😦',
      '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞',
      '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿',
      '💀', '☠️', '💩', '🤡', '👻', '👽', '🤖', '🎃',
    ],
    'People & Body': [
      '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤏', '✌️', '🤞', '🤟',
      '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎',
      '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏',
      '✍️', '💅', '🤳', '💪', '🦾', '🦿', '🦵', '🦶', '👂', '🦻',
      '👃', '🧠', '🫀', '🫁', '🦷', '🦴', '👀', '👁️', '👅', '👄',
    ],
    'Animals & Nature': [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
      '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🐤', '🦆',
      '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋',
      '🐌', '🐞', '🐜', '🦟', '🐢', '🐍', '🦎', '🐙', '🦑', '🦐',
      '🦞', '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '🦈', '🐊', '🐅',
      '🐆', '🦓', '🦍', '🦧', '🐘', '🦛', '🦏', '🐪', '🐫', '🦒',
      '🦘', '🐃', '🐂', '🐄', '🐎', '🐖', '🐏', '🐑', '🦙', '🐐',
      '🦌', '🐕', '🐩', '🦮', '🐕‍🦺', '🐈', '🐓', '🦃', '🦚', '🦜',
      '🌸', '💮', '🏵️', '🌹', '🥀', '🌺', '🌻', '🌼', '🌷', '🌱',
      '🌲', '🌳', '🌴', '🌵', '🌾', '🌿', '☘️', '🍀', '🍁', '🍂',
    ],
    'Food & Drink': [
      '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
      '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🥑', '🥦',
      '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅', '🥔',
      '🍠', '🥐', '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳', '🧈',
      '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🦴', '🌭', '🍔', '🍟',
      '🍕', '🫓', '🥪', '🥙', '🧆', '🌮', '🌯', '🫔', '🥗', '🥘',
      '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🍤', '🍙', '🍚',
      '🍘', '🍥', '🥠', '🥮', '🍢', '🍡', '🍧', '🍨', '🍦', '🥧',
      '🧁', '🍰', '🎂', '🍮', '🍭', '🍬', '🍫', '🍿', '🍩', '🍪',
      '☕', '🫖', '🍵', '🍶', '🍾', '🍷', '🍸', '🍹', '🍺', '🍻',
    ],
    'Activities': [
      '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
      '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳',
      '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷',
      '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️', '🤼', '🤸', '⛹️',
      '🤺', '🤾', '🏌️', '🏇', '🧘', '🏄', '🏊', '🤽', '🚣', '🧗',
    ],
    'Travel & Places': [
      '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐',
      '🛻', '🚚', '🚛', '🚜', '🛵', '🏍️', '🛺', '🚲', '🛴', '🚨',
      '🚔', '🚍', '🚘', '🚖', '🚡', '🚠', '🚟', '🚃', '🚋', '🚞',
      '🚝', '🚄', '🚅', '🚈', '🚂', '🚆', '🚇', '🚊', '🚉', '✈️',
      '🛫', '🛬', '🛩️', '💺', '🛰️', '🚀', '🛸', '🚁', '🛶', '⛵',
    ],
    'Objects': [
      '⌚', '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', '🕹️',
      '🗜️', '💽', '💾', '💿', '📀', '📼', '📷', '📸', '📹', '🎥',
      '📽️', '🎞️', '📞', '☎️', '📟', '📠', '📺', '📻', '🎙️', '🎚️',
      '🎛️', '🧭', '⏱️', '⏲️', '⏰', '🕰️', '⌛', '⏳', '📡', '🔋',
      '💡', '🔦', '🕯️', '🪔', '🧯', '🛢️', '💸', '💵', '💴', '💶',
    ],
    'Symbols': [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
      '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '☮️',
      '✝️', '☪️', '🕉️', '☸️', '✡️', '🔯', '🕎', '☯️', '☦️', '🛐',
      '⛎', '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐',
      '♑', '♒', '♓', '🆔', '⚛️', '🉑', '☢️', '☣️', '📴', '📳',
      '🈶', '🈚', '🈸', '🈺', '🈷️', '✴️', '📶', '📳', '📴', '💯',
    ],
    'Flags': [
      '🏁', '🚩', '🎌', '🏴', '🏳️', '🏳️‍🌈', '🏳️‍⚧️', '🏴‍☠️', '🇮🇳', '🇺🇸',
      '🇬🇧', '🇨🇦', '🇦🇺', '🇩🇪', '🇫🇷', '🇮🇹', '🇯🇵', '🇰🇷', '🇧🇷', '🇲🇽',
    ],
  };

  void _insertEmoji(String emoji) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (selection.isValid && selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + emoji.length),
      );
    } else {
      widget.controller.text = text + emoji;
      widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    }

    widget.onEmojiSelected?.call();
  }

  void _handleBackspace() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (text.isEmpty) return;

    if (selection.isValid && selection.start >= 0) {
      if (selection.start == selection.end && selection.start > 0) {
        final chars = text.characters;
        if (chars.isNotEmpty) {
          final newChars = chars.take(chars.length - 1).toString();
          widget.controller.value = TextEditingValue(
            text: newChars,
            selection: TextSelection.collapsed(offset: newChars.length),
          );
        }
      } else if (selection.start != selection.end) {
        final newText = text.replaceRange(selection.start, selection.end, '');
        widget.controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.start),
        );
      }
    } else {
      final chars = text.characters;
      if (chars.isNotEmpty) {
        final newChars = chars.take(chars.length - 1).toString();
        widget.controller.value = TextEditingValue(
          text: newChars,
          selection: TextSelection.collapsed(offset: newChars.length),
        );
      }
    }

    widget.onBackspace?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1F2C34) : Colors.white;
    final borderColor = widget.isDark ? const Color(0xFF2A3942) : const Color(0xFFE2E8F0);
    final bottomBarColor = widget.isDark ? const Color(0xFF182229) : const Color(0xFFF8FAFC);
    final primaryColor = const Color(0xFF5B50E6);

    return Container(
      height: 290,
      color: bgColor,
      child: Column(
        children: [
          // Top bar: Search, Tabs, Backspace
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor, width: 1)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isSearching ? Icons.close_rounded : Icons.search_rounded,
                    color: Colors.grey.shade600,
                    size: 22,
                  ),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchQuery = '';
                        _searchController.clear();
                      }
                    });
                  },
                ),
                if (_isSearching)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : const Color(0xFF171B2D),
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search emoji...',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                        border: InputBorder.none,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.toLowerCase().trim();
                        });
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTabButton(0, Icons.sentiment_satisfied_alt_rounded, primaryColor),
                        const SizedBox(width: 8),
                        _buildTabButton(1, null, primaryColor, label: 'GIF'),
                        const SizedBox(width: 8),
                        _buildTabButton(2, Icons.sticky_note_2_outlined, primaryColor),
                      ],
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.backspace_outlined, color: Colors.grey.shade600, size: 20),
                  onPressed: _handleBackspace,
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildEmojiGrid()
                : _selectedTabIndex == 1
                    ? _buildGifPlaceholder()
                    : _buildStickerPlaceholder(),
          ),

          // Bottom Category Selector
          if (_selectedTabIndex == 0 && !_isSearching)
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: bottomBarColor,
                border: Border(top: BorderSide(color: borderColor, width: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCategoryIcon(0, Icons.access_time_rounded, primaryColor),
                  _buildCategoryIcon(1, Icons.sentiment_satisfied_rounded, primaryColor),
                  _buildCategoryIcon(2, Icons.nature_people_rounded, primaryColor),
                  _buildCategoryIcon(3, Icons.restaurant_rounded, primaryColor),
                  _buildCategoryIcon(4, Icons.sports_soccer_rounded, primaryColor),
                  _buildCategoryIcon(5, Icons.directions_car_rounded, primaryColor),
                  _buildCategoryIcon(6, Icons.lightbulb_outline_rounded, primaryColor),
                  _buildCategoryIcon(7, Icons.tag_rounded, primaryColor),
                  _buildCategoryIcon(8, Icons.flag_rounded, primaryColor),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData? icon, Color primaryColor, {String? label}) {
    final bool isSelected = _selectedTabIndex == index;
    final activeBg = widget.isDark
        ? const Color(0xFF2A3942)
        : const Color(0xFF5B50E6).withValues(alpha: 0.12);

    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: icon != null
            ? Icon(
                icon,
                color: isSelected ? primaryColor : Colors.grey.shade500,
                size: 20,
              )
            : Text(
                label ?? '',
                style: TextStyle(
                  color: isSelected ? primaryColor : Colors.grey.shade500,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
      ),
    );
  }

  Widget _buildCategoryIcon(int index, IconData icon, Color primaryColor) {
    final bool isSelected = _selectedCategoryIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCategoryIndex = index);
        final targetOffset = index * 260.0;
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: isSelected ? Border(bottom: BorderSide(color: primaryColor, width: 3)) : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected ? primaryColor : Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _buildEmojiGrid() {
    if (_isSearching && _searchQuery.isNotEmpty) {
      final allEmojis = emojiCategories.values.expand((list) => list).toSet().toList();
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: allEmojis.length,
        itemBuilder: (context, index) {
          final emoji = allEmojis[index];
          return GestureDetector(
            onTap: () => _insertEmoji(emoji),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
          );
        },
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Text(
            'Recents',
            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        _buildSectionGrid(recentEmojis),
        ...emojiCategories.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                child: Text(
                  entry.key,
                  style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              _buildSectionGrid(entry.value),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildSectionGrid(List<String> emojis) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return InkWell(
          onTap: () => _insertEmoji(emoji),
          borderRadius: BorderRadius.circular(8),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
        );
      },
    );
  }

  Widget _buildGifPlaceholder() {
    final List<String> sampleGifs = [
      '🎉 Congratulations', '👋 Hello!', '❤️ Love you', '😂 LOL', '🔥 Lit',
      '👏 Good job', '🥺 Miss you', '🎂 Happy Birthday', '✨ Awesome',
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.5,
      ),
      itemCount: sampleGifs.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _insertEmoji(sampleGifs[index]),
          child: Container(
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF2A3942) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                sampleGifs[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.isDark ? Colors.white : const Color(0xFF5B50E6),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStickerPlaceholder() {
    final List<String> sampleStickers = [
      '🐱 Cute Cat', '🐶 Happy Pup', '🚀 Rocket', '🍕 Pizza Party',
      '☕ Good Morning', '💤 Sleepy', '🥳 Party Time', '💯 100%',
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: sampleStickers.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => _insertEmoji(sampleStickers[index]),
          child: Container(
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF2A3942) : const Color(0xFFF4EEFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                sampleStickers[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.isDark ? Colors.white70 : const Color(0xFF7C3AED),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
