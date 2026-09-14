import Foundation

// AVAudioFile accepts string-backed audio setting keys. Xcode 16.4 does not expose
// an AVLinearPCMIsAlignedHighKey Swift symbol, so keep the compatible Core Audio key
// local to the app instead of blocking the entire build.
let AVLinearPCMIsAlignedHighKey = "AVLinearPCMIsAlignedHigh"
