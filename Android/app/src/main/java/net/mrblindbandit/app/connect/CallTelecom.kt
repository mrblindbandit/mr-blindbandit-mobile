package net.mrblindbandit.app.connect

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import net.mrblindbandit.app.BlindbanditFirebaseMessagingService
import net.mrblindbandit.app.MainActivity

/**
 * Self-managed ConnectionService so an incoming Blindbandit call can surface through Telecom
 * when the app is in the background. Failure here never blocks the in-app answer path.
 */
class BlindbanditConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(connectionManagerPhoneAccount: PhoneAccountHandle?, request: ConnectionRequest): Connection {
        val callId = extra(request, "call_id")
        val name = extra(request, "caller_name").ifBlank { "Blindbandit caller" }
        CallLog.i("telecom incoming connection callIdPresent=${callId.isNotBlank()}")
        return BanditConnection(applicationContext, callId, name, incoming = true)
    }

    override fun onCreateOutgoingConnection(connectionManagerPhoneAccount: PhoneAccountHandle?, request: ConnectionRequest): Connection {
        val callId = extra(request, "call_id")
        val name = extra(request, "caller_name").ifBlank { "Blindbandit" }
        return BanditConnection(applicationContext, callId, name, incoming = false)
    }
}

private class BanditConnection(
    private val appContext: Context,
    private val callId: String,
    private val displayName: String,
    incoming: Boolean,
) : Connection() {
    init {
        connectionProperties = PROPERTY_SELF_MANAGED
        audioModeIsVoip = true
        setCallerDisplayName(displayName, TelecomManager.PRESENTATION_ALLOWED)
        setAddress(Uri.fromParts(PhoneAccount.SCHEME_SIP, displayName, null), TelecomManager.PRESENTATION_ALLOWED)
        setInitializing()
        if (incoming) setRinging() else setDialing()
    }

    override fun onAnswer() {
        CallLog.i("telecom answer")
        setActive()
        launch(BlindbanditFirebaseMessagingService.ACTION_ANSWER_CALL, "answer")
    }

    override fun onReject() {
        CallLog.i("telecom reject")
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
        launch(BlindbanditFirebaseMessagingService.ACTION_DECLINE_CALL, "decline")
    }

    override fun onDisconnect() {
        CallLog.i("telecom disconnect")
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        launch(BlindbanditFirebaseMessagingService.ACTION_CALL_ENDED, "end")
    }

    private fun launch(action: String, callAction: String) {
        val intent = Intent(appContext, MainActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("call_id", callId)
            putExtra("call_action", callAction)
        }
        appContext.startActivity(intent)
    }
}

private fun extra(request: ConnectionRequest, key: String): String {
    val direct = request.extras?.getString(key)
    if (!direct.isNullOrBlank()) return direct
    return request.extras?.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS)?.getString(key).orEmpty()
}

/** Telecom registration lives next to the service so FCM can report an incoming call without the UI. */
object CallTelecom {
    private val reported = linkedSetOf<String>()

    fun reportIncoming(context: Context, callId: String, callerName: String) {
        if (callId.isBlank() || !reported.add(callId)) return
        val telecom = context.getSystemService(TelecomManager::class.java) ?: return
        val handle = accountHandle(context)
        try {
            val account = PhoneAccount.builder(handle, "Blindbandit")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .setSupportedUriSchemes(listOf(PhoneAccount.SCHEME_SIP))
                .build()
            telecom.registerPhoneAccount(account)
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, Uri.fromParts(PhoneAccount.SCHEME_SIP, callerName.ifBlank { "blindbandit" }, null))
                putString("call_id", callId)
                putString("caller_name", callerName)
            }
            telecom.addNewIncomingCall(handle, extras)
            CallLog.i("telecom addNewIncomingCall")
        } catch (e: Exception) {
            reported.remove(callId)
            CallLog.w("telecom incoming unavailable ${e.javaClass.simpleName}")
        }
    }

    fun reportEnded(callId: String) {
        reported.remove(callId)
    }

    private fun accountHandle(context: Context) =
        PhoneAccountHandle(ComponentName(context, BlindbanditConnectionService::class.java), "blindbandit")
}
