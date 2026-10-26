import Testing
@testable import VFlowCore

@Suite struct VFlowHomeTests {
    @Test func defaultsToDotVflowUnderHome() {
        #expect(VFlowHome.resolve(environment: [:], home: "/Users/u") == "/Users/u/.vflow")
    }

    @Test func envOverrideIsUsedVerbatimNotNestedUnderHome() {
        #expect(VFlowHome.resolve(environment: ["VFLOW_HOME": "/tmp/vflow-m4a-home"], home: "/Users/u")
                == "/tmp/vflow-m4a-home")
    }

    @Test func envOverrideExpandsTilde() {
        #expect(VFlowHome.resolve(environment: ["VFLOW_HOME": "~/alt-vflow"], home: "/Users/u")
                == "/Users/u/alt-vflow")
    }

    @Test func emptyEnvValueFallsBackToDefault() {
        #expect(VFlowHome.resolve(environment: ["VFLOW_HOME": ""], home: "/Users/u") == "/Users/u/.vflow")
    }
}
