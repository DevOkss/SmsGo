package com.example.smsgo

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receives SMS sent broadcast results and forwards them to Flutter.
 */
class SentReceiver : BroadcastReceiver() {

    companion object {
        const val TAG = "SentReceiver"
        var channel: io.flutter.plugin.common.MethodChannel? = null

        fun createPendingIntent(context: Context, requestId: Int, phone: String): PendingIntent {
            val intent = Intent(context, SentReceiver::class.java).apply {
                putExtra("requestId", requestId)
                putExtra("phone", phone)
            }
            return PendingIntent.getBroadcast(
                context,
                requestId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val requestId = intent.getIntExtra("requestId", -1)
        val phone = intent.getStringExtra("phone") ?: ""
        val result = resultCode

        val success = result == Activity.RESULT_OK
        Log.i(TAG, "SMS send result: requestId=$requestId phone=$phone success=$success resultCode=$result")

        try {
            channel?.invokeMethod("smsSendResult", hashMapOf(
                "requestId" to requestId,
                "phone" to phone,
                "success" to success
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to invoke smsSendResult: ${e.message}")
        }
    }
}
