package lab.p4c.dont4get2use2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AutoShareAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AutoShareAlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val gifticonId = intent.getStringExtra("gifticonId")

        if (gifticonId.isNullOrBlank()) {
            Log.e(TAG, "gifticonId missing")
            return
        }

        Log.d(TAG, "alarm received gifticonId=$gifticonId")
        AutoShareFlutterRunner.run(context, gifticonId)
    }
}