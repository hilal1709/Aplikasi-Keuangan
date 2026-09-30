package com.aurafinance.aura_finance

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity diperlukan oleh local_auth (kunci sidik jari).
// Juga menjadi jembatan kecil ke Firebase Cloud Messaging untuk push notification.
class MainActivity : FlutterFragmentActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aura/push").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // Token FCM HP ini; dikirim ke worker supaya pasangan bisa mengirim push.
                    // Tanpa google-services.json Firebase tidak aktif -> push dimatikan dengan aman.
                    "fcmToken" -> {
                        if (FirebaseApp.getApps(this).isEmpty() && FirebaseApp.initializeApp(this) == null) {
                            result.error("fcm", "Firebase tidak terpasang", null)
                        } else {
                            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                                main.post {
                                    if (task.isSuccessful) result.success(task.result)
                                    else result.error("fcm", task.exception?.message ?: "gagal mengambil token FCM", null)
                                }
                            }
                        }
                    }
                    // Pengaturan notifikasi aplikasi ini (dipakai bila izin pernah ditolak).
                    "openNotificationSettings" -> {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(Uri.parse("package:$packageName"))
                        }
                        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("push", e.message, null)
            }
        }
    }
}
