package com.example.smsgo

import android.Manifest
import android.net.Uri
import android.os.Build
import android.app.PendingIntent
import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import android.database.Cursor
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import android.telephony.SubscriptionManager
import android.telephony.SignalStrength
import android.telephony.PhoneStateListener
import java.lang.reflect.Method
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoWcdma
import android.telephony.CellInfoCdma
import android.telephony.CellInfoNr
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding


/**
 * Flutter MethodChannel plugin: channel "sms_gateway".
 * Sends SMS via Android SmsManager.
 */
class SmsGatewayPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

  companion object {
    private const val ROLE_SMS_REQUEST = 1001
    private var pendingRoleResult: Result? = null

    @JvmStatic
    fun handleActivityResult(requestCode: Int, resultCode: Int) {
      if (requestCode == ROLE_SMS_REQUEST) {
        val result = pendingRoleResult
        pendingRoleResult = null
        if (result != null) {
          val granted = resultCode == Activity.RESULT_OK
          Log.i("SmsGatewayPlugin", "handleActivityResult: role request resultCode=$resultCode granted=$granted")
          result.success(granted)
        }
      }
    }
  }

  private var channel: MethodChannel? = null
  private var applicationContext: Context? = null
  private var activityBinding: ActivityPluginBinding? = null
  private val signalListeners = mutableMapOf<Int, PhoneStateListener>()
  private var smsRequestCounter = 0

  override fun onAttachedToEngine(binding: FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "sms_gateway")

    // Log registration for debugging (helps diagnose MissingPluginException)
    Log.i("SmsGatewayPlugin", "onAttachedToEngine: registered method channel sms_gateway")

    // Expose a stable reference for BroadcastReceivers that need to forward events.
    MainActivity.smsChannel = channel
    SentReceiver.channel = channel

    channel?.setMethodCallHandler(this)

    // Create notification channel natively (so it's available even when Flutter is cold-starting)
    createNotificationChannel()

    // Start listening for signal-strength changes (best-effort).
    try {
      startSignalListeners()
    } catch (e: Exception) {
      Log.w("SmsGatewayPlugin", "startSignalListeners failed: ${e.message}")
    }
  }

  private fun createNotificationChannel() {
    try {
      val ctx = applicationContext ?: return
      if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
        val channel = android.app.NotificationChannel(
          "sms_incoming",
          "Incoming SMS",
          android.app.NotificationManager.IMPORTANCE_HIGH
        ).apply {
          description = "Notifications for incoming SMS messages"
          enableVibration(true)
          vibrationPattern = longArrayOf(0, 300, 200, 300)
        }
        val nm = ctx.getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        nm.createNotificationChannel(channel)
        Log.i("SmsGatewayPlugin", "Notification channel 'sms_incoming' created")
      }
    } catch (e: Exception) {
      Log.w("SmsGatewayPlugin", "Failed to create notification channel: ${e.message}")
    }
  }


  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
    applicationContext = null
    try {
      stopSignalListeners()
    } catch (e: Exception) {
      // ignore
    }
  }

  private fun startSignalListeners() {
    val ctx = applicationContext ?: return
    val sm = SubscriptionManager.from(ctx)
    val subs = try { sm.activeSubscriptionInfoList } catch (e: Exception) { null }
    if (subs == null || subs.isEmpty()) return

    val baseTm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

    for (info in subs) {
      val subId = info.subscriptionId
      try {
        val tmForSub = try { baseTm.createForSubscriptionId(subId) } catch (e: Exception) { baseTm }
        val listener = object : PhoneStateListener() {
          override fun onSignalStrengthsChanged(ss: SignalStrength) {
            super.onSignalStrengthsChanged(ss)
            val (dbm, asu) = try { readDbmAndAsu(tmForSub, ss) } catch (e: Exception) { Pair(null, null) }
            val payload = mapOf<String, Any?>(
              "subscriptionId" to subId,
              "signalDbm" to dbm,
              "signalAsu" to asu
            )
            try {
              channel?.invokeMethod("simSignalChanged", payload)
            } catch (e: Exception) {
              Log.w("SmsGatewayPlugin", "failed to invoke simSignalChanged: ${e.message}")
            }
          }
        }
        tmForSub.listen(listener, PhoneStateListener.LISTEN_SIGNAL_STRENGTHS)
        signalListeners[subId] = listener
      } catch (e: Exception) {
        // ignore per-subscription failures
      }
    }
  }

  private fun stopSignalListeners() {
    val ctx = applicationContext ?: return
    val baseTm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    for ((subId, listener) in signalListeners) {
      try {
        val tmForSub = try { baseTm.createForSubscriptionId(subId) } catch (e: Exception) { baseTm }
        tmForSub.listen(listener, PhoneStateListener.LISTEN_NONE)
      } catch (e: Exception) {
        // ignore
      }
    }
    signalListeners.clear()
  }

  // Read dBm and ASU using CellInfo when possible, otherwise fall back to
  // extracting from SignalStrength via reflection. CellInfo-based values are
  // generally more accurate and reflect the currently registered cell.
  private fun readDbmAndAsu(tm: TelephonyManager, ss: SignalStrength?): Pair<Int?, Int?> {
    try {
      // If airplane mode is on, treat as no signal.
      try {
        val ctx = applicationContext
        if (ctx != null) {
          val airplane = try { Settings.Global.getInt(ctx.contentResolver, Settings.Global.AIRPLANE_MODE_ON) } catch (e: Exception) { 0 }
          if (airplane == 1) return Pair(null, null)
        }
      } catch (e: Exception) {
        // ignore
      }
      val cells: List<CellInfo>? = try { tm.allCellInfo } catch (e: Exception) { null }
      if (cells != null && cells.isNotEmpty()) {
        // Prefer the registered cell (the one currently used)
        for (ci in cells) {
          try {
            val strength = when (ci) {
              is CellInfoGsm -> ci.cellSignalStrength
              is CellInfoLte -> ci.cellSignalStrength
              is CellInfoWcdma -> ci.cellSignalStrength
              is CellInfoCdma -> ci.cellSignalStrength
              is CellInfoNr -> ci.cellSignalStrength
              else -> null
            }
            if (strength != null) {
              val dbm = try { strength.dbm } catch (_: Exception) { Int.MIN_VALUE }
              val asu = try { strength.asuLevel } catch (_: Exception) { -1 }
              if (dbm != Int.MIN_VALUE && dbm != Int.MAX_VALUE) {
                return Pair(dbm, if (asu >= 0) asu else null)
              }
            }
          } catch (e: Exception) {
            // ignore per-cell
          }
        }
      }
    } catch (e: Exception) {
      // ignore
    }

    // Fallback to SignalStrength reflection-based extraction (legacy devices)
    return extractDbmAndAsuFallback(ss)
  }

  // Legacy extraction from SignalStrength using reflection and heuristics.
  private fun extractDbmAndAsuFallback(ss: SignalStrength?): Pair<Int?, Int?> {
    if (ss == null) return Pair(null, null)
    try {
      val cls = ss.javaClass

      // Try GSM ASU -> dBm conversion
      try {
        val mGsm: Method = cls.getMethod("getGsmSignalStrength")
        val asu = (mGsm.invoke(ss) as Int)
        if (asu in 0..31) {
          val dbm = -113 + (2 * asu)
          return Pair(dbm, asu)
        }
      } catch (e: Exception) {
        // ignore
      }

      // Try CDMA dBm
      try {
        val mCdma: Method = cls.getMethod("getCdmaDbm")
        val cdmaDbm = (mCdma.invoke(ss) as Int)
        if (cdmaDbm != Int.MIN_VALUE) return Pair(cdmaDbm, null)
      } catch (e: Exception) {
        // ignore
      }

      // Try EVDO dBm
      try {
        val mEvdo: Method = cls.getMethod("getEvdoDbm")
        val evdoDbm = (mEvdo.invoke(ss) as Int)
        if (evdoDbm != Int.MIN_VALUE) return Pair(evdoDbm, null)
      } catch (e: Exception) {
        // ignore
      }

      // Fallback: use level() where available to approximate dBm
      try {
        val mLevel: Method = cls.getMethod("getLevel")
        val level = (mLevel.invoke(ss) as Int)
        val approxDbm = when (level) {
          4 -> -65
          3 -> -80
          2 -> -95
          1 -> -110
          else -> null
        }
        return Pair(approxDbm, null)
      } catch (e: Exception) {
        // ignore
      }

    } catch (e: Exception) {
      // ignore
    }
    return Pair(null, null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    Log.i("SmsGatewayPlugin", "onMethodCall method=${call.method}")
    when (call.method) {
      "sendSms" -> {
        val toArg = call.argument<String>("to")
        val message = call.argument<String>("message")
        val simSlot = call.argument<Int>("simSlot") ?: 0

        if (toArg.isNullOrBlank() || message.isNullOrBlank()) {
          result.error("INVALID_ARGS", "Missing 'to' or 'message'", null)
          return
        }

        val to = toArg.trim()
        val msg = message

        val ctx = applicationContext
        if (ctx == null) {
          result.error("NO_CONTEXT", "Application context not available", null)
          return
        }

        val permissionCheck = ContextCompat.checkSelfPermission(ctx, Manifest.permission.SEND_SMS)
        if (permissionCheck != PackageManager.PERMISSION_GRANTED) {
          result.error("NO_PERMISSION", "SEND_SMS permission not granted", null)
          return
        }

        try {
          // Choose subscription based on simSlot (0 for SIM1, 1 for SIM2)
          // NOTE: slot<->subscription mapping varies by OEM; we use subscription list order.
          val sm = SubscriptionManager.from(ctx)
          val subs = try { sm.activeSubscriptionInfoList } catch (e: Exception) { null }

          val selectedSubId: Int? = if (subs != null && subs.isNotEmpty()) {
            val idx = simSlot.coerceAtLeast(0)
            if (idx < subs.size) subs[idx].subscriptionId else subs[0].subscriptionId
          } else {
            null
          }

          val smsManager = if (selectedSubId != null) {
            val manager = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            // SmsManager per subscription is available on modern APIs
            SmsManager.getSmsManagerForSubscriptionId(selectedSubId)
          } else {
            SmsManager.getDefault()
          }

          val requestId = smsRequestCounter++
          val sentIntent = SentReceiver.createPendingIntent(ctx, requestId, to)

          val parts = smsManager.divideMessage(msg)

          if (parts.size == 1) {
            smsManager.sendTextMessage(
              to,
              null,
              parts[0],
              sentIntent,
              null
            )
          } else {
            val sentIntents = java.util.ArrayList<PendingIntent>()
            repeat(parts.size) { sentIntents.add(sentIntent) }
            smsManager.sendMultipartTextMessage(
              to,
              null,
              parts,
              sentIntents,
              null
            )
          }

          result.success(true)
        } catch (e: Exception) {
          result.error("SMS_FAILED", e.message ?: "SmsManager failure", null)
        }
      }

      "getDeviceStatus" -> {
        // Backward-compatible alias to avoid MissingPluginException when
        // older Flutter code calls the previous method name.
        return onMethodCall(MethodCall("getDeviceSimStatus", call.arguments), result)
      }

      "getDeviceSimStatus" -> {
        val ctx = applicationContext
        if (ctx == null) {
          result.error("NO_CONTEXT", "Application context not available", null)
          return
        }

        // Some telephony info requires runtime permission; we already request READ_PHONE_STATE.
        val hasPhoneState = ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED

        val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val sm = SubscriptionManager.from(ctx)

        val subs = try {
          sm.activeSubscriptionInfoList
        } catch (e: Exception) {
          null
        }

        val list = mutableListOf<Map<String, Any?>>()

        // If we can't get subscription info, return at least one entry.
        if (subs == null || subs.isEmpty()) {
          val carrier = tm.networkOperatorName ?: ""

          // Signal strength is best-effort: extract numeric dBm/ASU when possible.
          val (signalDbm: Int?, signalAsu: Int?) = try {
            val strength: SignalStrength? = tm.signalStrength
            readDbmAndAsu(tm, strength)
          } catch (e: Exception) {
            Pair(null, null)
          }

          list.add(
            mapOf(
              "slotIndex" to 0,
              "subscriptionId" to null,
              "carrier" to carrier,
              "phoneNumber" to if (hasPhoneState) (tm.line1Number ?: "") else "",
              "signalDbm" to signalDbm,
              "signalAsu" to signalAsu
            )
          )
          result.success(list)
          return
        }

        for (i in subs.indices) {
          val info = subs[i]
          val subscriptionId = info.subscriptionId

          // Carrier/operator
          val carrierName = (info.carrierName ?: tm.networkOperatorName ?: "").toString()

          // Slot index is not always the same as subscription order, but we can expose it as i.
          // If you need exact SIM slot mapping, device OEM support varies.
          val slotIndex = i

          // Phone number: may be null even with permissions.
          val phoneNumber = if (hasPhoneState) {
            // line1Number may return empty on many devices
            val number = try {
              tm.createForSubscriptionId(subscriptionId).line1Number
            } catch (e: Exception) {
              null
            }
            number?.toString() ?: ""
          } else {
            ""
          }

            // Signal strength best-effort: attempt to extract numeric dBm and ASU values.
            val (signalDbm: Int?, signalAsu: Int?) = try {
              val tmForSub = try { tm.createForSubscriptionId(subscriptionId) } catch (e: Exception) { tm }
              val strength: SignalStrength? = tmForSub.signalStrength
              readDbmAndAsu(tmForSub, strength)
            } catch (e: Exception) {
              Pair(null, null)
            }

          list.add(
            mapOf(
              "slotIndex" to slotIndex,
              "subscriptionId" to subscriptionId,
              "carrier" to carrierName,
              "phoneNumber" to phoneNumber,
              "signalDbm" to signalDbm,
              "signalAsu" to signalAsu
            )
          )
        }

        result.success(list)
      }

      "isDefaultSmsApp" -> {
        // Backward-compatible alias for isDefaultSmsRoleHeld
        val ctx = applicationContext
        if (ctx == null) {
          result.error("NO_CONTEXT", "Application context not available", null)
          return
        }
        try {
          val held = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = ctx.getSystemService(RoleManager::class.java)
            rm?.isRoleHeld(RoleManager.ROLE_SMS) == true
          } else {
            // On older Android versions, check the default SMS package name
            try {
              val defaultPkg = Telephony.Sms.getDefaultSmsPackage(ctx)
              (defaultPkg != null && defaultPkg == ctx.packageName)
            } catch (e: Exception) {
              false
            }
          }
          Log.i("SmsGatewayPlugin", "isDefaultSmsApp / roleHeld=$held")
          result.success(held)
        } catch (e: Exception) {
          result.error("CHECK_FAILED", e.message ?: "Failed to check default SMS app", null)
        }
        return
      }


      "listSmsApps" -> {
        val ctx = applicationContext
        if (ctx == null) {
          result.error("NO_CONTEXT", "Application context not available", null)
          return
        }
        try {
          val pm = ctx.packageManager
          val schemes = arrayOf("smsto:", "sms:")
          val seen = linkedSetOf<String>()
          val list = ArrayList<Map<String, Any?>>()

          for (scheme in schemes) {
            try {
              val intent = android.content.Intent(android.content.Intent.ACTION_SENDTO, Uri.parse(scheme))
              val resolves = pm.queryIntentActivities(intent, 0)
              Log.i("SmsGatewayPlugin", "listSmsApps: scheme=$scheme found=${resolves.size}")
              for (ri in resolves) {
                val pkg = ri.activityInfo.packageName
                if (seen.add(pkg)) {
                  val label = ri.loadLabel(pm)?.toString() ?: pkg
                  Log.i("SmsGatewayPlugin", "listSmsApps: pkg=$pkg label=$label")
                  list.add(mapOf("package" to pkg, "label" to label))
                }
              }
            } catch (e: Exception) {
              Log.w("SmsGatewayPlugin", "listSmsApps: scheme=$scheme failed: ${e.message}")
            }
          }

          // If nothing found, log SMS role status as a hint
          if (list.isEmpty()) {
            try {
              val roleHeld = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val rm = ctx.getSystemService(RoleManager::class.java)
                rm?.isRoleHeld(RoleManager.ROLE_SMS) == true
              } else {
                false
              }
              Log.i("SmsGatewayPlugin", "listSmsApps: roleHeld=$roleHeld")
            } catch (e: Exception) {
              Log.w("SmsGatewayPlugin", "listSmsApps: could not read role status: ${e.message}")
            }

            // (RoleManager lookup removed for compatibility with older Kotlin/SDK tooling.)

            // Fallback: scan installed packages that request SMS permissions in manifest
            try {
              val pkgs = pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)
              for (pi in pkgs) {
                val perms = pi.requestedPermissions
                if (perms != null) {
                  val hasSmsPerm = perms.any { p ->
                    p == Manifest.permission.SEND_SMS || p == Manifest.permission.RECEIVE_SMS || p == Manifest.permission.READ_SMS
                  }
                  if (hasSmsPerm) {
                    val pkg = pi.packageName
                    if (seen.add(pkg)) {
                      try {
                        val appInfo = pm.getApplicationInfo(pkg, 0)
                        val label = pm.getApplicationLabel(appInfo)?.toString() ?: pkg
                        Log.i("SmsGatewayPlugin", "listSmsApps: hasSmsPerm pkg=$pkg label=$label")
                        list.add(mapOf("package" to pkg, "label" to label))
                      } catch (e: Exception) {
                        // ignore
                      }
                    }
                  }
                }
              }
            } catch (e: Exception) {
              Log.w("SmsGatewayPlugin", "listSmsApps: installed package scan failed: ${e.message}")
            }
          }

          result.success(list)
        } catch (e: Exception) {
          result.error("LIST_FAILED", e.message ?: "Failed to list SMS apps", null)
        }
        return
      }

      "isDefaultSmsRoleHeld" -> {
        val ctx = applicationContext
        if (ctx == null) {
          result.error("NO_CONTEXT", "Application context not available", null)
          return
        }
        try {
          val held = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = ctx.getSystemService(RoleManager::class.java)
            rm?.isRoleHeld(RoleManager.ROLE_SMS) == true
          } else {
            try {
              val defaultPkg = Telephony.Sms.getDefaultSmsPackage(ctx)
              (defaultPkg != null && defaultPkg == ctx.packageName)
            } catch (e: Exception) {
              false
            }
          }
          Log.i("SmsGatewayPlugin", "isDefaultSmsRoleHeld=$held")
          result.success(held)
        } catch (e: Exception) {
          result.error("CHECK_FAILED", e.message ?: "Failed to check SMS role", null)
        }
        return
      }

        "nativeGetPendingReplies" -> {
          try {
            val ctx = applicationContext ?: run {
              result.error("NO_CONTEXT", "Application context not available", null)
              return
            }
            val db = RepliesDbHelper(ctx)
            val rows = db.getAllReplies()
            // Convert to List<Map<String, Object>> for MethodChannel
            val out = ArrayList<Map<String, Any?>>()
            for (r in rows) {
              out.add(mapOf(
                "id" to (r["id"] as Number).toLong(),
                "phone_number" to r["phone_number"],
                "message" to r["message"],
                "received_at" to r["received_at"]
              ))
            }
            result.success(out)
          } catch (e: Exception) {
            result.error("PENDING_FAILED", e.message ?: "Failed to read pending replies", null)
          }
          return
        }

        "nativeDeleteReply" -> {
          try {
            val ctx = applicationContext ?: run {
              result.error("NO_CONTEXT", "Application context not available", null)
              return
            }
            val id = call.argument<Number>("id")?.toLong()
            if (id == null) {
              result.error("INVALID_ARGS", "Missing id", null)
              return
            }
            val db = RepliesDbHelper(ctx)
            val deleted = db.deleteReply(id)
            result.success(deleted > 0)
          } catch (e: Exception) {
            result.error("DELETE_FAILED", e.message ?: "Failed to delete reply", null)
          }
          return
        }

        "nativeImportSmsHistory" -> {
          Log.i("SmsGatewayPlugin", "nativeImportSmsHistory called")
          try {
            val ctx = applicationContext ?: run {
              Log.e("SmsGatewayPlugin", "nativeImportSmsHistory: NO_CONTEXT")
              result.error("NO_CONTEXT", "Application context not available", null)
              return
            }

            val types = call.argument<List<String>>("types") ?: listOf("inbox", "sent")
            val sinceStr = call.argument<String>("since")
            val sinceMillis = sinceStr?.toLongOrNull()

            val out = ArrayList<Map<String, Any?>>()

            val resolver = ctx.contentResolver

            fun queryUri(uri: android.net.Uri, typeLabel: String) {
              val projection = arrayOf("_id", "address", "body", "date", "read")
              var sel: String? = null
              var selArgs: Array<String>? = null
              if (sinceMillis != null) {
                sel = "date >= ?"
                selArgs = arrayOf(sinceMillis.toString())
              }
              val cursor: Cursor? = try { resolver.query(uri, projection, sel, selArgs, "date ASC") } catch (e: Exception) { null }
              cursor?.use {
                while (it.moveToNext()) {
                  val id = it.getLong(it.getColumnIndexOrThrow("_id"))
                  val addr = it.getString(it.getColumnIndexOrThrow("address")) ?: ""
                  val body = it.getString(it.getColumnIndexOrThrow("body")) ?: ""
                  val date = it.getLong(it.getColumnIndexOrThrow("date"))
                  val read = it.getInt(it.getColumnIndexOrThrow("read"))
                  out.add(mapOf(
                    "nativeId" to id,
                    "address" to addr,
                    "body" to body,
                    "date" to date,
                    "type" to typeLabel,
                    "read" to read
                  ))
                }
              }
            }

            for (t in types) {
              when (t) {
                "inbox" -> queryUri(Telephony.Sms.Inbox.CONTENT_URI, "inbox")
                "sent" -> queryUri(Telephony.Sms.Sent.CONTENT_URI, "sent")
                else -> queryUri(android.net.Uri.parse("content://sms"), t)
              }
            }

            Log.i("SmsGatewayPlugin", "nativeImportSmsHistory: returning ${out.size} rows for types=$types")
            result.success(out)
          } catch (e: Exception) {
            result.error("IMPORT_FAILED", e.message ?: "Failed to import SMS history", null)
          }
          return
        }

      "requestDefaultSmsRole" -> {
        val ctx = applicationContext
        val binding = activityBinding
        if (ctx == null) {
          result.error("NO_CONTEXT", "Application context not available", null)
          return
        }
        if (binding == null) {
          result.error("NO_ACTIVITY", "Activity not available to start intent", null)
          return
        }
        try {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = ctx.getSystemService(RoleManager::class.java)
            val intent = rm.createRequestRoleIntent(RoleManager.ROLE_SMS)
            pendingRoleResult = result
            binding.activity.startActivityForResult(intent, ROLE_SMS_REQUEST)
            Log.i("SmsGatewayPlugin", "requestDefaultSmsRole: started role request with startActivityForResult")
          } else {
            val intent = Intent(android.provider.Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
            intent.putExtra(android.provider.Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, ctx.packageName)
            binding.activity.startActivity(intent)
            result.success(true)
          }
        } catch (e: Exception) {
          Log.w("SmsGatewayPlugin", "requestDefaultSmsRole failed: ${e.message}")
          result.error("REQUEST_FAILED", e.message ?: "Failed to request SMS role", null)
        }
        return
      }

      "requestDefaultSmsApp" -> {
        val ctx = applicationContext
        val binding = activityBinding
        if (ctx == null) {
          result.error("NO_CONTEXT", "Application context not available", null)
          return
        }
        if (binding == null) {
          result.error("NO_ACTIVITY", "Activity not available to start intent", null)
          return
        }
        try {
          val targetPkg = call.argument<String>("package") ?: ctx.packageName

          if (targetPkg == ctx.packageName && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Use startActivityForResult so we get a callback when the user decides
            val roleManager = ctx.getSystemService(RoleManager::class.java)
            val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_SMS)
            pendingRoleResult = result
            binding.activity.startActivityForResult(intent, ROLE_SMS_REQUEST)
            Log.i("SmsGatewayPlugin", "requestDefaultSmsApp: started role request with startActivityForResult")
            return
          }

          // Fallback: open system settings (pre-Q or different package)
          val intent = Intent(android.provider.Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
          intent.putExtra(android.provider.Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, targetPkg)
          binding.activity.startActivity(intent)
          result.success(true)
        } catch (e: Exception) {
          result.error("REQUEST_FAILED", e.message ?: "Failed to request default SMS app", null)
        }
        return
      }

      else -> result.notImplemented()
    }
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activityBinding = binding
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activityBinding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activityBinding = binding
  }

  override fun onDetachedFromActivity() {
    activityBinding = null
  }
}

