import Foundation
import CryptoKit

/// Private EcoFlow app API + MQTT latestQuotas for DELTA 3 1500.
/// Prefer CocoaMQTT / MQTTNIO in the real app target; this file documents the
/// protocol and includes HTTP login helpers shared by app + widget bridge mode.
public enum EcoFlowRegion: String, CaseIterable, Identifiable, Sendable {
    case global, eu, asia

    public var id: String { rawValue }

    public var host: String {
        switch self {
        case .global: return "api.ecoflow.com"
        case .eu: return "api-e.ecoflow.com"
        case .asia: return "api-a.ecoflow.com"
        }
    }

    public var title: String {
        switch self {
        case .global: return "Global"
        case .eu: return "EU"
        case .asia: return "Asia"
        }
    }
}

public struct EcoFlowMQTTCredentials: Sendable {
    public let userId: String
    public let token: String
    public let broker: String
    public let port: Int
    public let username: String
    public let password: String
    public let clientId: String
}

public enum EcoFlowClientError: LocalizedError {
    case badResponse(String)
    case missingField(String)
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .badResponse(let message): return message
        case .missingField(let field): return "Missing field: \(field)"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        }
    }
}

public struct EcoFlowAuthClient: Sendable {
    public init() {}

    public func login(email: String, password: String, region: EcoFlowRegion) async throws -> EcoFlowMQTTCredentials {
        let loginURL = URL(string: "https://\(region.host)/auth/login")!
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en_US", forHTTPHeaderField: "lang")

        let passwordB64 = Data(password.utf8).base64EncodedString()
        let body: [String: String] = [
            "email": email,
            "password": passwordB64,
            "scene": "IOT_APP",
            "userType": "ECOFLOW",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfNeeded(data: data, response: response)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let payload = json?["data"] as? [String: Any],
            let token = payload["token"] as? String,
            let user = payload["user"] as? [String: Any],
            let userIdValue = user["userId"]
        else {
            throw EcoFlowClientError.missingField("token/userId")
        }
        let userId = String(describing: userIdValue)

        let certURL = URL(string: "https://\(region.host)/iot-auth/app/certification")!
        var certRequest = URLRequest(url: certURL)
        certRequest.httpMethod = "GET"
        certRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        certRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        certRequest.setValue("en_US", forHTTPHeaderField: "lang")
        certRequest.httpBody = "userId=\(userId)".data(using: .utf8)

        let (certData, certResponse) = try await URLSession.shared.data(for: certRequest)
        try Self.throwIfNeeded(data: certData, response: certResponse)
        let certJSON = try JSONSerialization.jsonObject(with: certData) as? [String: Any]
        guard let cert = certJSON?["data"] as? [String: Any] else {
            throw EcoFlowClientError.missingField("certification.data")
        }

        let digest = SHA256.hash(data: Data(userId.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(16).uppercased()
        let clientId = "ANDROID_\(hex)_\(userId)"

        return EcoFlowMQTTCredentials(
            userId: userId,
            token: token,
            broker: cert["url"] as? String ?? "mqtt.ecoflow.com",
            port: Int("\(cert["port"] ?? 8883)") ?? 8883,
            username: cert["certificateAccount"] as? String ?? "",
            password: cert["certificatePassword"] as? String ?? "",
            clientId: clientId
        )
    }

    public static func latestQuotasPayload() -> [String: Any] {
        [
            "from": "EcoFlowDeltaWidget",
            "id": String(999900000 + Int.random(in: 10000...99999)),
            "version": "1.1",
            "moduleType": 0,
            "operateType": "latestQuotas",
            "params": [:] as [String: Any],
        ]
    }

    public static func topics(userId: String, sn: String) -> (property: String, get: String, getReply: String, status: String) {
        (
            property: "/app/device/property/\(sn)",
            get: "/app/\(userId)/\(sn)/thing/property/get",
            getReply: "/app/\(userId)/\(sn)/thing/property/get_reply",
            status: "/app/device/status/\(sn)"
        )
    }

    public static func parseDelta31500(sn: String, quota: [String: Any], online: Bool) -> StationStatus {
        func pick(_ keys: String...) -> Any? {
            for key in keys where quota[key] != nil { return quota[key] }
            return nil
        }
        func asInt(_ value: Any?) -> Int? {
            if let i = value as? Int { return i }
            if let d = value as? Double { return Int(d.rounded()) }
            if let s = value as? String { return Int(s) }
            return nil
        }
        func asDouble(_ value: Any?) -> Double? {
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            if let s = value as? String { return Double(s) }
            return nil
        }

        let stateCode = asInt(pick("bms_emsStatus.sysChgDsgState", "bms_emsStatus.chgState"))
        let state: String?
        switch stateCode {
        case 0: state = "discharging"
        case 1: state = "idle"
        case 2: state = "charging"
        default: state = nil
        }

        var remain = asInt(pick("pd.remainTime"))
        if state == "charging" {
            remain = asInt(pick("bms_emsStatus.chgRemainTime", "pd.remainTime"))
        } else if state == "discharging" {
            remain = asInt(pick("bms_emsStatus.dsgRemainTime", "pd.remainTime"))
        }
        if let remain, remain >= 9999 { remain = nil }

        return StationStatus(
            sn: sn,
            online: online,
            soc: asInt(pick("bms_emsStatus.lcdShowSoc", "bms_bmsStatus.soc", "pd.soc")),
            inputW: asInt(pick("pd.wattsInSum")),
            outputW: asInt(pick("pd.wattsOutSum")),
            solarW: asInt(pick("mppt.inWatts")),
            acOutW: asInt(pick("inv.outputWatts")),
            acInW: asInt(pick("inv.inputWatts")),
            state: state,
            remainMin: remain,
            tempC: asDouble(pick("bms_bmsStatus.temp")),
            cycles: asInt(pick("bms_bmsStatus.cycles")),
            updatedAt: Date()
        )
    }

    private static func throwIfNeeded(data: Data, response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(code) {
            throw EcoFlowClientError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = "\(json["message"] ?? "")".lowercased()
            let apiCode = "\(json["code"] ?? "")"
            if message != "success" && apiCode != "0" && apiCode != "200" {
                throw EcoFlowClientError.badResponse(String(data: data, encoding: .utf8) ?? "API error")
            }
        }
    }
}
