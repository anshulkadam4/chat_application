import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser!.uid;

  // ============================================================
  // STREAMS
  // ============================================================

  /// Stream all conversations where the current user is a member.
  Stream<QuerySnapshot> userConversations(String uid) {
    return _db
        .collection('conversations')
        .where('members', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  /// Stream messages inside a conversation.
  Stream<QuerySnapshot> messagesStream(String conversationId) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ============================================================
  // CREATE CONVERSATION
  // ============================================================

  Future<String> createConversation(String uid1, String uid2) async {
    final q = await _db
        .collection('conversations')
        .where('members', arrayContains: uid1)
        .get();

    // Check if 1:1 chat already exists
    for (final doc in q.docs) {
      final members = List<String>.from(doc['members']);
      if (members.contains(uid2) && members.length == 2) {
        return doc.id;
      }
    }

    // Create new conversation
    final ref = await _db.collection('conversations').add({
      'members': [uid1, uid2],
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastRead': {uid1: FieldValue.serverTimestamp()},
    });

    return ref.id;
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();

    final now = FieldValue.serverTimestamp();

    await msgRef.set({
      'id': msgRef.id,
      'senderId': senderId,
      'text': text,
      'createdAt': now,
    });

    // Update conversation preview message
    await _db.collection('conversations').doc(conversationId).update({
      'lastMessage': text,
      'lastMessageAt': now,
    });
  }

  // ============================================================
  // READ RECEIPTS
  // ============================================================

  Future<void> markAsRead(String conversationId) async {
    await _db.collection('conversations').doc(conversationId).update({
      "lastRead.$uid": FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // EDIT MESSAGE
  // ============================================================

  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String newText,
  }) async {
    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);

    await msgRef.update({"text": newText});

    // If edited message is the last message → update preview
    final convoRef = _db.collection('conversations').doc(conversationId);
    final convo = await convoRef.get();

    if (convo.exists && convo['lastMessage'] != null) {
      final messages = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (messages.docs.isNotEmpty &&
          messages.docs.first.id == messageId) {
        await convoRef.update({
          "lastMessage": "$newText (edited)",
        });
      }
    }
  }

  // ============================================================
  // DELETE MESSAGE
  // ============================================================

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);

    await msgRef.delete();

    // Update last message preview (if deleted message was the last)
    final messages = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    final convoRef = _db.collection('conversations').doc(conversationId);

    if (messages.docs.isEmpty) {
      // No messages left
      await convoRef.update({
        "lastMessage": "",
      });
    } else {
      // Update preview with newest remaining message
      final msg = messages.docs.first.data();
      await convoRef.update({
        "lastMessage": msg["text"] ?? "",
      });
    }
  }
}
