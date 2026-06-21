package com.example.smsgo

import android.app.IntentService
import android.content.Intent
import android.os.Bundle
import android.telephony.SmsManager
import android.util.Log

/**
 * Handles RESPOND_VIA_MESSAGE intents for the default SMS role.
 *
 * When a user replies to an SMS notification via inline reply, the system sends
 * an intent to this service with the message body and recipient(s). This service
 * is one of the four components required by AOSP for ROLE_SMS qualification.
 *
 * See: packages/modules/Permission/PermissionController/res/xml/roles.xml
 */
class HeadlessSmsSendService : IntentService("HeadlessSmsSendService") {

    override fun onHandleIntent(intent: Intent?) {
        if (intent == null) return

        try {
            val action = intent.action
            if (action != "android.intent.action.RESPOND_VIA_MESSAGE") return

            val extras = intent.extras ?: return

            // Extract message body from the intent
            val messageBody = extras.getCharSequence(Intent.EXTRA_TEXT)?.toString() ?: return

            // Extract recipients from the intent data URI(s)
            val dataUri = intent.data
            if (dataUri != null) {
                val phoneNumber = dataUri.schemeSpecificPart
                if (!phoneNumber.isNullOrEmpty()) {
                    sendSms(phoneNumber, messageBody)
                }
            }

            // Also check for EXTRA_STREAM (for MMS responses)
            // Most SMS responses use the data URI, so this is a secondary path

        } catch (e: Exception) {
            Log.e("HeadlessSmsSendService", "Failed to handle respond-via-message: ${e.message}")
        }
    }

    private fun sendSms(to: String, message: String) {
        try {
            val smsManager = SmsManager.getDefault()
            val parts = smsManager.divideMessage(message)
            if (parts.size == 1) {
                smsManager.sendTextMessage(to, null, parts[0], null, null)
            } else {
                smsManager.sendMultipartTextMessage(to, null, parts, null, null)
            }
            Log.i("HeadlessSmsSendService", "Sent respond-via-message to $to")
        } catch (e: Exception) {
            Log.e("HeadlessSmsSendService", "SMS send failed: ${e.message}")
        }
    }
}
