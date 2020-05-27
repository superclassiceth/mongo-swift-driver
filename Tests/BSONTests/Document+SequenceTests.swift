import Foundation
@testable import MongoSwift
import Nimble
import TestsCommon
import XCTest

final class Document_SequenceTests: MongoSwiftTestCase {
    func testIterator() {
        let doc: BSONDocument = [
            "string": "test string",
            "true": true,
            "false": false,
            "int": 25,
            "int32": .int32(5),
            "int64": .int64(123),
            "double": .double(15),
            "decimal128": .decimal128(BSONDecimal128("1.2E+10")!),
            "minkey": .minKey,
            "maxkey": .maxKey,
            "date": .datetime(Date(timeIntervalSince1970: 5000)),
            "timestamp": .timestamp(BSONTimestamp(timestamp: 5, inc: 10))
        ]

        // create and use iter manually
        let iter = doc.makeIterator()

        let stringTup = iter.next()!
        expect(stringTup.key).to(equal("string"))
        expect(stringTup.value).to(equal("test string"))

        let trueTup = iter.next()!
        expect(trueTup.key).to(equal("true"))
        expect(trueTup.value).to(equal(true))

        let falseTup = iter.next()!
        expect(falseTup.key).to(equal("false"))
        expect(falseTup.value).to(equal(false))

        let intTup = iter.next()!
        expect(intTup.key).to(equal("int"))
        expect(intTup.value).to(equal(25))

        let int32Tup = iter.next()!
        expect(int32Tup.key).to(equal("int32"))
        expect(int32Tup.value).to(equal(.int32(5)))

        let int64Tup = iter.next()!
        expect(int64Tup.key).to(equal("int64"))
        expect(int64Tup.value).to(equal(.int64(123)))

        let doubleTup = iter.next()!
        expect(doubleTup.key).to(equal("double"))
        expect(doubleTup.value).to(equal(15.0))

        let decimalTup = iter.next()!
        expect(decimalTup.key).to(equal("decimal128"))
        expect(decimalTup.value).to(equal(.decimal128(BSONDecimal128("1.2E+10")!)))

        let minTup = iter.next()!
        expect(minTup.key).to(equal("minkey"))
        expect(minTup.value).to(equal(.minKey))

        let maxTup = iter.next()!
        expect(maxTup.key).to(equal("maxkey"))
        expect(maxTup.value).to(equal(.maxKey))

        let dateTup = iter.next()!
        expect(dateTup.key).to(equal("date"))
        expect(dateTup.value).to(equal(.datetime(Date(timeIntervalSince1970: 5000))))

        let timeTup = iter.next()!
        expect(timeTup.key).to(equal("timestamp"))
        expect(timeTup.value).to(equal(.timestamp(BSONTimestamp(timestamp: 5, inc: 10))))

        expect(iter.next()).to(beNil())

        // iterate via looping
        var expectedKeys = [
            "string", "true", "false", "int", "int32", "int64", "double",
            "decimal128", "minkey", "maxkey", "date", "timestamp"
        ]
        var expectedValues: [BSON] = [
            "test string", true, false, 25, .int32(5), .int64(123), .double(15),
            .decimal128(BSONDecimal128("1.2E+10")!), .minKey, .maxKey, .datetime(Date(timeIntervalSince1970: 5000)),
            .timestamp(BSONTimestamp(timestamp: 5, inc: 10))
        ]
        for (k, v) in doc {
            expect(k).to(equal(expectedKeys.removeFirst()))
            expect(v).to(equal(expectedValues.removeFirst()))
        }
    }

    func testMapFilter() throws {
        let doc1: BSONDocument = ["a": 1, "b": .null, "c": 3, "d": 4, "e": .null]
        expect(doc1.mapValues { $0 == .null ? 1 : $0 }).to(equal(["a": 1, "b": 1, "c": 3, "d": 4, "e": 1]))
        let output1 = doc1.mapValues { val in
            if let int = val.toInt() {
                return BSON(integerLiteral: int + 1)
            }
            return val
        }
        expect(output1).to(equal(["a": 2, "b": .null, "c": 4, "d": 5, "e": .null]))
        expect(doc1.filter { !($0.value == .null) }).to(equal(["a": 1, "c": 3, "d": 4]))

        let doc2: BSONDocument = ["a": 1, "b": "hello", "c": [1, 2]]
        expect(doc2.filter { $0.value.stringValue != nil }).to(equal(["b": "hello"]))
        let output2 = doc2.mapValues { val in
            switch val {
            case let .int64(val):
                return .int64(val + 1)
            case let .string(val):
                return .string(val + " there")
            case .array:
                return BSON(integerLiteral: val.arrayValue!.compactMap { $0.toInt() }.reduce(0, +))
            default:
                return val
            }
        }
        expect(output2).to(equal(["a": 2, "b": "hello there", "c": 3]))

        // test that the protocol-supplied version of filter is still available
        let _: [BSONDocument.KeyValuePair] = doc1.filter { $0.key != "a" }
    }

