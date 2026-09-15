import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'realtime_client.dart';

class TypingService {
  /// Set or clear the typing flag for [uid] in [chatId].
  Future<void> setTyping(String chatId, String uid, bool isTyping, {List<String> recipientUids = const []}) async {
    RealtimeClient.instance.setTyping(
      chatId: chatId,
      isTyping: isTyping,
      recipientUids: recipientUids,
    );
  }

  /// Stream whether [otherUid] is currently typing in [chatId].
  Stream<bool> listenTyping(String chatId, String otherUid) {
    return RealtimeClient.instance.typingStream
        .where((event) => event['chatId'] == chatId && event['uid'] == otherUid)
        .map((event) => event['isTyping'] == true)
        .startWith(false);
  }
}
