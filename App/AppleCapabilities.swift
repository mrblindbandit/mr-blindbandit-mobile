import Foundation
import SwiftUI
import CoreLocation
import GroupActivities
#if canImport(WeatherKit)
import WeatherKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - WeatherKit (AI chat tool)

enum WeatherLookup {
    static func forecast(_ place: String) async -> String {
        #if canImport(WeatherKit)
        let query = place.trimmingCharacters(in: .whitespaces).isEmpty ? "Cebu City" : place
        guard let loc = try? await CLGeocoder().geocodeAddressString(query).first?.location else { return "I couldn't find \(query) on the map." }
        do {
            let w = try await WeatherService.shared.weather(for: loc)
            let c = w.currentWeather
            let temp = c.temperature.converted(to: UnitTemperature(forLocale: .current)).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))
            var out = "\(query): \(c.condition.description), \(temp), humidity \(Int(c.humidity * 100)) percent."
            if let today = w.dailyForecast.first {
                out += " Today high \(today.highTemperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))), low \(today.lowTemperature.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0))))), \(Int(today.precipitationChance * 100)) percent chance of rain."
            }
            if let next = w.hourlyForecast.dropFirst().first(where: { $0.precipitationChance >= 0.5 }) {
                out += " Rain likely around \(next.date.formatted(date: .omitted, time: .shortened))."
            }
            return out + " Weather data from Apple Weather."
        } catch { return "Weather isn't available right now (\(error.localizedDescription))." }
        #else
        return "Weather isn't available on this iPhone."
        #endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "Gets current weather and today's forecast from Apple Weather for a city or place."
    @Generable struct Arguments { @Guide(description: "City or place, like 'Cebu City' or 'Manila'") var place: String }
    func call(arguments: Arguments) async throws -> String { await WeatherLookup.forecast(arguments.place) }
}
#endif

// MARK: - SharePlay: bring FaceTime friends into a Mr. BlindBandit call

struct BlindbanditCallActivity: GroupActivity {
    let callID: String
    let title: String
    var metadata: GroupActivityMetadata {
        var m = GroupActivityMetadata()
        m.title = title
        m.subtitle = "Join the call in Mr. BlindBandit"
        m.type = .generic
        return m
    }
}

@MainActor
enum SharePlayCalls {
    /// Offers the current call to the people on FaceTime. Returns a spoken status.
    static func share(callID: String, title: String) async -> String {
        let activity = BlindbanditCallActivity(callID: callID, title: title)
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do { _ = try await activity.activate(); return "Shared with your FaceTime call. They'll get a Join button." }
            catch { return "SharePlay failed: \(error.localizedDescription)" }
        case .activationDisabled: return "Start a FaceTime call first, then share this call with SharePlay."
        case .cancelled: return "SharePlay cancelled."
        @unknown default: return "SharePlay isn't available."
        }
    }

    /// Joins calls shared over SharePlay. Runs for the app's lifetime.
    static func listen(_ comms: ProductionCommunicationsService) async {
        for await session in BlindbanditCallActivity.sessions() {
            session.join()
            let id = session.activity.callID
            UIAccessibility.post(notification: .announcement, argument: "Joining \(session.activity.title) from SharePlay")
            await comms.joinIncomingCall(id: id)
        }
    }
}
