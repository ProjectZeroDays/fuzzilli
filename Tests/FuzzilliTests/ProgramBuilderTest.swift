// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import XCTest
@testable import Fuzzilli

class ProgramBuilderTests: XCTestCase {
    // Verify that code generators don't crash and always produce valid programs.
    func testCodeGeneration() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<1000 {
            b.generate(n: 100)
            let program = b.finalize()
            // Add to corpus since generate() does splicing as well
            fuzzer.corpus.add(program)
            
            XCTAssert(program.count >= 100)
            XCTAssert(program.check() == .valid)
        }
    }
    
    func testSplicing1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        // Original
        var i = b.loadInt(42)
        b.doWhileLoop(i, .lessThan, b.loadInt(44)) {
            b.unary(.BitwiseNot, i)
        }
        b.loadFloat(13.37)
        var arr = b.createArray(with: [i, i, i])
        b.loadProperty("length", of: arr)
        b.callMethod("pop", on: arr, withArgs: [])
        let original = b.finalize()
        
        // Expected splice
        i = b.loadInt(42)
        arr = b.createArray(with: [i, i, i])
        b.callMethod("pop", on: arr, withArgs: [])
        let expectedSplice = b.finalize()
        
        // Actual splice
        b.splice(from: original, at: original.lastInstruction.index)
        let actualSplice = b.finalize()
        
        XCTAssertEqual(expectedSplice, actualSplice)
    }
    
    func testSplicing2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        // Original
        var i = b.loadInt(42)
        var f = b.loadFloat(13.37)
        var f2 = b.loadFloat(133.7)
        let o = b.createObject(with: ["f": f])
        b.storeProperty(f2, as: "f", on: o)
        b.whileLoop(i, .lessThan, b.loadInt(100)) {
            b.binary(f, f2, with: .Add)
        }
        b.loadProperty("f", of: o)
        let original = b.finalize()
        
        // Expected splice
        i = b.loadInt(42)
        f = b.loadFloat(13.37)
        f2 = b.loadFloat(133.7)
        b.whileLoop(i, .lessThan, b.loadInt(100)) {
            // If a block is spliced, its entire body is copied as well
            b.binary(f, f2, with: .Add)
        }
        let expectedSplice = b.finalize()
        
        // Actual splice
        let idx = original.lastInstruction.index - 1
        XCTAssert(original[idx].operation is EndWhile)
        b.splice(from: original, at: idx)
        let actualSplice = b.finalize()
        
        XCTAssertEqual(expectedSplice, actualSplice)
    }
    
    func testSplicing3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative      // Aggressive splicing might not include all mutating instructions
        
        // Original
        var f2 = b.phi(b.loadFloat(13.37))
        b.definePlainFunction(withSignature: [.anything] => .unknown) { args in
            let i = b.loadInt(42)
            let f = b.loadFloat(13.37)
            b.copy(b.loadFloat(133.7), to: f2)
            let o = b.createObject(with: ["i": i, "f": f])
            let o2 = b.createObject(with: ["i": i, "f": f2])
            b.binary(i, args[0], with: .Add)
            b.storeProperty(f2, as: "f", on: o)
            let object = b.loadBuiltin("Object")
            let descriptor = b.createObject(with: ["value": b.loadString("foobar")])
            b.callMethod("defineProperty", on: object, withArgs: [o, b.loadString("s"), descriptor])
            b.callMethod("defineProperty", on: object, withArgs: [o2, b.loadString("s"), descriptor])
            let json = b.loadBuiltin("JSON")
            b.callMethod("stringify", on: json, withArgs: [o])
        }
        let original = b.finalize()
        
        // Expected splice
        f2 = b.phi(b.loadFloat(13.37))
        let i = b.loadInt(42)
        let f = b.loadFloat(13.37)
        b.copy(b.loadFloat(133.7), to: f2)      // (Possibly) mutating instruction must be included
        let o = b.createObject(with: ["i": i, "f": f])
        b.storeProperty(f2, as: "f", on: o)     // (Possibly) mutating instruction must be included
        let object = b.loadBuiltin("Object")
        let descriptor = b.createObject(with: ["value": b.loadString("foobar")])
        b.callMethod("defineProperty", on: object, withArgs: [o, b.loadString("s"), descriptor])    // (Possibly) mutating instruction must be included
        let json = b.loadBuiltin("JSON")
        b.callMethod("stringify", on: json, withArgs: [o])
        let expectedSplice = b.finalize()
        
        // Actual splice
        let idx = original.lastInstruction.index - 1
        XCTAssert(original[idx].operation is CallMethod)
        b.splice(from: original, at: idx)
        let actualSplice = b.finalize()
        
        print(fuzzer.lifter.lift(expectedSplice))
        print(fuzzer.lifter.lift(actualSplice))
        XCTAssertEqual(expectedSplice, actualSplice)
    }
}

extension ProgramBuilderTests {
    static var allTests : [(String, (ProgramBuilderTests) -> () throws -> Void)] {
        return [
            ("testCodeGeneration", testCodeGeneration),
            ("testSplicing1", testSplicing1),
            ("testSplicing2", testSplicing2),
            ("testSplicing3", testSplicing3)
        ]
    }
}