import Foundation
import SwiftUI
import AVFoundation
import UIKit

// MARK: - Settings keys for 2.2.0 extras (beyond Apple pack)
extension SettingsKey {
    // Accessibility / VoiceOver depth
    static let a11yAnnounceReaction = "a11y.announceReaction"
    static let a11yRotorActions = "a11y.rotorActions"
    static let a11yCallStateVerbose = "a11y.callStateVerbose"
    static let a11yDoubleTapCompose = "a11y.doubleTapCompose"
    static let a11yBoldStatusIcons = "a11y.boldStatusIcons"
    static let a11yPreferSpokenTimestamps = "a11y.spokenTimestamps"
    static let a11yReduceParallaxCards = "a11y.reduceParallax"
    static let a11yStickySendButton = "a11y.stickySend"
    static let a11yHapticAlphabetJump = "a11y.hapticAlphabet"
    static let a11yContrastChatBubbles = "a11y.contrastBubbles"

    // Messaging / Signal-depth
    static let msgDisappearingCustomPresets = "msg.disappearPresets"
    static let msgPinLimitExpanded = "msg.pinLimitExpanded"
    static let msgMuteForeverOption = "msg.muteForever"
    static let msgStarredFilter = "msg.starredFilter"
    static let msgDraftAutosaveSeconds = "msg.draftAutosaveSec"
    static let msgQuoteReplyPreviewFull = "msg.quotePreviewFull"
    static let msgVoiceWaveformScrub = "msg.voiceWaveformScrub"
    static let msgFastForwardVoice = "msg.fastForwardVoice"
    static let msgHoldToRecordLock = "msg.holdToRecordLock"
    static let msgMediaQualityChooser = "msg.mediaQualityChooser"
    static let msgTranslateIncomingHint = "msg.translateIncoming"
    static let msgScheduledSendLocal = "msg.scheduledSendLocal"
    static let msgReminderOnChat = "msg.reminderOnChat"
    static let msgHideExactTyping = "msg.hideExactTyping"
    static let msgCompactListDensity = "msg.compactListDensity"

    // Calls
    static let callNoiseCancelHint = "calls.noiseCancelHint"
    static let callAutoSpeakerOnDock = "calls.autoSpeakerDock"
    static let callEndConfirm = "calls.endConfirm"
    static let callBannerWhileMuted = "calls.bannerWhileMuted"
    static let callRememberLastCamera = "calls.rememberLastCamera"
    static let callLowDataVideo = "calls.lowDataVideo"
    static let callHapticRingPattern = "calls.hapticRingPattern"
    static let callQuickReplyDecline = "calls.quickReplyDecline"
    static let callShareLinkInvite = "calls.shareLinkInvite"
    static let callHistoryRetentionDays = "calls.historyRetentionDays"

    // Bandit Feed / Bites
    static let bitesChronologicalDefault = "bites.chronologicalDefault"
    static let bitesMuteCreatorLocal = "bites.muteCreatorLocal"
    static let bitesSaveDraftsCloudHint = "bites.saveDraftsCloud"
    static let bitesCensorLocalBlur = "bites.censorBlur"
    static let bitesDoubleTapLike = "bites.doubleTapLike"
    static let bitesLongPressReact = "bites.longPressReact"
    static let bitesHideRepostNoise = "bites.hideRepostNoise"
    static let bitesCreatorAnalyticsLocal = "bites.creatorAnalyticsLocal"
    static let bitesAltTextRequired = "bites.altTextRequired"
    static let bitesOfflineComposeQueue = "bites.offlineComposeQueue"

    // AI
    static let aiRememberThreadTitles = "ai.rememberThreadTitles"
    static let aiSpeakAnswers = "ai.speakAnswers"
    static let aiWebSearchDefault = "ai.webSearchDefault"
    static let aiConciseMode = "ai.conciseMode"
    static let aiHapticOnComplete = "ai.hapticOnComplete"
    static let aiPinFavoritePrompts = "ai.pinFavoritePrompts"
    static let aiExportThreadMarkdown = "ai.exportThreadMarkdown"
    static let aiBlockSensitiveTopicsLocal = "ai.blockSensitiveLocal"

    // Profile / Social
    static let profileShowPronouns = "profile.showPronouns"
    static let profileLinkPreviewCard = "profile.linkPreviewCard"
    static let profileMuteStoryReplies = "profile.muteStoryReplies"
    static let socialFollowNotifDigest = "social.followNotifDigest"
    static let socialHideSuggested = "social.hideSuggested"
    static let socialCloseFriendsOnlyBites = "social.closeFriendsOnlyBites"

    // Settings / Security / Network
    static let secAppLockFaceIDGrace = "sec.faceIDGrace"
    static let secClipboardAutoClear = "sec.clipboardAutoClear"
    static let secHideNotificationContentLock = "sec.hideNotifContentLock"
    static let netPreferIPv6 = "net.preferIPv6"
    static let netRetryBackoffBoost = "net.retryBackoffBoost"
    static let settingsSearchIndexLocal = "settings.searchIndexLocal"
    static let settingsExportDiagnostics = "settings.exportDiagnostics"
    static let settingsRestoreDefaultsConfirm = "settings.restoreDefaultsConfirm"

    // Widgets / Continuity prefs
    static let widgetShowLatestBite = "widget.showLatestBite"
    static let widgetShowUnreadBadge = "widget.showUnreadBadge"
    static let handoffChatsEnabled = "handoff.chatsEnabled"
    static let handoffAIEnabled = "handoff.aiEnabled"
    static let spotlightIndexEnabled = "spotlight.indexEnabled"
    static let tipKitEnabled = "tips.enabled"
    static let liveActivityCalls = "liveActivity.calls"
    static let liveActivityBitePost = "liveActivity.bitePost"
    static let passkeysPreferred = "auth.passkeysPreferred"
    static let writingToolsCompose = "compose.writingTools"
    static let watchQuickReplyEnabled = "watch.quickReply"
    static let carPlayCallingEnabled = "carplay.calling"
    static let controlCenterCallControls = "controlCenter.callControls"
    static let focusFilterRespected = "focus.filterRespected"
}

