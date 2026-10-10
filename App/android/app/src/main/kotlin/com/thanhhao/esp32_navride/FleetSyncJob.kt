package com.thanhhao.esp32_navride

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Android lên lịch khi có mạng; không bật GPS hoặc âm thầm bắt đầu chuyến mới. */
class FleetSyncJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        FleetHistorySync.get(this).sync { retry -> jobFinished(params, retry) }
        return true
    }
    override fun onStopJob(params: JobParameters): Boolean = true
}

internal class FleetHistorySync private constructor(context: Context) {
    private val app = context.applicationContext
    private val queue = FleetOutbox(app)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val auth = FirebaseAuth.getInstance()
    private val scheduler = app.getSystemService(JobScheduler::class.java)
    private var lastAttempt = -30_000L
    @Volatile private var error: String? = null

    companion object {
        private const val JOB = 7302
        @Volatile private var instance: FleetHistorySync? = null
        fun get(context: Context): FleetHistorySync = instance ?: synchronized(this) {
            instance ?: FleetHistorySync(context).also { instance = it }
        }
    }

    init {
        auth.addAuthStateListener { requestSync() }
        runCatching {
            app.getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) = requestSync()
                    override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                        if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) requestSync()
                    }
                },
            )
        }
    }

    fun online(): Boolean {
        val manager = app.getSystemService(ConnectivityManager::class.java)
        return manager.activeNetwork?.let { manager.getNetworkCapabilities(it) }
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
    }

    fun status(): Map<String, Any?> {
        val uid = auth.currentUser?.uid ?: return mapOf("queuedPoints" to 0, "historyPending" to false)
        return try {
            mapOf("queuedPoints" to queue.count(uid, true), "historyPending" to (queue.count(uid) > 0),
                "trackError" to error, "online" to online())
        } catch (_: Exception) {
            mapOf("historyPending" to true, "online" to online(),
                "trackError" to "Could not read trip data on this phone. Keep app data and try again.")
        }
    }

    fun hasPending(): Boolean = runCatching { queue.count() > 0 }.getOrDefault(true)

    fun enqueue(uid: String, kind: String, path: String, fields: JSONObject, stored: (Boolean) -> Unit = {}) {
        // Ghi bền vững trước khi báo đã lưu; không đợi mạng trên luồng GPS/UI.
        val success = runCatching { queue.add(uid, kind, path, fields) }.isSuccess
        if (!success) error = "Could not save trip data on this phone. Free up storage and try again."
        stored(success)
        if (success) requestSync()
    }

    fun requestSync(force: Boolean = false) = worker.execute {
        runCatching { schedule(); drain(force) }.onFailure {
            error = "Could not read trip data on this phone. Keep app data and try again."
        }
    }

    private fun schedule() {
        val uid = auth.currentUser?.uid ?: return
        if (queue.count(uid) == 0) return
        if (scheduler.getPendingJob(JOB) == null) {
            scheduler.schedule(JobInfo.Builder(JOB, ComponentName(app, FleetSyncJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .setBackoffCriteria(30_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL).build())
        }
    }

    fun sync(finished: (Boolean) -> Unit) = worker.execute {
        drain(force = true)
        main.post {
            val retry = runCatching { auth.currentUser?.uid?.let { queue.count(it) > 0 } == true }
                .getOrDefault(true)
            finished(retry)
        }
    }

    private fun drain(force: Boolean = false) {
        try {
            val user = auth.currentUser ?: return
            if (queue.count(user.uid) == 0 || !online()) return
            val now = SystemClock.elapsedRealtime()
            if (!force && now - lastAttempt < 30_000L) return
            lastAttempt = now
            val project = FirebaseApp.getInstance().options.projectId ?: return
            val upload = FleetHistoryUpload(project, token = {
                Tasks.await(user.getIdToken(false), 15, TimeUnit.SECONDS).token
                    ?: error("Fleet session unavailable")
            }, ownsSession = { auth.currentUser?.uid == user.uid })
            queue.flush(user.uid, mayContinue = {
                auth.currentUser?.uid == user.uid && online() && SystemClock.elapsedRealtime() - now < 60_000L
            }, upload = upload::upload)
            error = null
        } catch (_: Exception) {
            error = "Route sync paused. Data stays on this phone; check your connection and vehicle access."
        }
    }
}
