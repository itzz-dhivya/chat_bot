const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Triggered when a new call document is created in Firestore.
 * Sends a high-priority FCM notification to the receiver device.
 */
exports.onCallCreated = onDocumentCreated("calls/{callId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const data = snapshot.data();
  const receiverId = data.receiverId;
  const callerName = data.callerName || "Someone";
  const callerPhone = data.callerPhone || "";
  const callType = data.type || "voice"; // voice or video
  const callId = event.params.callId;

  if (!receiverId) return;

  try {
    // Get receiver's FCM Token from user collection
    const userDoc = await admin.firestore().collection("user").doc(receiverId).get();
    if (!userDoc.exists) return;

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;

    if (!fcmToken) return;

    const payload = {
      token: fcmToken,
      notification: {
        title: callType === "video" ? "📹 Incoming Video Call" : "📞 Incoming Voice Call",
        body: `${callerName} is calling you...`,
      },
      data: {
        type: "incoming_call",
        callId: callId,
        callerName: callerName,
        callerPhone: callerPhone,
        callType: callType,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "incoming_calls_channel",
          priority: "max",
          sound: "default",
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            "content-available": 1,
          },
        },
      },
    };

    await admin.messaging().send(payload);
    console.log(`Call notification sent to ${receiverId}`);
  } catch (error) {
    console.error("Error sending call notification:", error);
  }
});

/**
 * Triggered when a new message is sent in any chat.
 * Sends a push notification to the recipient.
 */
exports.onMessageCreated = onDocumentCreated("chats/{chatId}/messages/{messageId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const data = snapshot.data();
  // Skip call-type messages
  if (data.type === "call") return;

  const receiverId = data.receiverId;
  const senderId = data.senderId;
  const messageText = data.message || "New message";

  if (!receiverId) return;

  try {
    const receiverDoc = await admin.firestore().collection("user").doc(receiverId).get();
    if (!receiverDoc.exists) return;

    const senderDoc = await admin.firestore().collection("user").doc(senderId).get();
    const senderName = senderDoc.exists ? (senderDoc.data().name || "Contact") : "Contact";

    const fcmToken = receiverDoc.data().fcmToken;
    if (!fcmToken) return;

    const payload = {
      token: fcmToken,
      notification: {
        title: `💬 ${senderName}`,
        body: messageText,
      },
      data: {
        type: "chat_message",
        senderId: senderId,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "chat_messages_channel",
          priority: "high",
          sound: "default",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    await admin.messaging().send(payload);
    console.log(`Message notification sent to ${receiverId}`);
  } catch (error) {
    console.error("Error sending message notification:", error);
  }
});
