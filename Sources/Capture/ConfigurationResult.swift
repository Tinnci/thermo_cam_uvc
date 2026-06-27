struct ConfigurationResult {
    let deviceID: String
    let formatID: String
    let activeConfiguration: ActiveConfiguration
    let fallbackEvents: [FallbackEvent]
    let controlStates: [CameraControlState]
    let recordingAvailable: Bool
    let requiresNativeBackendOnNoFrames: Bool
}
