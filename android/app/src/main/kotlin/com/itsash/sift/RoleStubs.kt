package com.itsash.sift

import android.app.Activity
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import android.widget.Toast

/*
 * Android lists an app as a possible default SMS app only when it declares all
 * of these components. Sift is a cleaner, not a messenger, so the ones it
 * does not need are minimal. See AndroidManifest.xml.
 */

/** MMS push while Sift is the default. Sift does not download MMS. */
class MmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = Unit
}

/** Quick replies to calls. Sift does not send messages. */
class HeadlessSmsSendService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopSelf(startId)
        return START_NOT_STICKY
    }
}

/** "Send a message" links: explains and opens the default apps screen. */
class ComposeSmsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Toast.makeText(
            this,
            "Sift can't send messages. Set your messaging app as the default SMS app again.",
            Toast.LENGTH_LONG,
        ).show()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        }
        finish()
    }
}
