package com.example.smsgo

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

  companion object {
    @JvmStatic
    var smsChannel: MethodChannel? = null
  }

  private val channelName = "sms_gateway"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    // Register the in-app SmsGatewayPlugin so its MethodChannel handlers
    // (including `getDeviceSimStatus`, `sendSms`, etc.) are available.
    // SmsGatewayPlugin will set `MainActivity.smsChannel` itself when attached.
    try {
      flutterEngine.plugins.add(SmsGatewayPlugin())
    } catch (e: Exception) {
      // Best-effort: log but don't crash if plugin registration fails here.
      // The plugin may still be registered by GeneratedPluginRegistrant in some setups.
    }
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    // Forward role-request result to the plugin so it can resolve the pending Flutter Result
    SmsGatewayPlugin.handleActivityResult(requestCode, resultCode)
  }
}
