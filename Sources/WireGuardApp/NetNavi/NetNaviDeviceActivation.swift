import Foundation

// MARK: - Top Level Response
struct ActivationResponse: Codable {
    let error: String
    let data: ActivationData?
}

// MARK: - Data Object
struct ActivationData: Codable {
    let deviceJid: String
    let deviceJidpwd: String
    let deviceToken: String
    let serverIp: String
    let serverPort: String
    let serverProtocol: String
    let tunnelGw: String
    let country: String
    let trialStart: Int64
    let trialEnd: Int64
    let deviceStatus: Int
    let pops: [String: PopInfo]

    // These keys must match the keys INSIDE the "data" dictionary of your JSON
    enum CodingKeys: String, CodingKey {
        case deviceJid = "device_jid"
        case deviceJidpwd = "device_jidpwd"
        case deviceToken = "device_token"
        case serverIp = "server_ip"
        case serverPort = "server_port"
        case serverProtocol = "server_protocol"
        case tunnelGw = "tunnel_gw"
        case country
        case trialStart = "trial_start"
        case trialEnd = "trial_end"
        case deviceStatus = "device_status"
        case pops
    }
}

// MARK: - POP Details
struct PopInfo: Codable {
    let popId: String
    let popName: String
    let popPublicIp: String
    let popWgPort: String
    let publicKey: String
    let popLocation: String
    let countryCode: String
    let usage: String

    enum CodingKeys: String, CodingKey {
        case popId, popName, popPublicIp, popWgPort, publicKey, popLocation, countryCode, usage
    }
}
