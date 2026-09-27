package net.mrblindbandit.app.safety

import android.content.Context
import net.mrblindbandit.app.AndroidAppPreferences

/**
 * On-device filter for objectionable language in messages from other people
 * (Google Play User Generated Content policy, App Store Review Guideline 1.2).
 * Matching words are masked before they are shown or read by TalkBack. On by default; can be
 * turned off in Settings > Safety. Reports, blocking and moderator review on the Blindbandit
 * server remain the primary protections.
 */
object ContentFilter {
    const val SETTING_KEY = "filterOffensiveLanguage"

    /**
     * Word stems for severe profanity, slurs and sexual terms. Case-insensitive, whole words, plus
     * common suffixes (plural, -ed, -er, -ing, -y and so on). Stems that are also the start of
     * everyday words are deliberately left out.
     */
    val blockedStems: List<String> = listOf(
        "fuck", "motherfuck", "shit", "bullshit", "bitch", "cunt", "asshole", "bastard", "pussy",
        "whore", "slut", "twat", "wanker", "porn", "nude", "rape", "rapist",
        "nigger", "nigga", "faggot", "fag", "retard", "chink", "kike", "tranny", "dyke", "wetback",
        "raghead", "beaner", "kys",
    )

    private val regex: Regex by lazy {
        val alternatives = blockedStems.sortedByDescending { it.length }.joinToString("|") { Regex.escape(it) }
        Regex("\\b(?:$alternatives)(?:s|es|ed|er|ers|ing|in|y|ty|ies|head|heads|face)?\\b", RegexOption.IGNORE_CASE)
    }

    fun mask(text: String): String = regex.replace(text) { "*".repeat(it.value.length) }

    fun containsBlockedLanguage(text: String): Boolean = regex.containsMatchIn(text)

    fun display(text: String, enabled: Boolean): String = if (enabled) mask(text) else text

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(AndroidAppPreferences.FILE, Context.MODE_PRIVATE).getBoolean(SETTING_KEY, true)
}