    // shared docs for subsequence tests
    let emptyDoc = BSONDocument()
    let smallDoc: BSONDocument = ["x": 1]
    let doc: BSONDocument = ["a": 1, "b": "hi", "c": [1, 2], "d": false, "e": .null, "f": .minKey, "g": 10]

    // shared predicates for subsequence tests
    func isInt(_ pair: BSONDocument.KeyValuePair) -> Bool { pair.value.toInt() != nil }
    func isNotNil(_ pair: BSONDocument.KeyValuePair) -> Bool { pair.value != .null }
    func is10(_ pair: BSONDocument.KeyValuePair) -> Bool {
        if let int = pair.value.toInt() {
            return int == 10
        }
        return false
    }

    func isNot10(_ pair: BSONDocument.KeyValuePair) -> Bool { !self.is10(pair) }

    func testDropFirst() throws {
        expect(self.emptyDoc.dropFirst(0)).to(equal([:]))
        expect(self.emptyDoc.dropFirst(1)).to(equal([:]))

        expect(self.smallDoc.dropFirst(0)).to(equal(self.smallDoc))
        expect(self.smallDoc.dropFirst()).to(equal([:]))
        expect(self.smallDoc.dropFirst(2)).to(equal([:]))

        expect(self.doc.dropFirst(0)).to(equal(self.doc))
        expect(self.doc.dropFirst()).to(equal(
            [
                "b": "hi",
                "c": [1, 2],
                "d": false,
                "e": .null,
                "f": .minKey,
                "g": 10
            ]
        ))
        expect(self.doc.dropFirst(4)).to(equal(["e": .null, "f": .minKey, "g": 10]))
        expect(self.doc.dropFirst(7)).to(equal([:]))
        expect(self.doc.dropFirst(8)).to(equal([:]))
    }

    func testDropLast() throws {
        expect(self.emptyDoc.dropLast(0)).to(equal([:]))
        expect(self.emptyDoc.dropLast(1)).to(equal([:]))

        expect(self.smallDoc.dropLast(0)).to(equal(self.smallDoc))
        expect(self.smallDoc.dropLast()).to(equal([:]))
        expect(self.smallDoc.dropLast(2)).to(equal([:]))

        expect(self.doc.dropLast(0)).to(equal(self.doc))
        expect(self.doc.dropLast()).to(equal([
            "a": 1,
            "b": "hi",
            "c": [1, 2],
            "d": false,
            "e": .null,
            "f": .minKey
        ]))
        expect(self.doc.dropLast(4)).to(equal(["a": 1, "b": "hi", "c": [1, 2]]))
        expect(self.doc.dropLast(7)).to(equal([:]))
        expect(self.doc.dropLast(8)).to(equal([:]))
    }

    func testDropPredicate() throws {
        expect(self.emptyDoc.drop(while: self.isInt)).to(equal([:]))
        expect(self.smallDoc.drop(while: self.isInt)).to(equal([:]))
        expect(self.doc.drop(while: self.isInt)).to(equal([
            "b": "hi",
            "c": [1, 2],
            "d": false,
            "e": .null,
            "f": .minKey,
            "g": 10
        ]))

        expect(self.emptyDoc.drop(while: self.isNotNil)).to(equal([:]))
        expect(self.smallDoc.drop(while: self.isNotNil)).to(equal([:]))
        expect(self.doc.drop(while: self.isNotNil)).to(equal(["e": .null, "f": .minKey, "g": 10]))

        expect(self.emptyDoc.drop(while: self.isNot10)).to(equal([:]))
        expect(self.smallDoc.drop(while: self.isNot10)).to(equal([:]))
        expect(self.doc.drop(while: self.isNot10)).to(equal(["g": 10]))

        expect(self.emptyDoc.drop(while: self.is10)).to(equal([:]))
        expect(self.smallDoc.drop(while: self.is10)).to(equal(self.smallDoc))
        expect(self.doc.drop(while: self.is10)).to(equal(self.doc))
    }

