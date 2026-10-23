import AppKit
import CoreLocation

struct WeatherConditions: Equatable {
    let temperature: Double
    let high: Double
    let low: Double
    let code: Int
    let isDay: Bool

    var symbolName: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var summary: String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorms"
        default: return "—"
        }
    }
}

/// Current conditions for the user's approximate location, from Open-Meteo (free, no API key).
final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Access { case notDetermined, granted, denied }

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var conditions: WeatherConditions?
    @Published private(set) var place: String?
    @Published private(set) var failed = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastFetch: Date?
    private let refreshInterval: TimeInterval = 30 * 60

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        access = Self.access(for: manager.authorizationStatus)
    }

    private static func access(for status: CLAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        default: return .denied
        }
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshIfNeeded() {
        guard access == .granted else { return }
        if let lastFetch, Date().timeIntervalSince(lastFetch) < refreshInterval, conditions != nil { return }
        lastFetch = Date()
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        access = Self.access(for: manager.authorizationStatus)
        refreshIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        fetch(for: location)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async { self?.place = placemarks?.first?.locality ?? placemarks?.first?.name }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        failed = conditions == nil
        lastFetch = nil
    }

    // MARK: - Open-Meteo

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }

    private func fetch(for location: CLLocation) {
        // Two decimals (~1 km) is plenty for a forecast and avoids sending a precise position.
        let latitude = String(format: "%.2f", location.coordinate.latitude)
        let longitude = String(format: "%.2f", location.coordinate.longitude)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: latitude),
            URLQueryItem(name: "longitude", value: longitude),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius"),
        ]
        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let response = data.flatMap { try? JSONDecoder().decode(Response.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let response, let high = response.daily.temperature_2m_max.first,
                      let low = response.daily.temperature_2m_min.first else {
                    self.failed = self.conditions == nil
                    self.lastFetch = nil
                    return
                }
                self.failed = false
                self.conditions = WeatherConditions(temperature: response.current.temperature_2m, high: high, low: low,
                                                    code: response.current.weather_code, isDay: response.current.is_day == 1)
            }
        }.resume()
    }

    #if DEBUG
    func loadPreviewWeather() {
        access = .granted
        place = "Accra"
        conditions = WeatherConditions(temperature: 29, high: 31, low: 24, code: 2, isDay: true)
    }
    #endif
}
