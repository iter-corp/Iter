import 'package:flutter/material.dart';

class ChatMessage {
  final String text;
  final String time;
  final bool isMe;
  final bool isSeen;

  const ChatMessage({
    required this.text,
    required this.time,
    required this.isMe,
    this.isSeen = false,
  });
}

class ChatScreen extends StatefulWidget {
  final String name;
  final String avatar;

  const ChatScreen({
    super.key,
    required this.name,
    required this.avatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessage> messages = const [
    ChatMessage(
        text: "Hi", time: "9:30", isMe: true, isSeen: true),
    ChatMessage(text: "Hello", time: "9:35", isMe: false),
  ];

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      messages = [
        ...messages,
        ChatMessage(
          text: _controller.text.trim(),
          time: "Now",
          isMe: true,
        ),
      ];
      _controller.clear();
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 22),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(widget.avatar),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        const Text("@jack09",
                            style: TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.videocam_outlined, size: 24),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.call_outlined, size: 22),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            /// MESSAGES
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final msg = messages[i];
                  return _buildMessage(msg);
                },
              ),
            ),
            /// INPUT
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: Colors.grey),
                  ),
                  Expanded(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: "Message...",
                          hintStyle: TextStyle(
                              color: Colors.grey, fontSize: 14),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.mic_outlined,
                        color: Colors.grey),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.image_outlined,
                        color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            msg.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.isMe) ...[
            const CircleAvatar(
              radius: 16,
              backgroundImage: NetworkImage(
                  "https://i.pravatar.cc/150?img=2"),
            ),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: msg.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: msg.isMe
                      ? const Color(0xFFB05ECC)
                      : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                    bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                  ),
                ),
                child: Text(
                  msg.text,
                  style: TextStyle(
                    color: msg.isMe ? Colors.white : Colors.black,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    msg.time,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 11),
                  ),
                  if (msg.isMe && msg.isSeen) ...[
                    const SizedBox(width: 4),
                    const Text(
                      "Seen",
                      style: TextStyle(
                          color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}