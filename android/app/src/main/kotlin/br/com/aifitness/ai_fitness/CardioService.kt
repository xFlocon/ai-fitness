package br.com.aifitness.ai_fitness

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.SystemClock

internal class CardioSession(val id: String, val mode: String, private val started: Long) {
    var ended: Long? = null
        private set
    var error: String? = null
    var steps: Int? = null
    private var firstStep: Int? = null
    private var anchor: Location? = null
    private var lastFix: Location? = null
    private var meters = 0.0
    private var kmh: Double? = null

    fun step(total: Int) {
        val base = firstStep ?: total.also { firstStep = it }
        steps = maxOf(steps ?: 0, total - base)
    }

    fun fix(location: Location) {
        val time = location.elapsedRealtimeNanos / 1_000_000
        if (time < started || SystemClock.elapsedRealtime() - time > 15_000 ||
            !location.hasAccuracy() || location.accuracy > 25 ||
            time <= (lastFix?.elapsedRealtimeNanos?.div(1_000_000) ?: -1)) return
        val previous = anchor
        val gap = lastFix?.let { (location.elapsedRealtimeNanos - it.elapsedRealtimeNanos) / 1e9 }
        lastFix = location
        val maxSpeed = if (mode == "walk") 4.5 else 32.0
        kmh = if (location.hasSpeed() && location.speed.toDouble() in 0.0..maxSpeed) location.speed * 3.6 else null
        // ponytail: skip noisy fixes and gaps; add route smoothing if field tests warrant it.
        if (previous == null || (gap ?: 0.0) > 25) {
            anchor = location
            return
        }
        val delta = previous.distanceTo(location)
        val seconds = (location.elapsedRealtimeNanos - previous.elapsedRealtimeNanos) / 1e9
        if (delta / seconds > maxSpeed) return
        if (delta >= maxOf(5f, maxOf(previous.accuracy, location.accuracy))) {
            meters += delta
            anchor = location
            if (kmh == null) kmh = delta * 3.6 / seconds
        }
    }

    fun finish() { if (ended == null) ended = SystemClock.elapsedRealtime() }

    fun snapshot(): Map<String, Any?> {
        val now = SystemClock.elapsedRealtime()
        val gps = lastFix?.let { now - it.elapsedRealtimeNanos / 1_000_000 <= 15_000 } ?: false
        return mapOf("id" to id, "mode" to mode, "seconds" to ((ended ?: now) - started) / 1000,
            "meters" to meters, "speed" to kmh.takeIf { gps && ended == null }, "gps" to gps,
            "fixed" to (lastFix != null), "steps" to steps, "ended" to (ended != null), "error" to error)
    }
}

class CardioService : Service(), LocationListener, SensorEventListener {
    companion object { internal var session: CardioSession? = null }
    private var tracking: CardioSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val active = session
        if (active == null || active.ended != null) {
            stopSelf()
            return START_NOT_STICKY
        }
        tracking = active
        try {
            val channel = "cardio_tracking"
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(channel, "Rastreamento de cardio", NotificationManager.IMPORTANCE_LOW))
                Notification.Builder(this, channel)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
            startForeground(605, builder.setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle(if (active.mode == "walk") "Caminhada em andamento" else "Pedalada em andamento")
                .setContentText("Abra AI Fitness → Cardio para terminar.").setContentIntent(open).setOngoing(true).build())
            getSystemService(LocationManager::class.java).requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, this)
            if (active.mode == "walk" && (Build.VERSION.SDK_INT < 29 ||
                    checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED)) {
                val manager = getSystemService(SensorManager::class.java)
                manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)?.let {
                    try { manager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) } catch (_: SecurityException) { }
                }
            }
        } catch (_: RuntimeException) {
            active.error = "Rastreamento interrompido. Confira se GPS e permissão de localização precisa estão ativos."
            active.finish()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onLocationChanged(location: Location) { tracking?.takeIf { it.ended == null }?.fix(location) }
    override fun onProviderDisabled(provider: String) { }
    override fun onProviderEnabled(provider: String) { }
    override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) { }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) { }
    override fun onSensorChanged(event: SensorEvent) {
        tracking?.takeIf { it.ended == null }?.step(event.values[0].toInt())
    }

    override fun onDestroy() {
        getSystemService(LocationManager::class.java).removeUpdates(this)
        getSystemService(SensorManager::class.java).unregisterListener(this)
        tracking?.finish()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