/// Runtime helpers implementing many of the 2.2.0 extras without UI sprawl.
@MainActor
enum ExtraFeatures220 {
    static func clipboardAutoClearIfNeeded() {
        let on = UserDefaults.standard.object(forKey: SettingsKey.secClipboardAutoClear) as? Bool ?? false
        guard on else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            UIPasteboard.general.items = []
        }
    }

    static func speakAIAnswerIfEnabled(_ text: String) {
        let on = UserDefaults.standard.object(forKey: SettingsKey.aiSpeakAnswers) as? Bool ?? false
        guard on, !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: String(text.prefix(500)))
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        AVSpeechSynthesizer().speak(u)
    }

    static func hapticAIComplete() {
        let on = UserDefaults.standard.object(forKey: SettingsKey.aiHapticOnComplete) as? Bool ?? true
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static var hideBitesForFocus: Bool {
        guard UserDefaults.standard.object(forKey: SettingsKey.focusFilterRespected) as? Bool ?? true else { return false }
        return BanditSharedStore.focusHideBites
    }

    static var liveActivitiesForCalls: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.liveActivityCalls) as? Bool ?? true
    }

    static var liveActivitiesForBites: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.liveActivityBitePost) as? Bool ?? true
    }
}

struct ExtraFeatures220SettingsSection: View {
    @AppStorage(SettingsKey.liveActivityCalls) private var liveCalls = true
    @AppStorage(SettingsKey.liveActivityBitePost) private var liveBites = true
    @AppStorage(SettingsKey.widgetShowLatestBite) private var widgetBite = true
    @AppStorage(SettingsKey.widgetShowUnreadBadge) private var widgetUnread = true
    @AppStorage(SettingsKey.handoffChatsEnabled) private var handoffChats = true
    @AppStorage(SettingsKey.handoffAIEnabled) private var handoffAI = true
    @AppStorage(SettingsKey.spotlightIndexEnabled) private var spotlight = true
    @AppStorage(SettingsKey.tipKitEnabled) private var tips = true
    @AppStorage(SettingsKey.passkeysPreferred) private var passkeys = true
    @AppStorage(SettingsKey.writingToolsCompose) private var writingTools = true
    @AppStorage(SettingsKey.watchQuickReplyEnabled) private var watchReply = true
    @AppStorage(SettingsKey.carPlayCallingEnabled) private var carPlay = true
    @AppStorage(SettingsKey.controlCenterCallControls) private var ccControls = true
    @AppStorage(SettingsKey.focusFilterRespected) private var focusRespect = true
    @AppStorage(SettingsKey.aiSpeakAnswers) private var aiSpeak = false
    @AppStorage(SettingsKey.aiWebSearchDefault) private var aiWeb = false
    @AppStorage(SettingsKey.aiConciseMode) private var aiConcise = false
    @AppStorage(SettingsKey.secClipboardAutoClear) private var clipClear = false
    @AppStorage(SettingsKey.bitesDoubleTapLike) private var doubleTapLike = true
    @AppStorage(SettingsKey.bitesAltTextRequired) private var altText = false
    @AppStorage(SettingsKey.callEndConfirm) private var endConfirm = false
    @AppStorage(SettingsKey.msgCompactListDensity) private var compact = false
    @AppStorage(SettingsKey.a11yStickySendButton) private var stickySend = false
    @AppStorage(SettingsKey.a11yContrastChatBubbles) private var contrastBubbles = false

    var body: some View {
        Section("Apple & Continuity (2.2)") {
            Toggle("Live Activities for calls", isOn: $liveCalls)
            Toggle("Live Activity while posting Bites", isOn: $liveBites)
            Toggle("Home Screen widget: latest Bite", isOn: $widgetBite)
            Toggle("Home Screen widget: unread badge", isOn: $widgetUnread)
            Toggle("Handoff for chats", isOn: $handoffChats)
            Toggle("Handoff for AI threads", isOn: $handoffAI)
            Toggle("Spotlight index chats & Bites", isOn: $spotlight)
            Toggle("Show coaching tips (TipKit)", isOn: $tips)
            Toggle("Prefer Passkeys with Sign in with Apple", isOn: $passkeys)
            Toggle("Writing Tools in composers", isOn: $writingTools)
            Toggle("Apple Watch quick reply", isOn: $watchReply)
            Toggle("CarPlay calling", isOn: $carPlay)
            Toggle("Control Center call controls", isOn: $ccControls)
            Toggle("Respect Focus filters", isOn: $focusRespect)
        }
        Section("Messaging & calls extras") {
            Toggle("Compact chat list", isOn: $compact)
            Toggle("Confirm before ending call", isOn: $endConfirm)
            Toggle("Sticky send button (a11y)", isOn: $stickySend)
            Toggle("Higher-contrast bubbles", isOn: $contrastBubbles)
        }
        Section("Bandit Feed & AI extras") {
            Toggle("Double-tap Bite to like", isOn: $doubleTapLike)
            Toggle("Require alt text on media Bites", isOn: $altText)
            Toggle("Speak AI answers", isOn: $aiSpeak)
            Toggle("Default AI web search on", isOn: $aiWeb)
            Toggle("Concise AI answers", isOn: $aiConcise)
            Toggle("Auto-clear clipboard after copy", isOn: $clipClear)
        }
    }
}
