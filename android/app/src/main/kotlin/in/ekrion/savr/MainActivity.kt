package `in`.ekrion.savr

import android.content.Intent
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingShare = extractShare(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "in.savr/native").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialSharedText" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "installedPackages" -> {
                        val asked = (call.arguments as? List<*>)?.filterIsInstance<String>()?.take(64) ?: emptyList()
                        result.success(asked.filter { isPackageName(it) && launchIntent(it) != null })
                    }
                    "openInPackage" -> {
                        // Opens an https link inside one specific installed app (its own
                        // product page), even when the app hasn't verified the domain for
                        // automatic App Links. Dart only passes allowlisted hosts/packages.
                        val args = call.arguments as? Map<*, *>
                        val url = args?.get("url") as? String
                        val pkg = args?.get("package") as? String
                        val uri = url?.let { runCatching { Uri.parse(it) }.getOrNull() }
                        if (uri == null || uri.scheme != "https" || pkg == null || !isPackageName(pkg)) {
                            result.success(false)
                        } else {
                            val view = Intent(Intent.ACTION_VIEW, uri).setPackage(pkg)
                                .addCategory(Intent.CATEGORY_BROWSABLE)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            val ok = view.resolveActivity(packageManager) != null && runCatching {
                                startActivity(view)
                            }.isSuccess
                            result.success(ok)
                        }
                    }
                    "launchPackage" -> {
                        val pkg = call.arguments as? String
                        val launch = if (pkg != null && isPackageName(pkg)) launchIntent(pkg) else null
                        if (launch == null) {
                            result.success(false)
                        } else {
                            try {
                                startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        extractShare(intent)?.let { channel?.invokeMethod("sharedText", it) }
    }

    private fun isPackageName(s: String) = s.length <= 128 && Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$").matches(s)

    /** Only the app's launcher entry point; null when not installed / not visible. */
    private fun launchIntent(pkg: String): Intent? = packageManager.getLaunchIntentForPackage(pkg)

    /** Only plain-text ACTION_SEND is accepted, capped in length; Dart re-validates. */
    private fun extractShare(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        return text.take(2048)
    }
}
