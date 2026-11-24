package br.com.aifitness.ai_fitness

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var pending: Pair<String, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai_fitness/cardio").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(CardioService.session?.snapshot())
                "finish" -> {
                    CardioService.session?.finish()
                    stopService(Intent(this, CardioService::class.java))
                    result.success(CardioService.session?.snapshot())
                }
                "clear" -> {
                    val session = CardioService.session
                    if (session?.ended != null && session.id == call.arguments) CardioService.session = null
                    result.success(null)
                }
                "start" -> {
                    val mode = call.arguments as? String
                    if (mode != "walk" && mode != "bike") {
                        result.error("mode", "Escolha caminhada ou pedalada.", null)
                        return@setMethodCallHandler
                    }
                    if (pending != null || CardioService.session != null) {
                        result.error("busy", "Já existe uma atividade em andamento ou pendente.", null)
                        return@setMethodCallHandler
                    }
                    val permissions = mutableListOf<String>()
                    if (!granted(Manifest.permission.ACCESS_FINE_LOCATION)) {
                        permissions += Manifest.permission.ACCESS_FINE_LOCATION
                        permissions += Manifest.permission.ACCESS_COARSE_LOCATION
                    }
                    if (mode == "walk" && Build.VERSION.SDK_INT >= 29 && !granted(Manifest.permission.ACTIVITY_RECOGNITION)) {
                        permissions += Manifest.permission.ACTIVITY_RECOGNITION
                    }
                    if (permissions.isEmpty()) startCardio(mode, result) else {
                        pending = mode to result
                        requestPermissions(permissions.toTypedArray(), 604)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 604) return
        val request = pending ?: return
        pending = null
        startCardio(request.first, request.second)
    }

    private fun granted(permission: String) = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun startCardio(mode: String, result: MethodChannel.Result) {
        if (!granted(Manifest.permission.ACCESS_FINE_LOCATION)) {
            result.error("location", "Permita localização precisa nas configurações do Android para usar GPS.", null)
            return
        }
        if (!getSystemService(LocationManager::class.java).isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            result.error("gps", "Ative a localização do celular e tente novamente.", null)
            return
        }
        val session = CardioSession(UUID.randomUUID().toString(), mode, SystemClock.elapsedRealtime())
        CardioService.session = session
        try {
            val intent = Intent(this, CardioService::class.java)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            result.success(session.snapshot())
        } catch (_: RuntimeException) {
            CardioService.session = null
            result.error("start", "Não foi possível iniciar o rastreamento. Abra a aba Cardio e tente novamente.", null)
        }
    }
}
