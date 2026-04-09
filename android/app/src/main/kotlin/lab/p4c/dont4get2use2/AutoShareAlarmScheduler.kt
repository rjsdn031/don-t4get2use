package lab.p4c.dont4get2use2

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log

object AutoShareAlarmScheduler {
    private const val TAG = "AutoShareAlarmScheduler"

    fun schedule(
        context: Context,
        gifticonId: String,
        triggerAtMillis: Long
    ) {
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, AutoShareAlarmReceiver::class.java).apply {
            putExtra("gifticonId", gifticonId)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            gifticonId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        Log.d(
            TAG,
            "schedule gifticonId=$gifticonId triggerAtMillis=$triggerAtMillis"
        )

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAtMillis,
            pendingIntent
        )
    }

    fun cancel(
        context: Context,
        gifticonId: String
    ) {
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, AutoShareAlarmReceiver::class.java)

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            gifticonId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        Log.d(TAG, "cancel gifticonId=$gifticonId")
        alarmManager.cancel(pendingIntent)
    }
}