import XCTest

import redisTests

var tests = [XCTestCaseEntry]()
tests += redisTests.allTests()
XCTMain(tests)