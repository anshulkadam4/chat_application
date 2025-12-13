import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../core/services/chat_service.dart';
import '../../state/auth_provider.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  Map<String, dynamic> lastReadMap = {};

  @override
  void initState() {
    super.initState();

    // Load conversation metadata ONCE
    FirebaseFirestore.instance
        .collection("conversations")
        .doc(widget.conversationId)
        .snapshots()
        .listen((doc) {
      if (mounted && doc.data() != null) {
        setState(() {
          lastReadMap = doc.data()!["lastRead"] ?? {};
        });
      }
    });

    // Mark as read on open
    Future.microtask(() {
      final chat = Provider.of<ChatService>(context, listen: false);
      chat.markAsRead(widget.conversationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = Provider.of<ChatService>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context);
    final uid = auth.user!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: chat.messagesStream(widget.conversationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final msg = docs[i].data() as Map<String, dynamic>;

                    // Protect against missing fields
                    final String msgId = msg["id"] ?? "";
                    final String messageText = (msg["text"] ?? "").toString();
                    final String senderId = msg["senderId"] ?? "";
                    final bool isMe = senderId == uid;

                    Timestamp? tsRaw = msg["createdAt"];
                    DateTime? ts = tsRaw?.toDate();

                    return _buildMessageBubble(
                      msgId: msgId,
                      messageText: messageText,
                      isMe: isMe,
                      timestamp: ts,
                      msg: msg,
                      chat: chat,
                    );
                  },
                );
              },
            ),
          ),

          const Divider(height: 1),

          _buildInputArea(chat, uid),
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // MESSAGE BUBBLE
  // -------------------------------------------------------

  Widget _buildMessageBubble({
    required String msgId,
    required String messageText,
    required bool isMe,
    required DateTime? timestamp,
    required Map<String, dynamic> msg,
    required ChatService chat,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress:
            isMe ? () => _showMessageOptions(msgId, messageText, chat) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                messageText,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              ),

              if (timestamp != null)
                Text(
                  "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : Colors.black54,
                  ),
                ),

              if (isMe) _readReceiptWidget(msg),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // READ RECEIPTS
  // -------------------------------------------------------

  Widget _readReceiptWidget(Map<String, dynamic> msg) {
    Timestamp? sentAt = msg["createdAt"];
    if (sentAt == null) return const SizedBox();

    bool seen = false;

    lastReadMap.forEach((uid, ts) {
      if (ts is Timestamp &&
          ts.millisecondsSinceEpoch >= sentAt.millisecondsSinceEpoch) {
        seen = true;
      }
    });

    return Text(
      seen ? "Seen" : "Delivered",
      style: const TextStyle(fontSize: 10, color: Colors.white70),
    );
  }

  // -------------------------------------------------------
  // INPUT AREA
  // -------------------------------------------------------

  Widget _buildInputArea(ChatService chat, String uid) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(chat, uid),
                decoration: const InputDecoration(
                  hintText: "Type a message...",
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              onPressed: _sending ? null : () => _sendMessage(chat, uid),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // SEND MESSAGE
  // -------------------------------------------------------

  Future<void> _sendMessage(ChatService chat, String uid) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);

    try {
      await chat.sendMessage(
        conversationId: widget.conversationId,
        senderId: uid,
        text: text,
      );

      chat.markAsRead(widget.conversationId);

      _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // -------------------------------------------------------
  // EDIT / DELETE
  // -------------------------------------------------------

  void _showMessageOptions(String msgId, String oldText, ChatService chat) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text("Edit"),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(msgId, oldText, chat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete"),
              onTap: () async {
                Navigator.pop(context);
                await chat.deleteMessage(
                  conversationId: widget.conversationId,
                  messageId: msgId,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(String msgId, String oldText, ChatService chat) {
    final controller = TextEditingController(text: oldText);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Message"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isNotEmpty) {
                await chat.editMessage(
                  conversationId: widget.conversationId,
                  messageId: msgId,
                  newText: newText,
                );
              }
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}
