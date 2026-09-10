package com.chatbot.chat_bot

import android.Manifest
import android.app.Activity
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.telecom.Call
import android.telecom.TelecomManager
import android.util.Log

import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {

        private const val CHANNEL = "call_state"

        private const val REQUEST_PHONE_PERMISSION = 100
        private const val REQUEST_DIALER_ROLE = 200

        private var methodChannel: MethodChannel? = null

        // =====================================================
        // SEND CALL STATE TO FLUTTER
        // =====================================================

        fun sendCallStateToFlutter(state: String) {

            Log.d(
                "CALL_NATIVE",
                "Sending state to Flutter = $state"
            )

            methodChannel?.invokeMethod(
                "callState",
                state
            )
        }
    }

    // =========================================================
    // FLUTTER ENGINE
    // =========================================================

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel?.setMethodCallHandler { call, result ->

            when (call.method) {

                // -------------------------------------------------
                // START LISTENING
                // -------------------------------------------------

                "startListening" -> {

                    requestPhonePermission()

                    result.success(true)
                }

                // -------------------------------------------------
                // REQUEST DEFAULT DIALER
                // -------------------------------------------------

                "requestDialerRole" -> {

                    requestDefaultDialer()

                    result.success(true)
                }

                // -------------------------------------------------
                // PLACE CELLULAR CALL
                // -------------------------------------------------

                "placeCall" -> {

                    val phoneNumber =
                        call.argument<String>("phoneNumber")

                    if (phoneNumber.isNullOrBlank()) {

                        result.error(
                            "INVALID_NUMBER",
                            "Phone number is empty",
                            null
                        )

                    } else {

                        placePhoneCall(
                            phoneNumber.trim()
                        )

                        result.success(true)
                    }
                }

                // -------------------------------------------------
                // END CALL
                // -------------------------------------------------

                "endCall" -> {

                    endCurrentCall()

                    result.success(true)
                }

                // -------------------------------------------------
                // MUTE
                // -------------------------------------------------

                "muteCall" -> {

                    muteCurrentCall()

                    result.success(true)
                }

                // -------------------------------------------------
                // UNMUTE
                // -------------------------------------------------

                "unmuteCall" -> {

                    unmuteCurrentCall()

                    result.success(true)
                }

                else -> {

                    result.notImplemented()
                }
            }
        }
    }

    // =========================================================
    // PHONE PERMISSION
    // =========================================================

    private fun requestPhonePermission() {

        val permissions =
            mutableListOf<String>()

        // READ PHONE STATE
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_PHONE_STATE
            ) != PackageManager.PERMISSION_GRANTED
        ) {

            permissions.add(
                Manifest.permission.READ_PHONE_STATE
            )
        }

        // CALL PHONE
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.CALL_PHONE
            ) != PackageManager.PERMISSION_GRANTED
        ) {

            permissions.add(
                Manifest.permission.CALL_PHONE
            )
        }

        if (permissions.isNotEmpty()) {

            Log.d(
                "CALL_NATIVE",
                "Requesting phone permissions"
            )

            ActivityCompat.requestPermissions(
                this,
                permissions.toTypedArray(),
                REQUEST_PHONE_PERMISSION
            )

        } else {

            Log.d(
                "CALL_NATIVE",
                "Phone permissions already granted"
            )
        }
    }

    // =========================================================
    // PLACE PHONE CALL
    // =========================================================

    private fun placePhoneCall(
        phoneNumber: String
    ) {

        // Check CALL_PHONE permission
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.CALL_PHONE
            ) != PackageManager.PERMISSION_GRANTED
        ) {

            Log.d(
                "CALL_NATIVE",
                "CALL_PHONE permission not granted"
            )

            requestPhonePermission()

            return
        }

        try {

            val telecomManager =
                getSystemService(
                    TELECOM_SERVICE
                ) as TelecomManager

            val phoneUri =
                Uri.parse(
                    "tel:${Uri.encode(phoneNumber)}"
                )

            Log.d(
                "CALL_NATIVE",
                "Placing call to $phoneNumber"
            )

            telecomManager.placeCall(
                phoneUri,
                Bundle()
            )

            Log.d(
                "CALL_NATIVE",
                "placeCall() executed"
            )

        } catch (e: SecurityException) {

            Log.e(
                "CALL_NATIVE",
                "CALL_PHONE permission/security error",
                e
            )

        } catch (e: Exception) {

            Log.e(
                "CALL_NATIVE",
                "Error placing phone call",
                e
            )
        }
    }

    // =========================================================
    // DEFAULT DIALER ROLE
    // =========================================================

    private fun requestDefaultDialer() {

        // ROLE_DIALER available from Android 10
        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.Q
        ) {

            Log.d(
                "CALL_NATIVE",
                "ROLE_DIALER requires Android 10+"
            )

            return
        }

        val roleManager =
            getSystemService(
                ROLE_SERVICE
            ) as RoleManager

        // -----------------------------------------------------
        // CHECK ROLE AVAILABILITY
        // -----------------------------------------------------

        val available =
            roleManager.isRoleAvailable(
                RoleManager.ROLE_DIALER
            )

        Log.d(
            "CALL_NATIVE",
            "Dialer role available = $available"
        )

        if (!available) {

            Log.d(
                "CALL_NATIVE",
                "Dialer role is not available"
            )

            return
        }

        // -----------------------------------------------------
        // CHECK CURRENT DEFAULT
        // -----------------------------------------------------

        val alreadyDefault =
            roleManager.isRoleHeld(
                RoleManager.ROLE_DIALER
            )

        Log.d(
            "CALL_NATIVE",
            "Already default dialer = $alreadyDefault"
        )

        if (alreadyDefault) {

            Log.d(
                "CALL_NATIVE",
                "Chat Bot is already the default dialer"
            )

            return
        }

        // -----------------------------------------------------
        // REQUEST ROLE
        // -----------------------------------------------------

        Log.d(
            "CALL_NATIVE",
            "Requesting default dialer role"
        )

        val intent =
            roleManager.createRequestRoleIntent(
                RoleManager.ROLE_DIALER
            )

        startActivityForResult(
            intent,
            REQUEST_DIALER_ROLE
        )
    }

    // =========================================================
    // DIALER ROLE RESULT
    // =========================================================

    @Deprecated(
        "Deprecated in Android API"
    )
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {

        super.onActivityResult(
            requestCode,
            resultCode,
            data
        )

        if (
            requestCode ==
            REQUEST_DIALER_ROLE
        ) {

            if (
                resultCode ==
                Activity.RESULT_OK
            ) {

                Log.d(
                    "CALL_NATIVE",
                    "Default dialer role ACCEPTED"
                )

            } else {

                Log.d(
                    "CALL_NATIVE",
                    "Default dialer role REJECTED"
                )
            }

            // -------------------------------------------------
            // VERIFY ROLE
            // -------------------------------------------------

            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.Q
            ) {

                val roleManager =
                    getSystemService(
                        ROLE_SERVICE
                    ) as RoleManager

                val isDefault =
                    roleManager.isRoleHeld(
                        RoleManager.ROLE_DIALER
                    )

                Log.d(
                    "CALL_NATIVE",
                    "Final default dialer status = $isDefault"
                )
            }
        }
    }

    // =========================================================
    // END CURRENT CALL
    // =========================================================

    private fun endCurrentCall() {

        val call =
            CallInCallService.currentCall

        if (call != null) {

            Log.d(
                "CALL_NATIVE",
                "Disconnecting current call"
            )

            try {

                call.disconnect()

                Log.d(
                    "CALL_NATIVE",
                    "Call disconnect requested"
                )

            } catch (e: Exception) {

                Log.e(
                    "CALL_NATIVE",
                    "Error ending call",
                    e
                )
            }

        } else {

            Log.d(
                "CALL_NATIVE",
                "No active call"
            )
        }
    }

    // =========================================================
    // MUTE CURRENT CALL
    // =========================================================

    private fun muteCurrentCall() {

        val call =
            CallInCallService.currentCall

        if (call != null) {

            Log.d(
                "CALL_NATIVE",
                "Mute requested"
            )

            try {

                CallInCallService.setMute(
                    true
                )

            } catch (e: Exception) {

                Log.e(
                    "CALL_NATIVE",
                    "Mute error",
                    e
                )
            }

        } else {

            Log.d(
                "CALL_NATIVE",
                "No active call to mute"
            )
        }
    }

    // =========================================================
    // UNMUTE CURRENT CALL
    // =========================================================

    private fun unmuteCurrentCall() {

        val call =
            CallInCallService.currentCall

        if (call != null) {

            Log.d(
                "CALL_NATIVE",
                "Unmute requested"
            )

            try {

                CallInCallService.setMute(
                    false
                )

            } catch (e: Exception) {

                Log.e(
                    "CALL_NATIVE",
                    "Unmute error",
                    e
                )
            }

        } else {

            Log.d(
                "CALL_NATIVE",
                "No active call to unmute"
            )
        }
    }

    // =========================================================
    // PERMISSION RESULT
    // =========================================================

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {

        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (
            requestCode ==
            REQUEST_PHONE_PERMISSION
        ) {

            var allGranted = true

            for (result in grantResults) {

                if (
                    result !=
                    PackageManager.PERMISSION_GRANTED
                ) {

                    allGranted = false
                    break
                }
            }

            if (allGranted) {

                Log.d(
                    "CALL_NATIVE",
                    "All phone permissions granted"
                )

            } else {

                Log.d(
                    "CALL_NATIVE",
                    "Phone permission denied"
                )
            }
        }
    }

    // =========================================================
    // DESTROY
    // =========================================================

    override fun onDestroy() {

        methodChannel = null

        super.onDestroy()
    }
}