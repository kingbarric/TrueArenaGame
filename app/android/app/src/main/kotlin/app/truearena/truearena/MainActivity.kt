package app.truearena.truearena

import android.os.RemoteException
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "playhuud/install_referrer")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") { result.notImplemented(); return@setMethodCallHandler }
                val client = InstallReferrerClient.newBuilder(this).build()
                val answered = java.util.concurrent.atomic.AtomicBoolean(false)
                fun finish(value: String?) {
                    if (!answered.compareAndSet(false, true)) return
                    try { client.endConnection() } catch (_: RuntimeException) {}
                    result.success(value)
                }
                client.startConnection(object : InstallReferrerStateListener {
                    override fun onInstallReferrerSetupFinished(code: Int) {
                        if (code != InstallReferrerClient.InstallReferrerResponse.OK) { finish(null); return }
                        try { finish(client.installReferrer.installReferrer) }
                        catch (_: RemoteException) { finish(null) }
                        catch (_: RuntimeException) { finish(null) }
                    }
                    override fun onInstallReferrerServiceDisconnected() { finish(null) }
                })
                // A disconnected/slow store must never hold up opening the app.
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ finish(null) }, 2500)
            }
    }
}
