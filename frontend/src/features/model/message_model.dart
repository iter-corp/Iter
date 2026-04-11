class MessageModel {
  final String name;
  final String avatar;
  final String lastMessage;
  final String time;
  final bool hasUnread;
  final bool isRequest;

  const MessageModel({
    required this.name,
    required this.avatar,
    required this.lastMessage,
    required this.time,
    this.hasUnread = false,
    this.isRequest = false,
  });
}