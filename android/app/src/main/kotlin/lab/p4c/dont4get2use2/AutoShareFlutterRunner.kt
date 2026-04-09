package lab.p4c.dont4get2use2

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

object AutoShareFlutterRunner {
    private const val TAG = "AutoShareFlutterRunner"
    private const val ENTRYPOINT = "autoShareBackgroundEntry"

    fun run(
        context: Context,
        gifticonId: String
    ) {
        try {
            val appContext = context.applicationContext
            val flutterLoader = FlutterInjector.instance().flutterLoader()

            flutterLoader.startInitialization(appContext)
            flutterLoader.ensureInitializationComplete(appContext, null)

            val engine = FlutterEngine(appContext)
            val bundlePath = flutterLoader.findAppBundlePath()

            Log.d(TAG, "run entrypoint=$ENTRYPOINT gifticonId=$gifticonId")

            val dartEntrypoint = DartExecutor.DartEntrypoint(
                bundlePath,
                ENTRYPOINT
            )

            engine.dartExecutor.executeDartEntrypoint(
                dartEntrypoint,
                listOf(gifticonId)
            )
        } catch (t: Throwable) {
            Log.e(TAG, "failed to start flutter background entry", t)
        }
    }
}