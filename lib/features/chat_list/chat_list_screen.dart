// lib/features/chat_list/chat_list_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/chat_service.dart';
import '../../state/auth_provider.dart';
import '../chat/chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  final ChatService chatService;
  const ChatListScreen({super.key, required this.chatService});

  // --------------------------
  // SHOW UID POPUP
  // --------------------------
  void _showUidDialog(BuildContext context, String uid) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Your UID"),
        content: SelectableText(uid),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.user!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showUidDialog(context, uid),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.logout(),
          ),
        ],
      ),

      // --------------------------
      // CHAT LIST STREAM
      // --------------------------
      body: StreamBuilder<QuerySnapshot>(
        stream: chatService.userConversations(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Error loading chats:\n${snapshot.error}"),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text("No chats yet"));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final lastMessage = data["lastMessage"] ?? "";
              final ts = data["lastMessageAt"] as Timestamp?;

              final members = List<String>.from(data["members"] ?? []);
              final isGroup = data["isGroup"] ?? false;

              // Determine title
              String title;
              if (isGroup) {
                title = data["name"] ?? "Unnamed Group";
              } else {
                final otherUser =
                    members.firstWhere((m) => m != uid, orElse: () => uid);
                title = "Chat with $otherUser";
              }

              final time = ts != null
                  ? "${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}"
                  : "";

              return ListTile(
                title: Text(title),
                subtitle: Text(lastMessage),
                trailing: Text(time),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(conversationId: doc.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),

      // --------------------------
      // CREATE NEW CHAT (ENTER UID)
      // --------------------------
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final otherUid = await showDialog<String>(
            context: context,
            builder: (context) {
              final controller = TextEditingController();
              return AlertDialog(
                title: const Text("Start chat"),
                content: TextField(
                  controller: controller,
                  decoration:
                      const InputDecoration(hintText: "Enter user UID"),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text("Start"),
                  ),
                ],
              );
            },
          );

          if (otherUid != null && otherUid.isNotEmpty) {
            final convoId = await chatService.createConversation(uid, otherUid);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(conversationId: convoId),
              ),
            );
          }
        },
      ),
    );
  }
}
