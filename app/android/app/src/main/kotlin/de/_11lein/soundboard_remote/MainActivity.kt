package de._11lein.soundboard_remote

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "soundboard/bt"
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private var socket: BluetoothSocket? = null
    private var output: OutputStream? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "bondedDevices" -> bondedDevices(result)
                "connect" -> connect(call.argument<String>("address"), result)
                "disconnect" -> { closeSocket(); result.success(null) }
                "send" -> send(call.argument<String>("data"), result)
                "isConnected" -> result.success(socket?.isConnected == true)
                else -> result.notImplemented()
            }
        }
    }

    private fun bondedDevices(result: MethodChannel.Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                result.error("NO_BT", "Kein Bluetooth-Adapter", null); return
            }
            if (!adapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth ist aus", null); return
            }
            val list = adapter.bondedDevices.map {
                mapOf("name" to (it.name ?: ""), "address" to it.address)
            }
            result.success(list)
        } catch (e: SecurityException) {
            result.error("PERM", "Bluetooth-Berechtigung fehlt", null)
        } catch (e: Exception) {
            result.error("ERR", e.message, null)
        }
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        if (address == null) {
            result.error("ARG", "Keine Adresse", null); return
        }
        thread {
            try {
                closeSocket()
                val adapter = BluetoothAdapter.getDefaultAdapter()
                val device: BluetoothDevice = adapter.getRemoteDevice(address)
                adapter.cancelDiscovery()
                val s = device.createRfcommSocketToServiceRecord(sppUuid)
                s.connect()
                socket = s
                output = s.outputStream
                runOnUiThread { result.success(null) }
            } catch (e: SecurityException) {
                closeSocket()
                runOnUiThread { result.error("PERM", "Berechtigung fehlt", null) }
            } catch (e: Exception) {
                closeSocket()
                runOnUiThread { result.error("CONNECT", e.message, null) }
            }
        }
    }

    private fun send(data: String?, result: MethodChannel.Result) {
        val out = output
        if (out == null || socket?.isConnected != true) {
            result.error("NOT_CONNECTED", "Nicht verbunden", null); return
        }
        thread {
            try {
                out.write((data ?: "").toByteArray(Charsets.US_ASCII))
                out.flush()
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                closeSocket()
                runOnUiThread {
                    result.error("SEND", e.message, null)
                    channel?.invokeMethod("disconnected", null)
                }
            }
        }
    }

    private fun closeSocket() {
        try { output?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        output = null
        socket = null
    }

    override fun onDestroy() {
        closeSocket()
        super.onDestroy()
    }
}
