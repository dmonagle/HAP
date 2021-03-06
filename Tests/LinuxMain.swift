@testable import HAPTests
import XCTest

XCTMain([
    testCase(AccessoriesTests.allTests),
    testCase(DeviceTests.allTests),
    testCase(EndpointTests.allTests),
    testCase(PairingsEndpointTests.allTests),
    testCase(PairSetupControllerTests.allTests),
    testCase(PairVerifyControllerTests.allTests),
    testCase(TLV8Tests.allTests)
])
