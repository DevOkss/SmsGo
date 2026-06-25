package com.example.smsgo

import android.app.Activity
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class SmsReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    try {
      val action = intent.action
      Log.i("SmsReceiver", "onReceive action=$action")

      if (action == "android.provider.Telephony.SMS_DELIVER") {
        val bundle: Bundle? = intent.extras
        val pdus = bundle?.get("pdus") as? Array<*>
        if (pdus == null || pdus.isEmpty()) {
          Log.w("SmsReceiver", "No PDUs in bundle")
          setReceiverResult()
          return
        }

        val format = bundle.getString("format")
        val msgs = mutableListOf<SmsMessage>()
        for (pdu in pdus) {
          val bytes = pdu as? ByteArray ?: continue
          val msg = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            SmsMessage.createFromPdu(bytes, format)
          } else {
            @Suppress("DEPRECATION")
            SmsMessage.createFromPdu(bytes)
          }
          msgs.add(msg)
        }

        val body = msgs.joinToString(separator = "") { it.messageBody ?: "" }
        val from = msgs.firstOrNull()?.originatingAddress ?: ""

        // Determine SIM slot from subscription ID
        var simSlot = ""
        try {
          val subId = bundle?.getInt("subscription_id", -1) ?: -1
          if (subId >= 0 && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP_MR1) {
            val subMgr = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            val subInfoList = subMgr?.activeSubscriptionInfoList
            if (subInfoList != null) {
              for (info in subInfoList) {
                if (info.subscriptionId == subId) {
                  simSlot = if (info.simSlotIndex == 1) "SIM 1" else "SIM 2"
                  break
                }
              }
            }
          }
          if (simSlot.isEmpty()) {
            // Fallback: try to determine from phone count
            simSlot = if (msgs.isNotEmpty()) "SIM 1" else ""
          }
        } catch (e: Exception) {
          Log.w("SmsReceiver", "Failed to determine SIM slot: ${e.message}")
        }

        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        val receivedAt = sdf.format(Date())

        Log.i("SmsReceiver", "SMS received from=$from bodyLength=${body.length} simSlot=$simSlot")

        val payload: HashMap<String, Any> = hashMapOf(
          "from" to from,
          "message" to body,
          "receivedAt" to receivedAt,
          "simSlot" to simSlot
        )

        try {
          val db = RepliesDbHelper(context)
          db.insertReply(from, body, receivedAt)
          Log.i("SmsReceiver", "Persisted SMS to native DB")
        } catch (e: Exception) {
          Log.w("SmsReceiver", "Failed to persist inbound SMS: ${e.message}")
        }

        val channel = MainActivity.smsChannel
        if (channel != null) {
          // Flutter is running — it will handle notification via NotificationService
          try {
            channel.invokeMethod("smsReceived", payload)
            Log.i("SmsReceiver", "Forwarded SMS to Flutter via MethodChannel")
          } catch (e: Exception) {
            Log.w("SmsReceiver", "Failed to forward to Flutter: ${e.message}")
          }
        } else {
          // Flutter is NOT running (app is killed) — show native notification
          Log.i("SmsReceiver", "Flutter not running, showing native notification")
          showNativeNotification(context, from, body)
        }
      }

      setReceiverResult()
    } catch (e: Exception) {
      Log.e("SmsReceiver", "Unexpected error: ${e.message}")
      setReceiverResult()
    }
  }

  private fun setReceiverResult() {
    try {
      resultCode = Activity.RESULT_OK
    } catch (_: Exception) {}
  }

  private fun showNativeNotification(context: Context, from: String, body: String) {
    try {
      val channelId = "sms_incoming"
      val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
      launchIntent?.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

      val pendingIntent = PendingIntent.getActivity(
        context, from.hashCode(), launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
      )

      val builder = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
        android.app.Notification.Builder(context, channelId)
      } else {
        @Suppress("DEPRECATION")
        android.app.Notification.Builder(context)
      }

      val notification = builder
        .setSmallIcon(R.drawable.ic_notification)
        .setContentTitle(from)
        .setContentText(body)
        .setStyle(android.app.Notification.BigTextStyle().bigText(body))
        .setPriority(android.app.Notification.PRIORITY_HIGH)
        .setCategory(android.app.Notification.CATEGORY_MESSAGE)
        .setVisibility(android.app.Notification.VISIBILITY_PUBLIC)
        .setAutoCancel(true)
        .setContentIntent(pendingIntent)
        .build()

      val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.notify(from.hashCode(), notification)
      Log.i("SmsReceiver", "Native notification shown for $from")
    } catch (e: Exception) {
      Log.w("SmsReceiver", "Failed to show native notification: ${e.message}")
    }
  }
}
