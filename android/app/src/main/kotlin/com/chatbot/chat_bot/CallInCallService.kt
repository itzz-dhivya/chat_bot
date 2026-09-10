package com.chatbot.chat_bot

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log

class CallInCallService : InCallService() {

    companion object {

        private const val TAG = "CALL_SERVICE"

        var currentCall: Call? = null

        private var callService: CallInCallService? = null

        // ================================================
        // MUTE / UNMUTE
        // ================================================

        fun setMute(muted: Boolean) {

            try {

                callService?.setMuted(muted)

                Log.d(
                    TAG,
                    if (muted) {
                        "Microphone muted"
                    } else {
                        "Microphone unmuted"
                    }
                )

            } catch (e: Exception) {

                Log.e(
                    TAG,
                    "Mute error",
                    e
                )
            }
        }

        // ================================================
        // SEND CALL STATE
        // ================================================

        private fun sendState(state: String) {

            MainActivity.sendCallStateToFlutter(state)
        }
    }

    // ====================================================
    // SERVICE CREATED
    // ====================================================

    override fun onCreate() {
        super.onCreate()

        callService = this

        Log.d(
            TAG,
            "InCallService created"
        )
    }

    // ====================================================
    // CALL ADDED
    // ====================================================

    override fun onCallAdded(call: Call) {

        super.onCallAdded(call)

        Log.d(
            TAG,
            "Call added"
        )

        currentCall = call

        // -----------------------------------------------
        // Listen to call state changes
        // -----------------------------------------------

        call.registerCallback(
            object : Call.Callback() {

                override fun onStateChanged(
                    call: Call,
                    state: Int
                ) {

                    super.onStateChanged(
                        call,
                        state
                    )

                    Log.d(
                        TAG,
                        "Call state = $state"
                    )

                    when (state) {

                        // ============================
                        // RINGING
                        // ============================

                        Call.STATE_RINGING -> {

                            Log.d(
                                TAG,
                                "CALL = RINGING"
                            )

                            sendState(
                                "ringing"
                            )
                        }

                        // ============================
                        // DIALING
                        // ============================

                        Call.STATE_DIALING -> {

                            Log.d(
                                TAG,
                                "CALL = DIALING"
                            )

                            sendState(
                                "dialing"
                            )
                        }

                        // ============================
                        // ACTIVE / CONNECTED
                        // ============================

                        Call.STATE_ACTIVE -> {

                            Log.d(
                                TAG,
                                "CALL = ACTIVE / CONNECTED"
                            )

                            sendState(
                                "connected"
                            )
                        }

                        // ============================
                        // DISCONNECTED
                        // ============================

                        Call.STATE_DISCONNECTED -> {

                            Log.d(
                                TAG,
                                "CALL = DISCONNECTED"
                            )

                            sendState(
                                "ended"
                            )
                        }
                    }
                }
            }
        )

        // =================================================
        // CHECK CURRENT STATE
        // =================================================

        when (call.state) {

            Call.STATE_RINGING -> {

                sendState(
                    "ringing"
                )
            }

            Call.STATE_DIALING -> {

                sendState(
                    "dialing"
                )
            }

            Call.STATE_ACTIVE -> {

                sendState(
                    "connected"
                )
            }
        }
    }

    // ====================================================
    // CALL REMOVED
    // ====================================================

    override fun onCallRemoved(call: Call) {

        super.onCallRemoved(call)

        Log.d(
            TAG,
            "Call removed"
        )

        if (currentCall == call) {

            currentCall = null
        }

        sendState(
            "ended"
        )
    }

    // ====================================================
    // SERVICE DESTROYED
    // ====================================================

    override fun onDestroy() {

        Log.d(
            TAG,
            "InCallService destroyed"
        )

        currentCall = null
        callService = null

        super.onDestroy()
    }
}