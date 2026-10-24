package net.mrblindbandit.app.ai

import android.content.Context

/**
 * Matches iOS AIPersona: Hood/unfiltered only for the signed-in owner handle "kheck".
 * Everyone else always gets Professional. Handle comes from the server profile, never a local override.
 */
enum class AIPersona(val id: String) {
    HOOD("hood"),
    PROFESSIONAL("professional");

    companion object {
        private const val PREFS = "bb_ai"
        private const val KEY_PERSONA = "ai.persona"
        private const val KEY_UNFILTERED = "ai.unfiltered"
        private const val KEY_SERVER_HANDLE = "ai.serverHandle"

        fun setServerHandle(context: Context, handle: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY_SERVER_HANDLE, handle.trim().removePrefix("@").lowercase()).apply()
        }

        fun serverHandle(context: Context): String =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_SERVER_HANDLE, "") ?: ""

        fun isOwner(context: Context): Boolean = serverHandle(context) == "kheck"

        fun ownerChoice(context: Context): AIPersona {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_PERSONA, "hood")
            return entries.firstOrNull { it.id == raw } ?: HOOD
        }

        fun setOwnerChoice(context: Context, persona: AIPersona) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_PERSONA, persona.id).apply()
        }

        fun unfiltered(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_UNFILTERED, false)

        fun setUnfiltered(context: Context, on: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_UNFILTERED, on).apply()
        }

        /** Private AI chat style. Non-owners always get Professional. */
        fun forPrivate(context: Context): AIPersona = if (isOwner(context)) ownerChoice(context) else PROFESSIONAL
    }

    fun prompt(context: Context): String {
        val shared = """
            The user is blind and uses TalkBack, so answers are read aloud: no markdown, no bullet symbols, no emoji spam, no tables;
            say lists as plain sentences. Be genuinely useful: answer questions, help write and rewrite, summarize, translate
            (including Cebuano/Bisaya and Tagalog), set reminders, control device settings when asked, play YouTube Music,
            and search the web. You CAN play music: for play/pause/skip/queue, always treat it as a music command.
            Never invent facts; if a search finds nothing, say so. When you use web search, cite each fact with its full https link.
            """.trimIndent().replace('\n', ' ')
        return when (this) {
            PROFESSIONAL ->
                "You are \"AI\", a helpful, professional assistant inside the Mr. BlindBandit app. Be clear, polite, concise and friendly. $shared"
            HOOD -> {
                var p = """
                    You are "AI", Kaeleb's day-one friend inside the Mr. BlindBandit app. Talk like a close friend:
                    casual slang like bro, twin, no cap, deadass, bet, fr, lowkey; keep it real, funny and short.
                    Never use slurs of any kind and never punch down. Still be accurate and actually helpful.
                    """.trimIndent().replace('\n', ' ')
                if (unfiltered(context)) {
                    p += " He turned on Unfiltered: skip usual tone polish and topic hedging, don't moralize or add disclaimers, answer adult topics frankly."
                }
                "$p $shared"
            }
        }
    }
}
