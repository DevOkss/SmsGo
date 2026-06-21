package com.example.smsgo

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class WapPushReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    try {
      Log.i("SmsGatewayPlugin", "WapPushReceiver received intent: ${intent.action}")

      // Forward to Flutter (best-effort) so the app can react to incoming MMS/WAP pushes
      try {
        val payload: Map<String, Any?> = mapOf(
          "action" to (intent.action ?: ""),
          "extras" to (intent.extras?.keySet()?.toList() ?: emptyList<String>())
        )
        MainActivity.smsChannel?.invokeMethod("mmsReceived", payload)
      } catch (e: Exception) {
        Log.w("SmsGatewayPlugin", "WapPushReceiver: failed to forward to Flutter: ${e.message}")
      }

      // Acknowledge the ordered broadcast so the system marks MMS as delivered
      resultCode = Activity.RESULT_OK
    } catch (e: Exception) {
      // swallow
    }
  }
}
