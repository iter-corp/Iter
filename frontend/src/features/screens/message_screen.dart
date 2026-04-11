import 'package:flutter/material.dart';
import '../model/message_model.dart';
import '../widgets/message_widget.dart';
import 'chat_screen.dart';
import 'request_screen.dart';


class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: MessageBody(),
    );
  }
}

class MessageBody extends StatefulWidget {
  const MessageBody({super.key});

  @override
  State<MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<MessageBody> {
  int selectedTab = 0;

  final List<MessageModel> allMessages = const [
    MessageModel(
      name: "Zhalian Omar",
      avatar: "https://i.pravatar.cc/150?img=1",
      lastMessage: "Yes that's right .",
      time: "29m",
      hasUnread: true,
    ),
    MessageModel(
      name: "Hike_With_Me",
      avatar: "https://i.pravatar.cc/150?img=2",
      lastMessage: "4+ new messages .",
      time: "2h",
      hasUnread: true,
    ),
    MessageModel(
      name: "Anna.salh",
      avatar: "https://i.pravatar.cc/150?img=3",
      lastMessage: "OK, thank you .",
      time: "6h",
      hasUnread: true,
    ),
    MessageModel(
      name: "Sara Kamal",
      avatar: "https://i.pravatar.cc/150?img=4",
      lastMessage: "sent 10h ago",
      time: "10h",
    ),
    MessageModel(
      name: "Michael",
      avatar: "https://i.pravatar.cc/150?img=5",
      lastMessage: "active 23h ago",
      time: "23h",
    ),
  ];

  final List<MessageModel> requests = const [
    MessageModel(
      name: "Aram Sardar",
      avatar: "https://i.pravatar.cc/150?img=6",
      lastMessage: "Hi .",
      time: "1h",
      hasUnread: true,
      isRequest: true,
    ),
    MessageModel(
      name: "Ahmed Ali",
      avatar: "https://i.pravatar.cc/150?img=7",
      lastMessage: "4+ new messages .",
      time: "22h",
      hasUnread: true,
      isRequest: true,
    ),
    MessageModel(
      name: "Savan_Rahman",
      avatar: "https://i.pravatar.cc/150?img=8",
      lastMessage: "sorry, one question .",
      time: "5d",
      hasUnread: true,
      isRequest: true,
    ),
    MessageModel(
      name: "Shadost",
      avatar: "https://i.pravatar.cc/150?img=9",
      lastMessage: "thanks for sharing this...",
      time: "6d",
      hasUnread: true,
      isRequest: true,
    ),
    MessageModel(
      name: "Hiwa jamal",
      avatar: "https://i.pravatar.cc/150?img=10",
      lastMessage: "Open the previous link .",
      time: "2w",
      hasUnread: true,
      isRequest: true,
    ),
  ];
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: "Search...",
                  hintStyle:
                      TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: Colors.grey),
                ),
              ),
            ),
          ),
          MessageTabBar(
            selectedTab: selectedTab,
            allCount: allMessages.length,
            requestCount: requests.length,
            onTap: (i) => setState(() => selectedTab = i),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: selectedTab == 0
                ? ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: allMessages.length,
                    itemBuilder: (context, i) => MessageTile(
                      message: allMessages[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            name: allMessages[i].name,
                            avatar: allMessages[i].avatar,
                          ),
                        ),
                      ),
                    ),
                  )
                : RequestsTab(
                    requests: requests,
                    onTap: (msg) => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          name: msg.name,
                          avatar: msg.avatar,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