    func testPrefixLength() throws {
        expect(self.emptyDoc.prefix(0)).to(equal([:]))
        expect(self.emptyDoc.prefix(1)).to(equal([:]))

        expect(self.smallDoc.prefix(0)).to(equal([:]))
        expect(self.smallDoc.prefix(1)).to(equal(self.smallDoc))
        expect(self.smallDoc.prefix(2)).to(equal(self.smallDoc))

        expect(self.doc.prefix(0)).to(equal([:]))
        expect(self.doc.prefix(1)).to(equal(["a": 1]))
        expect(self.doc.prefix(2)).to(equal(["a": 1, "b": "hi"]))
        expect(self.doc.prefix(4)).to(equal(["a": 1, "b": "hi", "c": [1, 2], "d": false]))
        expect(self.doc.prefix(7)).to(equal(self.doc))
        expect(self.doc.prefix(8)).to(equal(self.doc))
    }

    func testPrefixPredicate() throws {
        expect(self.emptyDoc.prefix(while: self.isInt)).to(equal([:]))
        expect(self.smallDoc.prefix(while: self.isInt)).to(equal(self.smallDoc))
        expect(self.doc.prefix(while: self.isInt)).to(equal(["a": 1]))

        expect(self.emptyDoc.prefix(while: self.isNotNil)).to(equal([:]))
        expect(self.smallDoc.prefix(while: self.isNotNil)).to(equal(self.smallDoc))
        expect(self.doc.prefix(while: self.isNotNil)).to(equal(["a": 1, "b": "hi", "c": [1, 2], "d": false]))

        expect(self.emptyDoc.prefix(while: self.isNot10)).to(equal([:]))
        expect(self.smallDoc.prefix(while: self.isNot10)).to(equal(self.smallDoc))
        expect(self.doc.prefix(while: self.isNot10)).to(equal(
            [
                "a": 1,
                "b": "hi",
                "c": [1, 2],
                "d": false,
                "e": .null,
                "f": .minKey
            ]
        ))

        expect(self.emptyDoc.prefix(while: self.is10)).to(equal([:]))
        expect(self.smallDoc.prefix(while: self.is10)).to(equal([:]))
        expect(self.doc.prefix(while: self.is10)).to(equal([:]))
    }

    func testSuffix() throws {
        expect(self.emptyDoc.suffix(0)).to(equal([:]))
        expect(self.emptyDoc.suffix(1)).to(equal([:]))
        expect(self.emptyDoc.suffix(5)).to(equal([:]))

        expect(self.smallDoc.suffix(0)).to(equal([:]))
        expect(self.smallDoc.suffix(1)).to(equal(self.smallDoc))
        expect(self.smallDoc.suffix(2)).to(equal(self.smallDoc))
        expect(self.smallDoc.suffix(5)).to(equal(self.smallDoc))

        expect(self.doc.suffix(0)).to(equal([:]))
        expect(self.doc.suffix(1)).to(equal(["g": 10]))
        expect(self.doc.suffix(2)).to(equal(["f": .minKey, "g": 10]))
        expect(self.doc.suffix(4)).to(equal(["d": false, "e": .null, "f": .minKey, "g": 10]))
        expect(self.doc.suffix(7)).to(equal(self.doc))
        expect(self.doc.suffix(8)).to(equal(self.doc))
    }

    func testSplit() throws {
        expect(self.emptyDoc.split(whereSeparator: self.isInt)).to(equal([]))
        expect(self.smallDoc.split(whereSeparator: self.isInt)).to(equal([]))
        expect(self.doc.split(whereSeparator: self.isInt)).to(equal(
            [
                [
                    "b": "hi",
                    "c": [1, 2],
                    "d": false,
                    "e": .null,
                    "f": .minKey
                ]
            ]
        ))

        expect(self.emptyDoc.split(omittingEmptySubsequences: false, whereSeparator: self.isInt)).to(equal([[:]]))
        expect(self.smallDoc.split(omittingEmptySubsequences: false, whereSeparator: self.isInt)).to(equal([[:], [:]]))
        expect(self.doc.split(omittingEmptySubsequences: false, whereSeparator: self.isInt)).to(equal(
            [
                [:],
                ["b": "hi", "c": [1, 2], "d": false, "e": .null, "f": .minKey],
                [:]
            ]
        ))

        expect(self.doc.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: self.isInt))
            .to(equal([[:], ["b": "hi", "c": [1, 2], "d": false, "e": .null, "f": .minKey, "g": 10]]))
    }

    func testIsEmpty() throws {
        expect(self.emptyDoc.isEmpty).to(beTrue())
        expect(self.smallDoc.isEmpty).to(beFalse())
        expect(self.doc.isEmpty).to(beFalse())
    }
}
