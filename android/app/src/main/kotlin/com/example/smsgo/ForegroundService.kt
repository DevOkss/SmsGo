package com.example.smsgo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class ForegroundService : android.app.Service() {

    companion object {
        const val CHANNEL_ID = "smsgo_bulk_sending"
        const val NOTIFICATION_ID = 888
        const val ACTION_PAUSE = "com.example.smsgo.PAUSE"
        const val ACTION_STOP = "com.example.smsgo.STOP"

        private var channel: MethodChannel? = null
        private var flutterEngine: FlutterEngine? = null

        fun sendProgressUpdate(campaignName: String, sent: Int, total: Int, status: String) {
            channel?.invokeMethod("onProgressUpdate", {
                mapOf(
                    "campaignName" to campaignName,
                    "sent" to sent,
                    "total" to total,
                    "status" to status
                )
            })
        }
    }

    private var isRunning = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> {
                channel?.invokeMethod("onPause", null)
            }
            ACTION_STOP -> {
                channel?.invokeMethod("onStop", null)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        val campaignName = intent?.getStringExtra("campaignName") ?: "SMSGo"
        val sent = intent?.getIntExtra("sent", 0) ?: 0
        val total = intent?.getIntExtra("total", 0) ?: 0
        val status = intent?.getStringExtra("status") ?: "Sending"

        val notification = buildNotification(campaignName, sent, total, status)
        startForeground(NOTIFICATION_ID, notification)

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Bulk Sending",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows bulk sending progress"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(
        campaignName: String,
        sent: Int,
        total: Int,
        status: String
    ): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Pause action
        val pauseIntent = Intent(this, ForegroundService::class.java).apply {
            action = ACTION_PAUSE
        }
        val pausePendingIntent = PendingIntent.getService(
            this,
            1,
            pauseIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        // Stop action
        val stopIntent = Intent(this, ForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            2,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SMSGo Bulk Sending")
            .setContentText("$campaignName\n$status: $sent / $total")
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(
                if (status == "Paused") android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                if (status == "Paused") "Resume" else "Pause",
                pausePendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            )
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("$campaignName\n$status: $sent / $total"))
            .build()
    }
}
