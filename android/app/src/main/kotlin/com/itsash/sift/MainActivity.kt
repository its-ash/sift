package com.itsash.sift

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * MethodChannel "com.itsash.sift/sms" (Dart side: lib/sms/sms_platform.dart):
 *   - defaultSmsApp() -> {package, label, isSelf}: the current default SMS app.
 *   - requestDefaultSmsApp() -> bool: asks Android to make Sift the default
 *     SMS app (needed to delete). True when Sift is the default afterwards.
 *   - restoreDefaultSmsApp({package}) -> "requested" | "settings": hands the role
 *     back. Below Android 10 it asks for [package] directly; from 10 on apps can
 *     only request the role for themselves, so it opens the default apps screen.
 *   - loadInbox() -> List<{id, threadId, address, body, date, read}>, newest first.
 *   - deleteMessages({ids}) -> int deleted. Error "not_default" when Sift is
 *     not the default SMS app (Android would silently delete nothing).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.itsash.sift/sms"
    private val roleRequestCode = 4101
    private var pendingRole: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "defaultSmsApp" -> result.success(defaultSmsApp())
                "requestDefaultSmsApp" -> requestDefaultSmsApp(result)
                "restoreDefaultSmsApp" -> result.success(restoreDefaultSmsApp(call.argument<String>("package")))
                "loadInbox" -> background(result) { loadInbox() }
                "deleteMessages" -> {
                    if (!isDefaultSmsApp()) {
                        result.error("not_default", "Sift is not the default SMS app", null)
                    } else {
                        val ids = (call.argument<List<Any>>("ids") ?: emptyList()).map { (it as Number).toLong() }
                        background(result) { deleteMessages(ids) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    private fun <T> background(result: MethodChannel.Result, work: () -> T) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("no_permission", e.message, null) }
            } catch (e: Throwable) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    private fun isDefaultSmsApp(): Boolean = Telephony.Sms.getDefaultSmsPackage(this) == packageName

    private fun defaultSmsApp(): Map<String, Any?> {
        val pkg = Telephony.Sms.getDefaultSmsPackage(this)
        val label = pkg?.let {
            try {
                packageManager.getApplicationLabel(packageManager.getApplicationInfo(it, 0)).toString()
            } catch (_: PackageManager.NameNotFoundException) {
                null
            }
        }
        return mapOf("package" to pkg, "label" to label, "isSelf" to (pkg == packageName))
    }

    private fun requestDefaultSmsApp(result: MethodChannel.Result) {
        if (isDefaultSmsApp()) {
            result.success(true)
            return
        }
        pendingRole?.success(false)
        pendingRole = result
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = getSystemService(RoleManager::class.java)
            if (roles == null || !roles.isRoleAvailable(RoleManager.ROLE_SMS)) {
                pendingRole = null
                result.success(false)
                return
            }
            roles.createRequestRoleIntent(RoleManager.ROLE_SMS)
        } else {
            Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
                .putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, roleRequestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == roleRequestCode) {
            pendingRole?.success(isDefaultSmsApp())
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
        startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
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

    /** Deletes by id in chunks, so huge selections stay under SQLite's argument limits. */
    private fun deleteMessages(ids: List<Long>): Int {
        var deleted = 0
        for (chunk in ids.distinct().chunked(400)) {
            deleted += contentResolver.delete(
                Telephony.Sms.CONTENT_URI,
                "${Telephony.Sms._ID} IN (${chunk.joinToString(",")})",
                null,
            )
        }
        return deleted
    }
}
