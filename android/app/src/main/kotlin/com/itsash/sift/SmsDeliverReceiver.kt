package com.itsash.sift

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Only the default SMS app gets SMS_DELIVER, and it must write the message to
 * the system inbox itself. While Sift holds the role (usually a few seconds
 * during a delete), this keeps new texts from being lost: the user's messaging
 * app shows them once it is the default again.
 */
class SmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isNullOrEmpty()) return
        val first = parts[0]
        val values = ContentValues().apply {
            put(Telephony.Sms.ADDRESS, first.displayOriginatingAddress)
            put(Telephony.Sms.BODY, parts.joinToString("") { it.displayMessageBody ?: "" })
            put(Telephony.Sms.DATE, System.currentTimeMillis())
            put(Telephony.Sms.DATE_SENT, first.timestampMillis)
            put(Telephony.Sms.READ, 0)
            put(Telephony.Sms.SEEN, 0)
            val sub = intent.getIntExtra("subscription", -1)
            if (sub >= 0) put(Telephony.Sms.SUBSCRIPTION_ID, sub)
        }
        val pending = goAsync()
        Thread {
            try {
                context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
            } catch (_: Throwable) {
            } finally {
                pending.finish()
            }
        }.start()
    }
}
