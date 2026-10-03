import Carbon
import Foundation
import os

@MainActor
final class HotKeyManager {
    enum Action: Equatable {
        case activate
        case preset(UUID)
    }

    private struct Registration {
        let reference: EventHotKeyRef
        var action: Action
        let id: UInt32
    }

    private var registrations: [HotKey: Registration] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private let signature: OSType = 0x564E4453
    private let logger = Logger(subsystem: "com.local.vindustilpasser", category: "hotkeys")
    var onAction: ((Action) -> Void)?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { manager.handle(event) }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if result != noErr { logger.error("Cannot install Carbon hotkey handler: \(result)") }
    }

    deinit {
        for registration in registrations.values { UnregisterEventHotKey(registration.reference) }
        if let handler { RemoveEventHandler(handler) }
    }

    func apply(settings: AppSettings) throws {
        try settings.validate()
        var desired: [HotKey: Action] = [settings.general.activationHotKey: .activate]
        for preset in settings.presets where preset.scope == .global {
            if let hotKey = preset.hotKey { desired[hotKey] = .preset(preset.id) }
        }
        var staged: [HotKey: Registration] = [:]
        do {
            for (key, action) in desired where registrations[key] == nil {
                var reference: EventHotKeyRef?
                let id = nextID
                nextID += 1
                let status = RegisterEventHotKey(key.keyCode, key.modifiers.carbon,
                                                 EventHotKeyID(signature: signature, id: id),
                                                 GetApplicationEventTarget(), 0, &reference)
                guard status == noErr, let reference else {
                    logger.error("Registration failed for \(key.label): \(status)")
                    throw HotKeyError.registrationFailed(key.label)
                }
                staged[key] = Registration(reference: reference, action: action, id: id)
            }
        } catch {
            for registration in staged.values { UnregisterEventHotKey(registration.reference) }
            throw error
        }
        for (key, registration) in registrations where desired[key] == nil {
            UnregisterEventHotKey(registration.reference)
        }
        registrations = registrations.filter { desired[$0.key] != nil }
        for (key, registration) in staged { registrations[key] = registration }
        for (key, action) in desired { registrations[key]?.action = action }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                       nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr, hotKeyID.signature == signature,
              let registration = registrations.values.first(where: { $0.id == hotKeyID.id }) else {
            return OSStatus(eventNotHandledErr)
        }
        onAction?(registration.action)
        return noErr
    }
}

enum HotKeyError: LocalizedError {
    case registrationFailed(String)
    var errorDescription: String? {
        switch self { case .registrationFailed(let label): "Could not register \(label). It may already be in use." }
    }
}
