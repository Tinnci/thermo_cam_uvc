import Foundation

extension CaptureSessionController {
    func refreshUSBTopology() {
        let captureRunning = isRunning

        sessionQueue.async { [weak self, captureRunning] in
            guard let self else {
                return
            }

            let topology = self.usbTopologyProbe.probeHikvisionDevice()
            let interpretation = self.privateControlPolicy.interpret(topology: topology)
            let capability = self.privateControlPolicy.decide(
                interpretation: interpretation,
                isAVFoundationRunning: captureRunning
            )
            let plan = self.privateControlExecutor.makeReadOnlyProbePlan(
                capability: capability,
                isAVFoundationRunning: captureRunning
            )

            DispatchQueue.main.async { [weak self, topology, interpretation, capability, plan] in
                self?.usbTopology = topology
                self?.usbInterpretation = interpretation
                self?.privateControlCapability = capability
                self?.privateControlPlan = plan.state == .blockedByCapture ? plan : .inactive
            }
        }
    }

    @MainActor
    func enterPrivateControlMode() {
        if isRunning {
            shouldEnterPrivateControlAfterStop = true
            privateControlPlan = privateControlExecutor.makeReadOnlyProbePlan(
                capability: privateControlCapability,
                isAVFoundationRunning: true
            )
            stop()
            return
        }

        beginPrivateControlReadOnlyProbe()
    }

    @MainActor
    func beginPrivateControlReadOnlyProbe() {
        let topology = usbTopologyProbe.probeHikvisionDevice()
        let interpretation = privateControlPolicy.interpret(topology: topology)
        let capability = privateControlPolicy.decide(
            interpretation: interpretation,
            isAVFoundationRunning: false
        )
        let plan = privateControlExecutor.makeReadOnlyProbePlan(
            capability: capability,
            isAVFoundationRunning: false
        )

        usbTopology = topology
        usbInterpretation = interpretation
        privateControlCapability = capability
        privateControlPlan = plan
        statusMessage = plan.title
    }
}
