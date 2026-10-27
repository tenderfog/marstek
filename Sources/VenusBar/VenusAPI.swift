import Foundation
import CoreFoundation
import Darwin

/// Standalone local UDP API. Each operation owns its socket until completion.
/// Cancellation is terminal for this instance, including a worker not yet started;
/// create a fresh instance for the next job. It never closes another thread's fd.
/// Call off the main thread.
/// An accepted setting or mode readback is not proof of physical power flow.
final class VenusAPI: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var cancelled = false
    private var busy = false

    init() {}

    func cancel() {
        lock.lock(); cancelled = true; generation &+= 1; lock.unlock()
    }

    func read(ip: String, port: Int) throws -> Data {
        try operation { token in
            try Self.validate(ip: ip, port: port)
            let wire = try Wire(localIP: "0.0.0.0", port: port, check: { try self.check(token) })
            defer { wire.close() }
            let (reply, identifiedAt) = try wire.query(ip: ip, port: port, method: "Marstek.GetDevice", params: ["ble_mac": "0"])
            let device = try Self.identity(reply, ip: ip, port: port)
            guard let model = device["name"] as? String, Self.e3Names.contains(model) || Self.aNames.contains(model) else {
                throw APIError("unsupported_device", VL("Підтримуються Venus E3 та Venus A з локальним Open API.", "Venus E3 and Venus A with local Open API are supported."))
            }
            var methods = ["ES.GetStatus", "Bat.GetStatus", "ES.GetMode"]
            if device["supports_pv"] as? Bool == true { methods.append("PV.GetStatus") }
            methods.append(contentsOf: ["EM.GetStatus", "Wifi.GetStatus", "BLE.GetStatus"])
            var samples: [(String, [String: Any], String)] = []
            var errors: [[String: Any]] = []
            var components = ["Marstek.GetDevice": "received"]
            var componentClocks = ["Marstek.GetDevice": identifiedAt]
            for method in methods {
                do {
                    let (frame, received) = try wire.query(ip: ip, port: port, method: method, params: ["id": 0])
                    samples.append((method, frame["result"] as! [String: Any], received))
                    components[method] = "received"; componentClocks[method] = received
                } catch is CancellationError { throw CancellationError() }
                catch {
                    errors.append(Self.failureItem(error, method: method))
                    components[method] = (error as? APIError)?.code ?? "network_unavailable"
                }
            }
            var normalized = Self.normalize(samples)
            errors.append(contentsOf: normalized.errors)
            guard !normalized.values.isEmpty else {
                throw APIError("no_data", VL("Marstek не повернув підтримуваних показників батареї чи потужності.", "Marstek returned no supported battery or power readings."))
            }
            normalized.values["schema_version"] = 1
            normalized.values["observed_at"] = normalized.clocks.values.min()!
            normalized.values["metric_observed_at"] = normalized.clocks
            normalized.values["component_status"] = components
            normalized.values["component_observed_at"] = componentClocks
            return ["ok": true, "status": "read", "device": device, "report": normalized.values, "errors": errors]
        }
    }

    func discover(port: Int) throws -> Data {
        try operation { token in
            try Self.validatePort(port)
            let interfaces = try Self.interfaces()
            var devices: [String: [String: Any]] = [:]
            var errors: [[String: Any]] = []
            for interface in interfaces {
                if devices.count >= 16 { break }
                try self.check(token)
                do {
                    let wire = try Wire(localIP: interface.ip, port: port, broadcast: true,
                                        check: { try self.check(token) })
                    defer { wire.close() }
                    // Finish the collection window so other stations can respond;
                    // repeat only when this interface returned no valid identities.
                    for _ in 0..<3 {
                        try self.check(token)
                        var responded = false
                        let requestID = try wire.send(method: "Marstek.GetDevice", params: ["ble_mac": "0"],
                                                      ip: interface.broadcast, port: port)
                        let deadline = Self.now + 2
                        for _ in 0..<64 {
                            guard devices.count < 16, let packet = try wire.receive(until: deadline) else { break }
                            guard packet.port == port, let address = Self.ipv4(packet.ip),
                                  address & interface.mask == interface.network,
                                  address != interface.network, address != interface.broadcastNumber else { continue }
                            do {
                                if let reply = try Self.response(packet.data, requestID: requestID, method: "Marstek.GetDevice", source: nil) {
                                    devices[packet.ip] = try Self.identity(reply, ip: packet.ip, port: port)
                                    responded = true
                                }
                            } catch { continue }
                        }
                        if responded || devices.count >= 16 { break }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { errors.append(Self.failureItem(error, method: "Marstek.GetDevice")) }
            }
            if devices.isEmpty, errors.count == interfaces.count, let first = errors.first {
                throw APIError(first["code"] as? String ?? "network_unavailable", first["message"] as? String ?? VL("Пошук Marstek недоступний.", "Marstek discovery is unavailable."))
            }
            return ["ok": true, "status": "discovered", "devices": devices.keys.sorted().compactMap { devices[$0] }, "errors": errors]
        }
    }

    func command(_ input: [String: Any]) throws -> Data {
        var sent = false
        return try operation(commandSent: { sent }) { token in
            let plan = try Self.commandPlan(input)
            let wire = try Wire(localIP: "0.0.0.0", port: plan.port, check: { try self.check(token) })
            defer { wire.close() }
            let (reply, _) = try wire.query(ip: plan.ip, port: plan.port, method: "Marstek.GetDevice", params: ["ble_mac": "0"])
            let device = try Self.identity(reply, ip: plan.ip, port: plan.port)
            try Self.authorize(plan, device: device)
            // Mark before sendto: a failed/ambiguous write is never automatically retried.
            let (ack, _) = try wire.query(ip: plan.ip, port: plan.port, method: plan.method, params: plan.params,
                                         willSend: { sent = true })
            guard let acknowledgement = ack["result"] as? [String: Any], Self.boolean(acknowledgement["set_result"]) == true else {
                throw APIError("not_accepted", VL("Marstek не підтвердив прийняття команди.", "Marstek did not confirm command acceptance."))
            }
            var result: [String: Any] = ["ok": true, "status": "accepted", "accepted": true,
                                         "verified": false, "method": plan.method, "device": device]
            var warnings: [[String: String]] = []
            if let requested = plan.mode {
                do {
                    let (reply, received) = try wire.query(ip: plan.ip, port: plan.port, method: "ES.GetMode", params: ["id": 0])
                    let raw = (reply["result"] as? [String: Any])?["mode"] as? String
                    if let mode = raw.flatMap(Self.normalizedMode) {
                        result["observed_state"] = ["mode": mode, "observed_at": received]
                        // GetMode has no Passive setpoint/countdown or schedule contents.
                        result["verified"] = plan.action == "set_mode" && mode == requested
                    }
                    if result["verified"] as? Bool != true {
                        warnings.append(["code": "state_unconfirmed", "message": plan.action == "set_mode" ? VL("Команду прийнято, але новий режим ще не підтверджено читанням.", "Command accepted, but a readback has not confirmed the new mode.") : VL("API читає режим, але не підтверджує записані параметри Passive або розкладу.", "The API reads the mode but does not confirm written Passive or schedule parameters.")])
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    warnings.append(["code": "readback_unavailable", "message": VL("Команду прийнято; повторне читання режиму недоступне.", "Command accepted; mode readback is unavailable.")])
                }
            } else {
                warnings.append(["code": "no_documented_readback", "message": VL("Команду прийнято API; документованого читання цього налаштування немає.", "Command accepted by the API; no readback is documented for this setting.")])
            }
            result["warnings"] = warnings
            return result
        }
    }

    private struct APIError: Error, LocalizedError {
        let code: String
        let message: String
        init(_ code: String, _ message: String) { self.code = code; self.message = message }
        var errorDescription: String? { message }
    }

    private func check(_ token: UInt64) throws {
        lock.lock(); let shouldCancel = cancelled || generation != token; lock.unlock()
        if shouldCancel { throw CancellationError() }
    }

    private func operation(commandSent: (() -> Bool)? = nil, _ body: (UInt64) throws -> [String: Any]) throws -> Data {
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        guard !busy else { lock.unlock(); throw APIError("busy", VL("Попередній запит Marstek ще завершується.", "The previous Marstek request is still finishing.")) }
        busy = true
        let token = generation
        lock.unlock()
        defer { lock.lock(); busy = false; lock.unlock() }
        do {
            let value = try body(token)
            try check(token)
            return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        } catch is CancellationError { throw CancellationError() }
        catch {
            let item = Self.failureItem(error)
            let sent = commandSent?() ?? false
            var failure: [String: Any] = ["ok": false, "status": sent ? "unconfirmed" : "error", "error": item]
            if commandSent != nil {
                failure["accepted"] = false; failure["verified"] = false; failure["command_sent"] = sent
                if sent { failure["error"] = ["code": item["code"]!, "message": VL("Команду надіслано, але результат не підтверджено. Перевір стан перед повторенням.", "Command sent, but its result is unconfirmed. Check the station before retrying.")] }
            } else { failure["errors"] = [] as [String] }
            return try JSONSerialization.data(withJSONObject: failure, options: [.sortedKeys])
        }
    }

    private static func failureItem(_ error: Error, method: String? = nil) -> [String: Any] {
        let known = error as? APIError
        var result: [String: Any] = ["code": known?.code ?? "network_unavailable",
                                     "message": known?.message ?? VL("Не вдалося виконати локальний запит Marstek.", "Could not complete the local Marstek request.")]
        if let method { result["method"] = method }
        return result
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // Only these documented, side-effect-free reads may retry a timeout. Never
    // classify by a suffix/prefix: a future setting must remain single-send.
    private static let retryableReads: Set<String> = ["Marstek.GetDevice", "ES.GetStatus", "Bat.GetStatus", "ES.GetMode",
                                                     "EM.GetStatus", "Wifi.GetStatus", "BLE.GetStatus", "PV.GetStatus"]

    private static func attemptLimit(method: String, isWrite: Bool) -> Int {
        !isWrite && retryableReads.contains(method) ? 2 : 1
    }

    private static func withReadRetry<T>(method: String, isWrite: Bool, check: () throws -> Void,
                                         attempt: () throws -> T) throws -> T {
        let limit = attemptLimit(method: method, isWrite: isWrite)
        for index in 0..<limit {
            try check()
            do { return try attempt() }
            catch let error as APIError {
                guard error.code == "timeout", index + 1 < limit else { throw error }
            }
        }
        throw APIError("timeout", VL("Marstek не відповів за відведений час.", "Marstek did not respond within the time limit."))
    }

    private static func uniqueRequestID(candidate: Int, excluding used: Set<Int>) throws -> Int {
        guard (1...65535).contains(candidate), used.count < 65535 else {
            throw APIError("request_id_unavailable", VL("Неможливо створити унікальний ідентифікатор запиту.", "Could not create a unique request identifier."))
        }
        var result = candidate
        while used.contains(result) { result = result == 65535 ? 1 : result + 1 }
        return result
    }
    private static func timestamp() -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: Date())
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              "cCsSiIlLqQ".contains(String(cString: number.objCType)) else { return nil }
        return Int(number.stringValue)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func finite(_ value: Any?, low: Double, high: Double, numericString: Bool = false) -> Double? {
        var result: Double?
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { result = number.doubleValue }
        else if numericString, let string = value as? String,
                string.range(of: #"^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil { result = Double(string) }
        guard let result, result.isFinite, result >= low, result <= high else { return nil }
        return result
    }

    private static func ascii(_ value: Any?, limit: Int = 128) -> String? {
        guard let string = value as? String, !string.isEmpty, string.utf8.count <= limit,
              string.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        return string
    }

    private static func displayText(_ value: Any?, limit: Int) -> String? {
        guard let string = value as? String, !string.isEmpty, string.utf8.count <= limit,
              string.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return string
    }

    private static func mac(_ value: Any?) -> String? {
        guard let string = ascii(value, limit: 17),
              string.range(of: #"^(?:[0-9A-Fa-f]{12}|(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})$"#, options: .regularExpression) != nil else { return nil }
        return string
    }

    private static func validTime(_ value: String) -> Bool {
        value.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil
    }

    private static func ipv4(_ string: String) -> UInt32? {
        let components = string.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return nil }
        var address: UInt32 = 0
        for component in components {
            guard !component.isEmpty, component.count == 1 || component.first != "0",
                  component.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let byte = UInt8(component) else { return nil }
            address = (address << 8) | UInt32(byte)
        }
        return address
    }

    private static func privateAddress(_ address: UInt32) -> Bool {
        address >> 24 == 10 || address & 0xfff00000 == 0xac100000 || address & 0xffff0000 == 0xc0a80000
    }

    private static func validatePort(_ port: Int) throws {
        guard (1024...65535).contains(port) else { throw APIError("invalid_configuration", VL("UDP-порт має бути цілим числом від 1024 до 65535.", "UDP port must be an integer from 1024 to 65535.")) }
    }

    private static func validate(ip: String, port: Int) throws {
        try validatePort(port)
        guard let address = ipv4(ip), privateAddress(address) else {
            throw APIError("invalid_configuration", VL("Потрібна явна приватна IPv4-адреса власної LAN.", "Enter an explicit private IPv4 address on your own LAN."))
        }
    }

    private static let aNames: Set<String> = ["VenusA", "Venus A", "VNSA-0"]
    private static let e3Names: Set<String> = ["VenusE3.0", "VenusE 3.0", "Venus E 3.0", "VNSE3-0"]
    private static let modes: Set<String> = ["Auto", "AI", "Manual", "UPS"]

    private static func normalizedMode(_ raw: String) -> String? {
        ["auto": "Auto", "ai": "AI", "manual": "Manual", "passive": "Passive", "ups": "UPS"][raw.lowercased()]
    }

    private static func identity(_ reply: [String: Any], ip: String, port: Int) throws -> [String: Any] {
        guard let result = reply["result"] as? [String: Any], let name = ascii(result["device"], limit: 64),
              result["ip"] == nil || result["ip"] as? String == ip else {
            throw APIError("invalid_identity", VL("Marstek повернув некоректну модель або IP пристрою.", "Marstek returned an invalid device model or IP."))
        }
        var device: [String: Any] = ["name": name, "ip": ip, "port": port, "supports_pv": aNames.contains(name)]
        for key in ["ble_mac", "wifi_mac"] {
            if let value = mac(result[key]) { device[key] = value }
        }
        if let name = displayText(result["wifi_name"], limit: 128) { device["wifi_name"] = name }
        if let raw = result["ver"] {
            guard let version = integer(raw), (0...1_000_000).contains(version) else {
                throw APIError("invalid_identity", VL("Marstek повернув некоректну версію прошивки.", "Marstek returned an invalid firmware version."))
            }
            device["firmware"] = version
        }
        return device
    }

    private static func response(_ data: Data, requestID: Int, method: String, source: String?) throws -> [String: Any]? {
        guard data.count <= 8192, var parser = try? StrictJSON(data), let value = try? parser.parse(),
              let object = value as? [String: Any], integer(object["id"]) == requestID,
              let src = ascii(object["src"]), source == nil || source?.lowercased() == src.lowercased(),
              object["method"] == nil || object["method"] as? String == method else { return nil }
        if let raw = object["error"] {
            guard let error = raw as? [String: Any], let code = integer(error["code"]) else { return nil }
            if code == -32601 { throw APIError("unsupported_method", VL("Прошивка Marstek не підтримує цей запит.", "Marstek firmware does not support this request.")) }
            throw APIError("device_error", VL("Marstek відхилив запит.", "Marstek rejected the request."))
        }
        guard let result = object["result"] as? [String: Any] else { return nil }
        if method != "Marstek.GetDevice" {
            let nullAllowed = ["ES.GetStatus", "ES.GetMode", "EM.GetStatus"].contains(method) && result["id"] is NSNull
            guard integer(result["id"]) == 0 || nullAllowed else { return nil }
        }
        return object
    }

    private struct Plan {
        let ip: String
        let port: Int
        let action: String
        let expected: String?
        let mode: String?
        let power: Int?
        let method: String
        let params: [String: Any]
    }

    private static func commandPlan(_ input: [String: Any]) throws -> Plan {
        guard let ip = input["ip"] as? String,
              let action = input["action"] as? String else { throw APIError("invalid_command", VL("Очікується одна підтримувана команда Marstek.", "One supported Marstek command is required.")) }
        let specific: [String: Set<String>] = ["set_mode": ["mode"], "set_dod": ["value"], "set_led": ["value"],
            "set_bluetooth_advertising": ["value"], "set_power_version": ["value"],
            "set_passive": ["power", "seconds"], "set_schedule": ["slot", "start", "end", "weekmask", "power", "enabled"],
            "factory_reset": ["keep_energy", "confirmed"]]
        guard let fields = specific[action], Set(input.keys).isSubset(of: fields.union(["ip", "port", "action", "expected_device"])) else {
            throw APIError("invalid_command", VL("Команда містить невідомі або зайві параметри.", "The command contains unknown or extra parameters."))
        }
        let port = input["port"] == nil ? 30000 : integer(input["port"])
        guard let port else { throw APIError("invalid_configuration", VL("Некоректний UDP-порт Marstek.", "Invalid Marstek UDP port.")) }
        try validate(ip: ip, port: port)
        let hasExpected = input["expected_device"] != nil && !(input["expected_device"] is NSNull)
        let expected = hasExpected ? ascii(input["expected_device"], limit: 64) : nil
        if hasExpected && expected == nil { throw APIError("invalid_command", VL("Некоректна очікувана модель Marstek.", "Invalid expected Marstek model.")) }
        var method: String
        var params: [String: Any]
        var mode: String?
        var requestedPower: Int?
        if action == "set_mode" {
            guard let requested = input["mode"] as? String, modes.contains(requested), input["value"] == nil else {
                throw APIError("invalid_command", VL("Вибери режим Auto, AI, Manual або UPS.", "Choose Auto, AI, Manual, or UPS mode."))
            }
            mode = requested
            var config: [String: Any] = ["mode": requested]
            if let key = ["Auto": "auto_cfg", "AI": "ai_cfg", "UPS": "ups_cfg"][requested] { config[key] = ["enable": 1] }
            method = "ES.SetMode"; params = ["id": 0, "config": config]
        } else {
            guard input["mode"] == nil else { throw APIError("invalid_command", VL("Параметр режиму не належить цій команді.", "The mode parameter does not belong to this command.")) }
            switch action {
            case "set_passive":
                guard let power = integer(input["power"]), (-2500...2500).contains(power),
                      let seconds = integer(input["seconds"]), (1...86400).contains(seconds) else {
                    throw APIError("invalid_command", VL("Passive: потрібні цілі Вт у межах моделі та від 1 до 86400 секунд.", "Passive requires whole watts within the model limit and 1 to 86400 seconds."))
                }
                // Rev3.1 specifies W and seconds but no polarity or countdown bounds.
                // Signed W is sent unchanged. 24h is an explicit app bound, not a device rating.
                mode = "Passive"; requestedPower = power
                method = "ES.SetMode"; params = ["id": 0, "config": ["mode": "Passive", "passive_cfg": ["power": power, "cd_time": seconds]]]
            case "set_schedule":
                guard let slot = integer(input["slot"]), (0...9).contains(slot),
                      let start = input["start"] as? String, validTime(start),
                      let end = input["end"] as? String, validTime(end),
                      let week = integer(input["weekmask"]), (1...127).contains(week),
                      let power = integer(input["power"]), (-2500...2500).contains(power),
                      let enabled = boolean(input["enabled"]) else {
                    throw APIError("invalid_command", VL("Розклад: слот 0–9, час HH:mm, дні 1–127, цілі Вт і логічний стан.", "Schedule requires slot 0–9, HH:mm times, days 1–127, whole watts, and a Boolean state."))
                }
                mode = "Manual"; requestedPower = power
                // One documented slot OBJECT; never an unverified array or E-mini manual_set.
                let slotData: [String: Any] = ["time_num": slot, "start_time": start, "end_time": end,
                                             "week_set": week, "power": power, "enable": enabled ? 1 : 0]
                method = "ES.SetMode"; params = ["id": 0, "config": ["mode": "Manual", "manual_cfg": slotData]]
            case "factory_reset":
                guard boolean(input["confirmed"]) == true, let keep = boolean(input["keep_energy"]) else {
                    throw APIError("confirmation_required", VL("Скидання потребує явного підтвердження та вибору збереження накопичених даних.", "Reset requires explicit confirmation and a choice about keeping accumulated data."))
                }
                method = "Reset.Factory"; params = ["type": keep ? 2 : 1]
            case "set_dod":
                guard let value = integer(input["value"]), (30...88).contains(value) else { throw APIError("invalid_command", VL("DOD має бути цілим числом від 30 до 88.", "DOD must be an integer from 30 to 88.")) }
                method = "DOD.SET"; params = ["value": value]
            case "set_led", "set_bluetooth_advertising":
                guard let value = boolean(input["value"]) else { throw APIError("invalid_command", VL("Потрібне логічне значення налаштування.", "A Boolean setting value is required.")) }
                if action == "set_led" { method = "Led.Ctrl"; params = ["state": value ? 1 : 0] }
                else { method = "Ble.Adv"; params = ["enable": value ? 0 : 1] }
            case "set_power_version":
                guard let value = integer(input["value"]), [800, 1200, 1500, 2500].contains(value) else { throw APIError("invalid_command", VL("Недокументований ліміт потужності.", "Undocumented power limit.")) }
                method = "Set.Ver"; params = ["version": value]
            default: throw APIError("unsupported_action", VL("Ця команда Marstek не підтримується застосунком.", "This Marstek command is not supported by the app."))
            }
        }
        return Plan(ip: ip, port: port, action: action, expected: expected, mode: mode, power: requestedPower, method: method, params: params)
    }

    private static func authorize(_ plan: Plan, device: [String: Any]) throws {
        let name = device["name"] as? String ?? ""
        guard plan.expected == nil || plan.expected == name else { throw APIError("identity_changed", VL("Модель відповіді не збігається з обраним пристроєм.", "The response model does not match the selected device.")) }
        guard e3Names.contains(name) || aNames.contains(name) else { throw APIError("unsupported_device", VL("Команди доступні лише для Venus E3 та Venus A.", "Commands are available only for Venus E3 and Venus A.")) }
        if ["set_dod", "set_led", "set_bluetooth_advertising", "set_power_version", "factory_reset"].contains(plan.action) {
            guard let firmware = integer(device["firmware"]), firmware >= 150 else { throw APIError("unsupported_feature", VL("Це налаштування потребує прошивки 150 або новішої.", "This setting requires firmware 150 or later.")) }
        }
        if let power = plan.power {
            // Conservative app caps use the highest documented power version for this model.
            // Firmware/local electrical limits can be lower; ACK does not confirm actual W.
            let cap = e3Names.contains(name) ? 2500 : 1500
            guard (-cap...cap).contains(power) else { throw APIError("unsupported_feature", VL("Задана потужність перевищує межу застосунку для цієї моделі.", "The requested power exceeds the app limit for this model.")) }
        }
        if plan.action == "set_power_version" {
            let versions = e3Names.contains(name) ? [800, 2500] : [800, 1200, 1500]
            guard let value = integer(plan.params["version"]), versions.contains(value) else { throw APIError("unsupported_feature", VL("Цей ліміт не підтримується визначеною моделлю Marstek.", "This limit is not supported by the identified Marstek model.")) }
        }
    }

    private struct Normalized {
        var values: [String: Any] = [:]
        var clocks: [String: String] = [:]
        var errors: [[String: Any]] = []
    }

    private struct Field {
        let raw: String, metric: String
        let low: Double, high: Double
        init(_ raw: String, _ metric: String, _ low: Double, _ high: Double) { self.raw = raw; self.metric = metric; self.low = low; self.high = high }
    }

    private static let fields: [String: [Field]] = [
        "ES.GetStatus": [.init("bat_soc", "soc_percent", 0, 100), .init("bat_cap", "battery_rated_wh", 0, 1e7),
                         .init("bat_power", "battery_power_w", -20000, 20000), .init("ongrid_power", "grid_power_w", -20000, 20000),
                         .init("offgrid_power", "offgrid_power_w", -20000, 20000), .init("pv_power", "pv_power_w", 0, 20000),
                         .init("total_grid_input_energy", "grid_input_wh", 0, 1e12), .init("total_grid_output_energy", "grid_output_wh", 0, 1e12),
                         .init("total_load_energy", "load_energy_wh", 0, 1e12), .init("total_pv_energy", "solar_energy_wh", 0, 1e11)],
        "Bat.GetStatus": [.init("soc", "soc_percent", 0, 100), .init("bat_temp", "battery_temperature_c", -273.15, 150),
                          .init("bat_capacity", "battery_remaining_wh", 0, 1e7), .init("rated_capacity", "battery_rated_wh", 0, 1e7)],
        "ES.GetMode": [.init("bat_soc", "soc_percent", 0, 100), .init("ongrid_power", "grid_power_w", -20000, 20000),
                       .init("offgrid_power", "offgrid_power_w", -20000, 20000),
                       .init("a_power", "ct_phase_a_w", -20000, 20000), .init("b_power", "ct_phase_b_w", -20000, 20000),
                       .init("c_power", "ct_phase_c_w", -20000, 20000), .init("total_power", "ct_total_w", -20000, 20000),
                       .init("input_energy", "ct_input_wh", 0, 1e13), .init("output_energy", "ct_output_wh", 0, 1e13)],
        "PV.GetStatus": [.init("pv_power", "pv_power_w", 0, 20000), .init("pv_voltage", "pv_voltage_v", 0, 2000), .init("pv_current", "pv_current_a", 0, 1000)],
        "EM.GetStatus": [.init("a_power", "ct_phase_a_w", -20000, 20000), .init("b_power", "ct_phase_b_w", -20000, 20000),
                         .init("c_power", "ct_phase_c_w", -20000, 20000), .init("total_power", "ct_total_w", -20000, 20000),
                         .init("input_energy", "ct_input_wh", 0, 1e13), .init("output_energy", "ct_output_wh", 0, 1e13)],
        "Wifi.GetStatus": [.init("rssi", "wifi_rssi_dbm", -150, 0)]
    ]

    private static func normalize(_ samples: [(String, [String: Any], String)]) -> Normalized {
        var output = Normalized()
        for (method, result, received) in samples {
            func invalid(_ raw: String) -> [String: Any] {
                ["method": method, "code": "invalid_value", "field": raw, "message": VL("Marstek повернув показник поза підтримуваними межами.", "Marstek returned a reading outside the supported range.")]
            }
            for field in fields[method] ?? [] {
                if method == "ES.GetMode", field.metric.hasPrefix("ct_"),
                   !["Auto", "AI"].contains((result["mode"] as? String).flatMap(normalizedMode) ?? "") { continue }
                guard let raw = result[field.raw], !(raw is NSNull) else { continue }
                guard var value = finite(raw, low: field.low, high: field.high, numericString: method == "Bat.GetStatus" && field.raw == "soc") else {
                    output.errors.append(invalid(field.raw)); continue
                }
                if method == "ES.GetMode", output.values[field.metric] != nil { continue }
                if field.metric == "solar_energy_wh" { value *= 10 }
                if field.metric == "ct_input_wh" || field.metric == "ct_output_wh" { value *= 0.1 }
                output.values[field.metric] = value; output.clocks[field.metric] = received
            }
            if method == "Bat.GetStatus" {
                for (raw, metric) in [("charg_flag", "battery_charge_allowed"), ("dischrg_flag", "battery_discharge_allowed")] {
                    guard let rawValue = result[raw], !(rawValue is NSNull) else { continue }
                    if let value = boolean(rawValue) { output.values[metric] = value; output.clocks[metric] = received }
                    else { output.errors.append(invalid(raw)) }
                }
            } else if method == "ES.GetMode" {
                let mode = (result["mode"] as? String).flatMap(normalizedMode)
                if let mode { output.values["mode"] = mode; output.clocks["mode"] = received }
                else if let raw = result["mode"], !(raw is NSNull) { output.errors.append(invalid("mode")) }
                if mode == "Auto" || mode == "AI", let raw = result["ct_state"], !(raw is NSNull) {
                    if let flag = integer(raw), [0, 1].contains(flag) { output.values["ct_connected"] = flag == 1; output.clocks["ct_connected"] = received }
                    else { output.errors.append(invalid("ct_state")) }
                }
            } else if method == "PV.GetStatus" {
                var channels: [[String: Any]] = []
                for index in 1...4 {
                    var channel: [String: Any] = ["id": index, "observed_at": received]
                    for (suffix, metric, high) in [("power", "power_w", 20000.0), ("voltage", "voltage_v", 2000.0), ("current", "current_a", 1000.0)] {
                        let key = "pv\(index)_\(suffix)"
                        guard let raw = result[key], !(raw is NSNull) else { continue }
                        if let value = finite(raw, low: 0, high: high) { channel[metric] = value }
                        else { output.errors.append(invalid(key)) }
                    }
                    let key = "pv\(index)_state"
                    if let raw = result[key], !(raw is NSNull) {
                        if let flag = integer(raw), [0, 1].contains(flag) { channel["is_working"] = flag == 1 }
                        else { output.errors.append(invalid(key)) }
                    }
                    if channel.count > 2 { channels.append(channel) }
                }
                if !channels.isEmpty { output.values["pv_channels"] = channels; output.clocks["pv_channels"] = received }
                if let raw = result["PV_state"], !(raw is NSNull) {
                    if let flag = integer(raw), [0, 1].contains(flag) { output.values["pv_working"] = flag == 1; output.clocks["pv_working"] = received }
                    else { output.errors.append(invalid("PV_state")) }
                }
            } else if method == "EM.GetStatus" {
                if let raw = result["ct_state"], !(raw is NSNull) {
                    if let flag = integer(raw), [0, 1].contains(flag) { output.values["ct_connected"] = flag == 1; output.clocks["ct_connected"] = received }
                    else { output.errors.append(invalid("ct_state")) }
                }
            } else if method == "Wifi.GetStatus" {
                if let raw = result["ssid"], !(raw is NSNull) {
                    if let name = displayText(raw, limit: 128) { output.values["wifi_ssid"] = name; output.clocks["wifi_ssid"] = received }
                    else { output.errors.append(invalid("ssid")) }
                }
                for (raw, metric) in [("sta_ip", "wifi_ip"), ("sta_gate", "wifi_gateway"), ("sta_mask", "wifi_mask"), ("sta_dns", "wifi_dns")] {
                    guard let value = result[raw], !(value is NSNull) else { continue }
                    if let string = value as? String, ipv4(string) != nil { output.values[metric] = string; output.clocks[metric] = received }
                    else { output.errors.append(invalid(raw)) }
                }
                if let raw = result["wifi_mac"], !(raw is NSNull) {
                    if let value = mac(raw) { output.values["wifi_mac"] = value; output.clocks["wifi_mac"] = received }
                    else { output.errors.append(invalid("wifi_mac")) }
                }
            } else if method == "BLE.GetStatus" {
                if let raw = result["state"], !(raw is NSNull) {
                    if let state = ascii(raw, limit: 64) {
                        output.values["bluetooth_state"] = state; output.clocks["bluetooth_state"] = received
                        if ["connect", "connected", "disconnect", "disconnected"].contains(state.lowercased()) {
                            output.values["bluetooth_connected"] = ["connect", "connected"].contains(state.lowercased())
                            output.clocks["bluetooth_connected"] = received
                        }
                    }
                    else { output.errors.append(invalid("state")) }
                }
                if let raw = result["ble_mac"], !(raw is NSNull) {
                    if let value = mac(raw) { output.values["bluetooth_mac"] = value; output.clocks["bluetooth_mac"] = received }
                    else { output.errors.append(invalid("ble_mac")) }
                }
            }
        }
        return output
    }

    private struct Interface {
        let ip: String, broadcast: String
        let mask: UInt32, network: UInt32, broadcastNumber: UInt32
    }

    private static func ipString(_ address: UInt32) -> String {
        "\((address >> 24) & 255).\((address >> 16) & 255).\((address >> 8) & 255).\(address & 255)"
    }

    private static func interfaces() throws -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { throw APIError("interface_unavailable", VL("Не вдалося прочитати локальні мережеві інтерфейси.", "Could not read local network interfaces.")) }
        defer { freeifaddrs(head) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        var seen = Set<String>()
        var found: [(String, Interface)] = []
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let item = current.pointee
            let flags = item.ifa_flags
            guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_RUNNING) != 0,
                  flags & UInt32(IFF_BROADCAST) != 0, flags & UInt32(IFF_LOOPBACK | IFF_POINTOPOINT) == 0,
                  let raw = item.ifa_addr, Int32(raw.pointee.sa_family) == AF_INET,
                  let rawMask = item.ifa_netmask, Int32(rawMask.pointee.sa_family) == AF_INET,
                  let rawBroadcast = item.ifa_dstaddr, Int32(rawBroadcast.pointee.sa_family) == AF_INET else { continue }
            func address(_ raw: UnsafeMutablePointer<sockaddr>) -> UInt32 {
                raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            }
            let ip = address(raw), mask = address(rawMask), broadcast = address(rawBroadcast)
            let inverted = ~mask, network = ip & mask
            guard privateAddress(ip), mask.nonzeroBitCount <= 30, inverted != UInt32.max,
                  inverted & (inverted &+ 1) == 0, broadcast == network | inverted,
                  privateAddress(network), privateAddress(broadcast), seen.insert("\(network)/\(mask)").inserted else { continue }
            found.append((String(cString: item.ifa_name), Interface(ip: ipString(ip), broadcast: ipString(broadcast), mask: mask, network: network, broadcastNumber: broadcast)))
        }
        guard !found.isEmpty else { throw APIError("interface_unavailable", VL("Немає активної приватної LAN із підтвердженим broadcast.", "No active private LAN with a verified broadcast address.")) }
        return found.sorted { $0.0 < $1.0 }.prefix(4).map(\.1)
    }

    private final class Wire {
        let descriptor: Int32
        let check: () throws -> Void
        private var source: String?
        private var lastSend: TimeInterval?
        private var usedRequestIDs = Set<Int>()

        init(localIP: String, port: Int, broadcast: Bool = false, check: @escaping () throws -> Void) throws {
            self.check = check
            try check()
            let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { throw Self.networkError() }
            do {
                let flags = fcntl(fd, F_GETFL, 0)
                guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw Self.networkError() }
                if broadcast {
                    var enabled: Int32 = 1
                    guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled))) == 0 else { throw Self.networkError() }
                }
                var local = Self.address(ip: localIP, port: port)
                let bound = withUnsafePointer(to: &local) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
                guard bound == 0 else {
                    if errno == EADDRINUSE { throw APIError("port_in_use", VL("UDP-порт Marstek уже зайнятий іншим читанням або застосунком.", "Another reader or app is already using the Marstek UDP port.")) }
                    throw Self.networkError()
                }
            } catch { Darwin.close(fd); throw error }
            descriptor = fd
        }

        func close() { Darwin.close(descriptor) }

        private static func networkError() -> APIError {
            if errno == EACCES || errno == EPERM { return APIError("permission_denied", VL("macOS не дозволила доступ до локальної мережі.", "macOS denied local network access.")) }
            return APIError("network_unavailable", VL("Не вдалося виконати локальний запит Marstek.", "Could not complete the local Marstek request."))
        }

        private static func address(ip: String, port: Int) -> sockaddr_in {
            var value = sockaddr_in()
            value.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            value.sin_family = sa_family_t(AF_INET)
            value.sin_port = UInt16(port).bigEndian
            _ = ip.withCString { inet_pton(AF_INET, $0, &value.sin_addr) }
            return value
        }

        func send(method: String, params: [String: Any], ip: String, port: Int, willSend: (() -> Void)? = nil) throws -> Int {
            if let lastSend {
                while VenusAPI.now - lastSend < 1 {
                    try check()
                    Thread.sleep(forTimeInterval: max(0, min(0.1, 1 - (VenusAPI.now - lastSend))))
                }
            }
            try check()
            let requestID = try VenusAPI.uniqueRequestID(candidate: Int.random(in: 1...65535), excluding: usedRequestIDs)
            usedRequestIDs.insert(requestID)
            let data = try JSONSerialization.data(withJSONObject: ["id": requestID, "method": method, "params": params])
            var destination = Self.address(ip: ip, port: port)
            willSend?()
            lastSend = VenusAPI.now
            let sent = data.withUnsafeBytes { bytes in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.sendto(descriptor, bytes.baseAddress!, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent == data.count else { throw Self.networkError() }
            return requestID
        }

        struct Packet { let data: Data, ip: String; let port: Int }

        func receive(until deadline: TimeInterval) throws -> Packet? {
            while VenusAPI.now < deadline {
                try check()
                var item = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let result = Darwin.poll(&item, 1, Int32(max(1, min(100, (deadline - VenusAPI.now) * 1000))))
                if result < 0 { if errno == EINTR { continue }; throw Self.networkError() }
                if result == 0 { continue }
                if item.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { throw Self.networkError() }
                var peer = sockaddr_in(), length = socklen_t(MemoryLayout<sockaddr_in>.size)
                var bytes = [UInt8](repeating: 0, count: 8193)
                let count = bytes.withUnsafeMutableBytes { buffer in
                    withUnsafeMutablePointer(to: &peer) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            Darwin.recvfrom(descriptor, buffer.baseAddress!, buffer.count, MSG_DONTWAIT, $0, &length)
                        }
                    }
                }
                if count < 0 { if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }; throw Self.networkError() }
                guard peer.sin_family == sa_family_t(AF_INET) else { continue }
                return Packet(data: Data(bytes.prefix(count)), ip: VenusAPI.ipString(UInt32(bigEndian: peer.sin_addr.s_addr)), port: Int(UInt16(bigEndian: peer.sin_port)))
            }
            try check()
            return nil
        }

        func query(ip: String, port: Int, method: String, params: [String: Any], willSend: (() -> Void)? = nil) throws -> ([String: Any], String) {
            try VenusAPI.withReadRetry(method: method, isWrite: willSend != nil, check: check) {
                try self.queryOnce(ip: ip, port: port, method: method, params: params, willSend: willSend)
            }
        }

        private func queryOnce(ip: String, port: Int, method: String, params: [String: Any], willSend: (() -> Void)?) throws -> ([String: Any], String) {
            let requestID = try send(method: method, params: params, ip: ip, port: port, willSend: willSend)
            let deadline = VenusAPI.now + 2
            for _ in 0..<64 {
                guard let packet = try receive(until: deadline) else { break }
                guard packet.ip == ip, packet.port == port else { continue }
                if let reply = try VenusAPI.response(packet.data, requestID: requestID, method: method, source: source) {
                    source = reply["src"] as? String
                    return (reply, VenusAPI.timestamp())
                }
            }
            throw APIError("timeout", VL("Marstek не відповів. Перевір Local API, порт і підключення до тієї самої LAN.", "Marstek did not respond. Check Local API, the port, and connection to the same LAN."))
        }
    }

    /// Small strict parser: Foundation's parser silently accepts duplicate keys.
    /// The wire is capped at 8KB; nesting is also bounded independently.
    private struct StrictJSON {
        let bytes: [UInt8]
        var index = 0
        init(_ data: Data) throws {
            guard data.count <= 8192 else { throw APIError("invalid_json", VL("Некоректна відповідь Marstek.", "Invalid Marstek response.")) }
            bytes = Array(data)
        }
        mutating func parse() throws -> Any {
            let value = try value(depth: 0)
            space()
            guard index == bytes.count else { throw bad() }
            return value
        }
        private func bad() -> APIError { APIError("invalid_json", VL("Некоректна відповідь Marstek.", "Invalid Marstek response.")) }
        private mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        private mutating func consume(_ byte: UInt8) -> Bool {
            space(); guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1; return true
        }
        private mutating func string() throws -> String {
            space(); let start = index
            guard consume(34) else { throw bad() }
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if byte == 92 { guard index < bytes.count else { throw bad() }; index += 1 }
                else if byte == 34 {
                    guard let result = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed]) as? String else { throw bad() }
                    return result
                }
            }
            throw bad()
        }
        private mutating func value(depth: Int) throws -> Any {
            guard depth <= 32 else { throw bad() }
            space(); guard index < bytes.count else { throw bad() }
            if bytes[index] == 34 { return try string() }
            if consume(123) {
                var object: [String: Any] = [:]
                if consume(125) { return object }
                repeat {
                    let key = try string()
                    guard object[key] == nil, consume(58) else { throw bad() }
                    object[key] = try value(depth: depth + 1)
                    if consume(125) { return object }
                } while consume(44)
                throw bad()
            }
            if consume(91) {
                var array: [Any] = []
                if consume(93) { return array }
                repeat {
                    array.append(try value(depth: depth + 1))
                    if consume(93) { return array }
                } while consume(44)
                throw bad()
            }
            for (word, value): (String, Any) in [("true", true), ("false", false), ("null", NSNull())] {
                let literal = Array(word.utf8)
                if bytes[index...].starts(with: literal) { index += literal.count; return value }
            }
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            guard token.range(of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { throw bad() }
            if !token.contains(".") && !token.lowercased().contains("e"), let number = Int(token) { return number }
            guard let number = Double(token), number.isFinite else { throw bad() }
            return number
        }
    }

    /// Pure parser/normalization/permission checks. Never creates a socket.
    static func selfCheck() throws {
        func require(_ condition: @autoclosure () throws -> Bool) throws {
            if try !condition() { throw APIError("selfcheck_failed", VL("Перевірка автономного Venus API не пройшла.", "The offline Venus API self-check failed.")) }
        }
        func rejected(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
        let exactReads = ["Marstek.GetDevice", "ES.GetStatus", "Bat.GetStatus", "ES.GetMode", "EM.GetStatus", "Wifi.GetStatus", "BLE.GetStatus", "PV.GetStatus"]
        for method in exactReads {
            try require(attemptLimit(method: method, isWrite: false) == 2)
            try require(attemptLimit(method: method, isWrite: true) == 1)
            var attempts = 0
            let value: Int = try withReadRetry(method: method, isWrite: false, check: {}) {
                attempts += 1
                if attempts == 1 { throw APIError("timeout", "fixture") }
                return 42
            }
            try require(value == 42 && attempts == 2)
        }
        for method in ["ES.SetMode", "DOD.SET", "Led.Ctrl", "Ble.Adv", "Set.Ver", "Reset.Factory", "Other.GetStatus", "Wifi.GetStatus "] {
            try require(attemptLimit(method: method, isWrite: false) == 1)
            var attempts = 0
            try require(rejected {
                let _: Int = try withReadRetry(method: method, isWrite: false, check: {}) {
                    attempts += 1; throw APIError("timeout", "fixture")
                }
            })
            try require(attempts == 1)
        }
        for code in ["timeout", "unsupported_method", "device_error", "network_unavailable"] {
            var attempts = 0
            try require(rejected {
                let _: Int = try withReadRetry(method: "Marstek.GetDevice", isWrite: false, check: {}) {
                    attempts += 1; throw APIError(code, "fixture")
                }
            })
            try require(attempts == (code == "timeout" ? 2 : 1))
        }
        var cancelledRetryAttempts = 0
        var cancellationStopsRetry = false
        do {
            let _: Int = try withReadRetry(method: "ES.GetStatus", isWrite: false, check: {
                if cancelledRetryAttempts > 0 { throw CancellationError() }
            }) {
                cancelledRetryAttempts += 1; throw APIError("timeout", "fixture")
            }
        } catch is CancellationError { cancellationStopsRetry = true }
        try require(cancellationStopsRetry && cancelledRetryAttempts == 1)
        var ids = Set<Int>()
        for expected in [65535, 1, 2] {
            let id = try uniqueRequestID(candidate: 65535, excluding: ids)
            try require(id == expected && (1...65535).contains(id)); ids.insert(id)
        }
        try require(ids.count == 3)
        try require(integer(true) == nil && integer(1.0) == nil && integer(1) == 1)
        try require(boolean(1) == nil && boolean(false) == false && finite(true, low: 0, high: 1) == nil)
        try validate(ip: "192.168.50.42", port: 30000)
        for ip in ["8.8.8.8", "127.0.0.1", "169.254.1.1", "192.168.050.42", "10.0.0.1.example"] { try require(rejected { try validate(ip: ip, port: 30000) }) }
        try require(rejected { try validate(ip: "10.0.0.1", port: 80) })
        let ack = Data(#"{"id":65535,"src":"VenusE3.0-device","result":{"id":0,"set_result":true}}"#.utf8)
        try require(try response(ack, requestID: 65535, method: "Led.Ctrl", source: "VenusE3.0-device") != nil)
        try require(try response(ack, requestID: 65535, method: "Led.Ctrl", source: "VENUSE3.0-DEVICE") != nil)
        try require(try response(ack, requestID: 65534, method: "Led.Ctrl", source: nil) == nil)
        try require(try response(ack, requestID: 65535, method: "Led.Ctrl", source: "another-device") == nil)
        try require(try response(Data(repeating: 32, count: 8193), requestID: 7, method: "Led.Ctrl", source: nil) == nil)
        for raw in [#"{"id":true,"src":"x","result":{"id":0}}"#, #"{"id":7,"id":7,"src":"x","result":{"id":0}}"#, #"{"id":7,"src":"x","result":{"id":false}}"#, #"{"id":7.0,"src":"x","result":{"id":0}}"#] {
            try require(try response(Data(raw.utf8), requestID: 7, method: "Led.Ctrl", source: nil) == nil)
        }
        let normalized = normalize([("ES.GetStatus", ["bat_cap": 5120, "bat_power": -440, "offgrid_power": 65525, "total_pv_energy": 42], "2026-10-27T00:00:00.000Z"),
                                    ("Bat.GetStatus", ["soc": "41", "rated_capacity": 5000, "bat_capacity": 2050, "charg_flag": true], "2026-10-27T00:00:01.000Z"),
                                    ("ES.GetMode", ["mode": "auto", "ct_state": 1, "bat_soc": 99], "2026-10-27T00:00:02.000Z"),
                                    ("PV.GetStatus", ["pv1_power": 100, "pv4_voltage": 30, "pv4_state": 1], "2026-10-27T00:00:03.000Z")])
        try require(normalized.values["offgrid_power_w"] == nil)
        try require(finite(normalized.values["solar_energy_wh"], low: 0, high: 1000) == 420)
        try require(finite(normalized.values["battery_rated_wh"], low: 0, high: 10000) == 5000)
        try require(finite(normalized.values["battery_remaining_wh"], low: 0, high: 10000) == 2050)
        try require(finite(normalized.values["soc_percent"], low: 0, high: 100) == 41)
        try require((normalized.values["pv_channels"] as? [[String: Any]])?.count == 2)
        try require(normalized.clocks["battery_power_w"] == "2026-10-27T00:00:00.000Z")
        let network = normalize([
            ("Wifi.GetStatus", ["ssid": "Моя мережа", "rssi": -59, "sta_ip": "192.168.50.42", "sta_gate": "192.168.50.1",
                                "sta_mask": "255.255.255.0", "sta_dns": "8.8.8.8", "wifi_mac": "020000000001"], "2026-10-27T00:00:04.000Z"),
            ("BLE.GetStatus", ["state": "connect", "ble_mac": "020000000002"], "2026-10-27T00:00:05.000Z"),
            ("EM.GetStatus", ["ct_state": 1, "a_power": -120, "b_power": 0, "c_power": 5, "total_power": -115,
                              "input_energy": 1234, "output_energy": 50], "2026-10-27T00:00:06.000Z")])
        try require(network.values["wifi_ssid"] as? String == "Моя мережа")
        try require(network.values["wifi_dns"] as? String == "8.8.8.8")
        try require(network.values["wifi_connected"] == nil) // IP is not radio connectivity or mains evidence.
        try require(boolean(network.values["bluetooth_connected"]) == true)
        try require(boolean(network.values["ct_connected"]) == true)
        try require(finite(network.values["ct_input_wh"], low: 0, high: 1000) == 123.4)
        try require(finite(network.values["ct_total_w"], low: -20000, high: 20000) == -115)
        try require(network.clocks["wifi_rssi_dbm"] == "2026-10-27T00:00:04.000Z")
        let invalidNetwork = normalize([
            ("Wifi.GetStatus", ["ssid": "bad\nname", "rssi": false, "sta_ip": "192.168.001.1", "wifi_mac": "not-a-mac"], "old"),
            ("BLE.GetStatus", ["state": "unknown", "ble_mac": NSNull()], "old"),
            ("EM.GetStatus", ["ct_state": true, "a_power": 65525], "old"),
            ("ES.GetMode", ["mode": "Manual", "a_power": 400, "input_energy": 500], "old")])
        try require(invalidNetwork.values["ct_phase_a_w"] == nil && invalidNetwork.values["ct_input_wh"] == nil)
        try require(invalidNetwork.values["ct_connected"] == nil && invalidNetwork.values["bluetooth_connected"] == nil)
        try require(invalidNetwork.values["wifi_ip"] == nil && invalidNetwork.values["wifi_rssi_dbm"] == nil)
        for model in ["VenusE3.0", "VenusA"] {
            let device: [String: Any] = ["name": model, "firmware": 150]
            for action in ["set_dod", "set_led", "set_bluetooth_advertising"] {
                let plan = try commandPlan(["ip": "10.0.0.1", "action": action, "value": action == "set_dod" ? 30 : true])
                try authorize(plan, device: device)
                try require(rejected { try authorize(plan, device: ["name": model, "firmware": 149]) })
            }
            for power in [800, 1200, 1500, 2500] {
                let plan = try commandPlan(["ip": "10.0.0.1", "action": "set_power_version", "value": power])
                let allowed = model == "VenusA" ? [800, 1200, 1500].contains(power) : [800, 2500].contains(power)
                try require(rejected { try authorize(plan, device: device) } != allowed)
            }
        }
        for value in [true, 29, 89, 30.0, "30"] as [Any] { try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "set_dod", "value": value]) }) }
        try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "Reset.Factory"]) })
        try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "set_mode", "mode": "Passive"]) })
        for model in ["VenusE3.0", "VenusA"] {
            let maximum = model == "VenusA" ? 1500 : 2500
            for power in [-maximum, 0, maximum] {
                let passive = try commandPlan(["ip": "10.0.0.1", "action": "set_passive", "power": power, "seconds": 86400])
                try authorize(passive, device: ["name": model, "firmware": 149]) // ES is not a FW150-only SYS feature.
                let config = passive.params["config"] as! [String: Any]
                try require(integer((config["passive_cfg"] as? [String: Any])?["power"]) == power)
                for slot in [0, 9] {
                    let schedule = try commandPlan(["ip": "10.0.0.1", "action": "set_schedule", "slot": slot,
                        "start": "23:00", "end": "06:00", "weekmask": 127, "power": power, "enabled": false])
                    try authorize(schedule, device: ["name": model, "firmware": 149])
                    let config = schedule.params["config"] as! [String: Any]
                    let object = config["manual_cfg"] as? [String: Any]
                    try require(object != nil && integer(object?["time_num"]) == slot && integer(object?["enable"]) == 0)
                    try require(object?["manual_set"] == nil)
                }
            }
            for keep in [true, false] {
                let reset = try commandPlan(["ip": "10.0.0.1", "action": "factory_reset", "keep_energy": keep, "confirmed": true])
                try authorize(reset, device: ["name": model, "firmware": 150])
                try require(reset.method == "Reset.Factory" && integer(reset.params["type"]) == (keep ? 2 : 1))
                try require(rejected { try authorize(reset, device: ["name": model, "firmware": 149]) })
            }
        }
        let excessiveA = try commandPlan(["ip": "10.0.0.1", "action": "set_passive", "power": 1501, "seconds": 1])
        try require(rejected { try authorize(excessiveA, device: ["name": "VenusA", "firmware": 150]) })
        for seconds in [0, 86401, 1.0, true] as [Any] {
            try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "set_passive", "power": 0, "seconds": seconds]) })
        }
        for power in [-2501, 2501, true, 100.0] as [Any] {
            try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "set_passive", "power": power, "seconds": 300]) })
        }
        let validSchedule: [String: Any] = ["ip": "10.0.0.1", "action": "set_schedule", "slot": 0, "start": "00:00", "end": "23:59", "weekmask": 1, "power": 0, "enabled": true]
        for (key, bad): (String, Any) in [("slot", 10), ("slot", true), ("start", "24:00"), ("start", "8:30"), ("end", "12:60"),
                                         ("weekmask", 0), ("weekmask", 128), ("enabled", 1), ("power", 2501)] {
            var invalid = validSchedule; invalid[key] = bad
            try require(rejected { _ = try commandPlan(invalid) })
        }
        for confirmed in [false, 1, "true", NSNull()] as [Any] {
            try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "factory_reset", "keep_energy": true, "confirmed": confirmed]) })
        }
        try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "factory_reset", "confirmed": true]) })
        try require(rejected { _ = try commandPlan(["ip": "10.0.0.1", "action": "set_led", "value": true, "confirmed": true]) })
        let api = VenusAPI()
        api.cancel()
        try require(rejected { try api.check(0) })
        try require(rejected { try api.check(1) })
        var cancelledBodyEntered = false
        do { _ = try api.operation { _ in cancelledBodyEntered = true; return ["ok": true] } }
        catch is CancellationError {}
        try require(!cancelledBodyEntered)
        let activeAPI = VenusAPI()
        var cancellationThrown = false
        do {
            _ = try activeAPI.operation { token in
                activeAPI.cancel(); try activeAPI.check(token)
                return ["ok": true]
            }
        } catch is CancellationError { cancellationThrown = true }
        try require(cancellationThrown)
        let nextAPI = VenusAPI()
        var overlapRejected = false
        _ = try nextAPI.operation { _ in
            do { _ = try nextAPI.operation { _ in ["ok": true] } }
            catch { overlapRejected = true }
            return ["ok": true]
        }
        try require(overlapRejected)
    }
}
