package com.aurafinance.aura_finance

import android.content.Intent
import android.os.Build
import android.os.Handler
import android.provider.Settings
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.pusher.pushnotifications.BeamsCallback
import com.pusher.pushnotifications.PushNotifications
import com.pusher.pushnotifications.PusherCallbackError
import com.pusher.pushnotifications.auth.AuthData
import com.pusher.pushnotifications.auth.AuthDataGetter
import com.pusher.pushnotifications.auth.BeamsTokenProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity diperlukan oleh local_auth (kunci sidik jari).
// Juga menjadi jembatan ke Pusher Beams Android SDK (plugin Flutter resminya sudah tidak dirawat).
class MainActivity : FlutterFragmentActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aura/beams").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // Beams memakai FCM; tanpa google-services.json Firebase tidak aktif -> push dimatikan dengan aman.
                    "start" -> {
                        if (FirebaseApp.getApps(this).isEmpty() && FirebaseApp.initializeApp(this) == null) {
                            result.success(false)
                        } else {
                            PushNotifications.start(applicationContext, call.argument<String>("instanceId")!!)
                            result.success(true)
                        }
                    }
                    "setUser" -> {
                        val jwt = call.argument<String>("jwt")!!
                        val provider = BeamsTokenProvider(
                            call.argument<String>("tokenUrl")!!,
                            object : AuthDataGetter {
                                override fun getAuthData() = AuthData(
                                    headers = hashMapOf("Authorization" to "Bearer $jwt"),
                                    queryParams = hashMapOf(),
                                )
                            },
                        )
                        PushNotifications.setUserId(
                            call.argument<String>("userId")!!,
                            provider,
                            object : BeamsCallback<Void, PusherCallbackError> {
                                override fun onSuccess(vararg values: Void) {
                                    main.post { result.success(true) }
                                }

                                override fun onFailure(error: PusherCallbackError) {
                                    main.post { result.error("beams", error.message, null) }
                                }
                            },
                        )
                    }
                    // Pengaturan notifikasi aplikasi ini (dipakai bila izin pernah ditolak).
                    "openNotificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(android.net.Uri.parse("package:$packageName"))
                        }
                        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "clear" -> {
                        PushNotifications.clearAllState()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("beams", e.message, null)
            }
        }
    }
}
