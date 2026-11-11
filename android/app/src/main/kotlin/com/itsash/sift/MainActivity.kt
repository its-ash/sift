package com.itsash.sift

import android.Manifest
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * MethodChannel "com.itsash.sift/sms" (Dart side: lib/sms/sms_platform.dart):
 *   - defaultSmsApp() -> {package, label, isSelf}: the current default SMS app.
 *   - roleState() -> {sdk, roleAvailable, roleHeld, package, label, smsPermission}.
 *   - requestDefaultSmsApp() -> {granted, resultCode, elapsedMs, error?}. Uses
 *     RoleManager.createRequestRoleIntent(ROLE_SMS) on Android 10+ and the old
 *     ACTION_CHANGE_DEFAULT below. elapsedMs lets Dart spot an instant refusal
 *     (Restricted settings on Android 13+).
 *   - restoreDefaultSmsApp({package}) -> "requested" | "settings".
 *   - openAppDetails(): Sift's page in Android Settings.
 *   - loadInbox() -> List<{id, threadId, address, body, date, read}>, newest first.
 *   - deleteByIds({ids}) / deleteById({id}) -> rows deleted (content://sms).
 *   - deleteThreads({threadIds}) -> rows deleted (content://mms-sms/conversations/<id>).
 *     Deletes fail with "not_default" when Sift is not the default SMS app and
 *     "security" on SecurityException. All provider work runs on a background thread.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.itsash.sift/sms"
    private val roleRequestCode = 4101
    private var pendingRole: MethodChannel.Result? = null
    private var roleRequestStart = 0L
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "defaultSmsApp" -> result.success(defaultSmsApp())
                "roleState" -> result.success(roleState())
                "requestDefaultSmsApp" -> requestDefaultSmsApp(result)
                "restoreDefaultSmsApp" -> result.success(restoreDefaultSmsApp(call.argument<String>("package")))
                "openAppDetails" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "loadInbox" -> background(result) { loadInbox() }
                "deleteByIds" -> deleteCall(result) {
                    val ids = (call.argument<List<Any>>("ids") ?: emptyList()).map { (it as Number).toLong() }
                    deleteByIds(ids)
                }
                "deleteById" -> deleteCall(result) {
                    deleteById((call.argument<Number>("id") ?: 0).toLong())
                }
                "deleteThreads" -> deleteCall(result) {
                    val ids = (call.argument<List<Any>>("threadIds") ?: emptyList()).map { (it as Number).toLong() }
                    deleteThreads(ids)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    /** Runs [work] off the main thread. SecurityException becomes error "security". */
    private fun <T> background(result: MethodChannel.Result, work: () -> T) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("security", e.message ?: "Permission denied", null) }
            } catch (e: Throwable) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    /** Android silently deletes nothing for a non-default app, so refuse up front. */
    private fun <T> deleteCall(result: MethodChannel.Result, work: () -> T) {
        if (!isDefaultSmsApp()) {
            result.error("not_default", "Sift is not the default SMS app", null)
        } else {
            background(result, work)
        }
    }

    /** True when Sift holds the SMS role (RoleManager on 10+, default package below). */
    private fun isDefaultSmsApp(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = getSystemService(RoleManager::class.java)
            if (roles != null && roles.isRoleHeld(RoleManager.ROLE_SMS)) return true
        }
        return Telephony.Sms.getDefaultSmsPackage(this) == packageName
    }

    private fun labelOf(pkg: String?): String? = pkg?.let {
        try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(it, 0)).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun defaultSmsApp(): Map<String, Any?> {
        val pkg = Telephony.Sms.getDefaultSmsPackage(this)
        return mapOf("package" to pkg, "label" to labelOf(pkg), "isSelf" to isDefaultSmsApp())
    }

    private fun roleState(): Map<String, Any?> {
        val pkg = Telephony.Sms.getDefaultSmsPackage(this)
        val available = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            getSystemService(RoleManager::class.java)?.isRoleAvailable(RoleManager.ROLE_SMS) ?: false
        } else {
            true
        }
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "roleAvailable" to available,
            "roleHeld" to isDefaultSmsApp(),
            "package" to pkg,
            "label" to labelOf(pkg),
            "smsPermission" to (checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED),
        )
    }

    private fun requestOutcome(granted: Boolean, resultCode: Int, error: String? = null): Map<String, Any?> = mapOf(
        "granted" to granted,
        "resultCode" to resultCode,
        "elapsedMs" to (SystemClock.elapsedRealtime() - roleRequestStart),
        "error" to error,
    )

    private fun requestDefaultSmsApp(result: MethodChannel.Result) {
        roleRequestStart = SystemClock.elapsedRealtime()
        if (isDefaultSmsApp()) {
            result.success(requestOutcome(true, RESULT_OK))
            return
        }
        pendingRole?.success(requestOutcome(false, RESULT_CANCELED))
        pendingRole = result
        val intent: Intent
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = getSystemService(RoleManager::class.java)
            if (roles == null || !roles.isRoleAvailable(RoleManager.ROLE_SMS)) {
                pendingRole = null
                result.success(requestOutcome(false, RESULT_CANCELED, "role_unavailable"))
                return
            }
            intent = roles.createRequestRoleIntent(RoleManager.ROLE_SMS)
        } else {
            intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
                .putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, roleRequestCode)
        } catch (e: ActivityNotFoundException) {
            pendingRole = null
            result.success(requestOutcome(false, RESULT_CANCELED, "no_activity"))
        } catch (e: SecurityException) {
            pendingRole = null
            result.success(requestOutcome(false, RESULT_CANCELED, e.message ?: "security"))
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == roleRequestCode) {
            // Do not trust resultCode alone: ask the role itself.
            pendingRole?.success(requestOutcome(isDefaultSmsApp(), resultCode))
            pendingRole = null
        }
    }

    private fun restoreDefaultSmsApp(pkg: String?): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && !pkg.isNullOrEmpty() && pkg != packageName) {
            startActivity(
                Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
                    .putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, pkg),
            )
            return "requested"
        }
        try {
            startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
        return "settings"
    }

    private fun loadInbox(): List<Map<String, Any?>> {
        if (checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("READ_SMS not granted")
        }
        val out = ArrayList<Map<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.THREAD_ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.READ,
            ),
            null,
            null,
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            val id = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val thread = c.getColumnIndexOrThrow(Telephony.Sms.THREAD_ID)
            val address = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val body = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val date = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            val read = c.getColumnIndexOrThrow(Telephony.Sms.READ)
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(id),
                        "threadId" to c.getLong(thread),
                        "address" to (c.getString(address) ?: ""),
                        "body" to (c.getString(body) ?: ""),
                        "date" to c.getLong(date),
                        "read" to (c.getInt(read) != 0),
                    ),
                )
            }
        }
        return out
    }

    /** One ContentResolver.delete on content://sms for a chunk of ids. Returns rows removed. */
    private fun deleteByIds(ids: List<Long>): Int {
        if (ids.isEmpty()) return 0
        return contentResolver.delete(
            Telephony.Sms.CONTENT_URI,
            "${Telephony.Sms._ID} IN (${ids.joinToString(",")})",
            null,
        )
    }

    /** content://sms/<id>. */
    private fun deleteById(id: Long): Int =
        contentResolver.delete(Uri.withAppendedPath(Telephony.Sms.CONTENT_URI, id.toString()), null, null)

    /** content://mms-sms/conversations/<threadId>: removes a whole conversation. */
    private fun deleteThreads(threadIds: List<Long>): Int {
        var deleted = 0
        for (t in threadIds.distinct()) {
            deleted += contentResolver.delete(Uri.parse("content://mms-sms/conversations/$t"), null, null)
        }
        return deleted
    }
}
