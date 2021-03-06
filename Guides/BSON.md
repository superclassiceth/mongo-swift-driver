# MongoSwift BSON Library
MongoDB stores and transmits data in the form of [BSON](bsonspec.org) documents, and MongoSwift provides a libary that can be used to work with such documents. The following is an example of some of the functionality provided as part of that:
```swift
// Document construction.
let doc: BSONDocument = [
    "name": "Bob",
    "occupation": "Software Engineer",
    "projects": [
        ["id": 76, "title": "Documentation"]
    ]
]
// Reading from documents.
print(doc["name"]) // .string(Bob)
print(doc["projects"]) // .array([.document({ "id": 76, "title": "Documentation" })])

// Document serialization and deserialization.
struct Person: Codable {
    let name: String
    let occupation: String
}
print(try BSONDecoder().decode(Person.self, from: doc)) // Person(name: "Bob", occupation: "Software Engineer")
print(try BSONEncoder().encode(Person(name: "Ted", occupation: "Janitor"))) // { "name": "Ted", "occupation": "Janitor" }
```
This guide will serve as an overview of various parts of the BSON library. To learn more specifics and cover the entirety of the API surface, please refer to the driver's [API reference](https://mongodb.github.io/mongo-swift-driver/).

## BSON values
BSON values have many possible types, ranging from simple 32-bit integers to documents which store more BSON values themselves. To accurately model this, the driver defines the `BSON` enum, which has a distinct case for each BSON type. For the more simple cases such as BSON null, the case has no associated value. For the more complex ones, such as documents, a separate type is defined that the case wraps. Where possible, the enum case will wrap the standard library/Foundation equivalent (e.g. `Double`, `String`, `Date`)
```swift
public enum BSON {
    case .null,
    case .document(BSONDocument)
    case .double(Double)
    case .datetime(Date)
    case .string(String)
    // ...rest of the cases...
}
```
### Initializing a `BSON`
This enum can be instantiated directly like any other enum in the Swift language, but it also conforms to a number of `ExpressibleByXLiteral` protocols, meaning it can be instantiated directly from numeric, string, boolean, dictionary, and array literals.
```swift
let int: BSON = 5 // .int64(5) on 64-bit systems
let double: BSON = 5.5 // .double(5.5)
let string: BSON = "hello world" // .string("hello world")
let bool: BSON = false // .bool(false)
let document: BSON = ["x": 5, "y": true, "z": ["x": 1]] // .document({ "x": 5, "y": true, "z": { "x": 1 } })
let array: BSON = ["1", true, 5.5] // .array([.string("1"), .bool(true), .double(5.5)])
```
All other cases must be initialized directly:
```swift
let date = BSON.datetime(Date())
let objectId = BSON.objectID()
// ...rest of cases...
```
### Unwrapping a `BSON`
To get a `BSON` value as a specific type, you can use `switch` or `if/guard case let` like any other enum in Swift:
```swift
func foo(x: BSON, y: BSON) {
    switch x {
    case let .int32(int32):
        print("got an Int32: \(int32)")
    case let .objectID(oid):
        print("got an objectId: \(oid.hex)")
    default:
        print("got something else")
    }
    guard case let .double(d) = y else {
        print("y must be a double")
        return
    }
    print(d * d)
}
```
While these methods are good for branching, sometimes it is useful to get just the value (e.g. for optional chaining, passing as a parameter, or returning from a function). For those cases, `BSON` has computed properties for each case that wraps a type. These properties will return `nil` unless the underlying BSON value is an exact match to the return type of the property.
```swift
func foo(x: BSON) -> [BSONDocument] {
    guard let documents = x.arrayValue?.compactMap({ $0.documentValue }) else {
        print("x is not an array")
        return []
    }
    return documents
}
print(BSON.int64(5).int32Value) // nil
print(BSON.int32(5).int32Value) // Int32(5)
print(BSON.double(5).int64Value) // nil
print(BSON.double(5).doubleValue) // Double(5.0)
```
### Converting a `BSON`
In some cases, especially when dealing with numbers, it may make sense to coerce a `BSON`'s wrapped value into a similar one. For those situations, there are several conversion methods defined on `BSON` that will unwrap the underlying value and attempt to convert it to the desired type. If that conversion would be lossless, a non-`nil` value is returned. 
```swift
func foo(x: BSON, y: BSON) {
    guard let x = x.toInt(), let y = y.toInt() else {
        print("provide two integer types")
        return
    }
    print(x + y)
}
foo(x: 5, y: 5.0) // 10
foo(x: 5, y: 5) // 10
foo(x: 5.0, y: 5.0) // 10
foo(x: .int32(5), y: .int64(5)) // 10
foo(x: 5.01, y: 5) // error
```
There are similar conversion methods for the other types, namely `toInt32()`, `toDouble()`, `toInt64()`, and `toDecimal128()`.

### Using a `BSON` value
`BSON` conforms to a number of useful Foundation protocols, namely `Codable`, `Equatable`, and `Hashable`. This allows them to be compared, encoded/decoded, and used as keys in maps:
```swift
// Codable conformance synthesized by compiler.
struct X: Codable {
    let _id: BSON
}
// Equatable
let x: BSON = "5"
let y: BSON = 5
let z: BSON = .string("5")
print(x == y) // false
print(x == z) // true
// Hashable
let map: [BSON: String] = [
    "x": "string",
    false: "bool",
    [1, 2, 3]: "array",
    .objectID(): "oid",
    .null: "null",
    .maxKey: "maxKey"
]
```
## Documents
BSON documents are the top-level structures that contain the aforementioned BSON values, and they are also BSON values themselves. The driver defines the `BSONDocument` struct to model this specific BSON type.
### Initializing documents
Like `BSON`, `BSONDocument` can also be initialized by a dictionary literal. The elements within the literal must be `BSON`s, so further literals can be embedded within the top level literal definition:
```swift
let x: BSONDocument = [
    "x": 5,
    "y": 5.5,
    "z": [
        "a": [1, true, .datetime(Date())]
    ]
]
```
Documents can also be initialized directly by passing in a `Data` containing raw BSON bytes:
```swift
try BSONDocument(fromBSON: Data(...))
```
Documents may be initialized from an [extended JSON](https://docs.mongodb.com/manual/reference/mongodb-extended-json/) string as well:
```swift
try BSONDocument(fromJSON: "{ \"x\": true }") // { "x": true }
try BSONDocument(fromJSON: "{ x: false }}}") // error
```
### Using documents
Documents define the interface in which an application communicates with a MongoDB deployment. For that reason, `BSONDocument` has been fitted with functionality to make it both powerful and ergonomic to use for developers.
#### Reading / writing to `BSONDocument`
`BSONDocument` conforms to [`Collection`](https://developer.apple.com/documentation/swift/collection), which allows for easy reading and writing of elements via the subscript operator. On `BSONDocument`, this operator returns and accepts a `BSON?`:
```swift
var doc: BSONDocument = ["x": 1]
print(doc["x"]) // .int64(1)
doc["x"] = ["y": .null]
print(doc["x"]) // .document({ "y": null })
doc["x"] = nil
print(doc["x"]) // nil
print(doc) // { }
```
`BSONDocument` also has the `@dynamicMemberLookup` attribute, meaning it's values can be accessed directly as if they were properties on `BSONDocument`:
```swift
var doc: BSONDocument = ["x": 1]
print(doc.x) // .int64(1)
doc.x = ["y": .null]
print(doc.x) // .document({ "y": null })
doc.x = nil
print(doc.x) // nil
print(doc) // { }
```
`BSONDocument` also conforms to [`Sequence`](https://developer.apple.com/documentation/swift/sequence), which allows it to be iterated over:
```swift
for (k, v) in doc { 
    print("\(k) = \(v)")
}
```
Conforming to `Sequence` also gives a number of useful methods from the functional programming world, such as `map` or `allSatisfy`:
```swift
let allEvens = doc.allSatisfy { _, v in v.toInt() ?? 1 % 2 == 0 }
let squares = doc.map { k, v in v.toInt()! * v.toInt()! }
```
See the documentation for `Sequence` for a full list of methods that `BSONDocument` implements as part of this.

In addition to those protocol conformances, there are a few one-off helpers implemented on `BSONDocument` such as `filter` (that returns a `BSONDocument`) and `mapValues` (also returns a `BSONDocument`):
```swift
let doc: BSONDocument = ["_id": .objectID(), "numCats": 2, "numDollars": 1.56, "numPhones": 1]
doc.filter { k, v in k.contains("num") && v.toInt() != nil }.mapValues { v in .int64(v.toInt64()! + 5) } // { "numCats": 7, "numPhones": 6 }
```
See the driver's documentation for a full listing of `BSONDocument`'s public API.
## `Codable` and `BSONDocument`
[`Codable`](https://developer.apple.com/documentation/swift/codable) is a protocol defined in Foundation that allows for ergonomic conversion between various serialization schemes and Swift data types. As part of the BSON library, MongoSwift defines both `BSONEncoder` and `BSONDecoder` to facilitate this serialization and deserialization to and from BSON via `Codable`. This allows applications to work with BSON documents in a type-safe way, and it removes much of the runtime key presence and type checking required when working with raw documents. It is reccommended that users leverage `Codable` wherever possible in their applications that use the driver instead of accessing documents directly. 

For example, here is an function written using raw documents:
```swift
let person: BSONDocument = [
    "name": "Bob",
    "occupation": "Software Engineer",
    "projects": [
        ["id": 1, "title": "Server Side Swift Application"],
        ["id": 76, "title": "Write documentation"],
    ]
]

func prettyPrint(doc: BSONDocument) {
    guard let name = doc["name"]?.stringValue else {
        print("missing name")
        return
    }
    print("Name: \(name)")
    guard let occupation = doc["occupation"]?.stringValue else {
        print("missing occupation")
        return
    }
    print("Occupation: \(occupation)")
    guard let projects = doc["projects"]?.arrayValue?.compactMap({ $0.documentValue }) else {
        print("missing projects")
        return
    }
    print("Projects:")
    for project in projects {
        guard let title = project["title"] else {
            print("missing title")
            return
        }
        print(title)
    }
}
```
Due to the flexible nature of `BSONDocument`, a number of checks have to be put into the body of the function. This clutters the actual function's logic and requires a lot of boilerplate code. Now, consider the following function which does the same thing but is written leveraging `Codable`:
```swift
struct Project: Codable {
    let id: BSON
    let title: String
}

struct Person: Codable {
    let name: String
    let occupation: String
    let projects: [Project]
}

func prettyPrint(doc: BSONDocument) throws {
    let person = try BSONDecoder().decode(Person.self, from: doc)
    print("Name: \(person.name)")
    print("Occupation: \(person.occupation)")
    print("Projects:")
    for project in person.projects {
        print(project.title)
    }
}
```
In this version, the definition of the data type and the logic of the function are defined completely separately, and it leads to far more readable and concise versions of both. 

### `Codable` in MongoSwift
There are a number of ways for users to leverage `Codable` via driver's API. One such example is through `MongoCollection<T>`. By default, `MongoDatabase.collection` returns a `MongoCollection<BSONDocument>`. Any `find` or `aggregate` method invocation on that returned collection would then return a `MongoCursor<BSONDocument>`, which when iterated returns a `BSONDocument?`:
```swift
let collection = db.collection("person")

// asynchronous API
collection.find(["occupation": "Software Engineer"]).flatMap { cursor in
    cursor.toArray()
}.map { docs in
    docs.forEach { person in
        print(person["name"] ?? "nil")
    }
}
collection.insertOne(["name": "New Hire", "occupation": "Doctor", "projects": []]).whenSuccess { _ in /* ... */ }

// synchronous API
for person in try collection.find(["occupation": "Software Engineer"]) {
    print(try person.get()["name"] ?? "nil")
}
try collection.insertOne(["name": "New Hire", "occupation": "Doctor", "projects": []])
```
However, if the schema of the collection is known, `Codable` structs can be used to work with the data in a more type safe way. To facilitate this, the alternate `collection(name:asType)` method on `MongoDatabase`, which accepts a `Codable` generic type, can be used. The provided type defines the model for all the documents in that collection, and any cursor returned from `find` or `aggregate` on that collection will be generic over that type instead of `BSONDocument`. Iterating such cursors will automatically decode the result documents to the generic type specified. Similarly, `insert` on that collection will accept an instance of that type.
```swift
struct Project: Codable {
    let id: BSON
    let title: String
}

struct Person: Codable {
    let name: String
    let occupation: String
    let projects: [Project]
}

let collection = db.collection("person", withType: Person.self)

// asynchronous API
collection.find(["occupation": "Software Engineer"]).flatMap { cursor in
    cursor.toArray()
}.map { docs in
    docs.forEach { person in
        print(person.name)
    }
}
collection.insertOne(Person(name: "New Hire", occupation: "Doctor", projects: [])).whenSuccess { _ in /* ... */ }

// synchronous API
for person in try collection.find(["occupation": "Software Engineer"]) {
    print(try person.get().name)
}
try collection.insertOne(Person(name: "New Hire", occupation: "Doctor", projects: []))
```
This allows applications that interact with the database to use well-defined Swift types, resulting in clearer and less error-prone code. Similar things can be done with `ChangeStream<T>` and `ChangeStreamEvent<T>`.

## Migration Guides
### Migrating from the 0.2.0 through 1.0.0-rc1 API to the 1.0 API

#### Name Changes
In order to avoid naming conflicts with other libraries, we have prefixed all BSON types that we own with `BSON`:
* `Document` is now `BSONDocument`
* `Binary` is now `BSONBinary`
* `ObjectId` is now `BSONObjectID`
* `RegularExpression` is now `BSONRegularExpression`
* `DBPointer` is now `BSONDBPointer`
* `Symbol` is now `BSONSymbol`
* `Code` is now `BSONCode`
* `CodeWithScope` is now `BSONCodeWithScope`
* `Timestamp` is now `BSONTimestamp`
* `Decimal128` is now `BSONDecimal128`

#### ObjectID Updates

Note that the `D` in `ID` is now capitalized in both the type name `BSONObjectID` and in the `BSON` enum case `.objectID`. We have also provided a default value of `BSONObjectID()` for the `BSON.objectID` case, which simplifies embedding `BSONObjectID`s in `BSONDocument` literals in cases where you are inserting a new ID:
```swift
let doc: Document = ["_id": .objectID(ObjectID())]
let doc: BSONDocument = ["_id": .objectID()] // new
``` 

If you need to use an existing `BSONObjectID` you can still provide one:
```swift
let doc: BSONDocument = ["_id": .objectID(myID)]
```

#### Conversion APIs
The BSON library contains a number of methods for converting between types. Many of these are defined on `BSON` and were previously named `asX()`, e.g. `asInt32()`. These are now all named `toX()` instead.

Additionally, the driver previously supported conversions from `Binary` -> `UUID` and `RegularExpression` -> `NSRegularExpression` through initializers defined in extensions of the type being converted to. For discoverability, this logic has now been moved into `toX()` methods on the source types instead:
```swift
let regExp = try NSRegularExpression(from: myBSONRegExp) // old
let regExp = try myBSONRegExp.toNSRegularExpression() // new

let uuid = try UUID(from: myBSONBinary) // old
let uuid = try myBSONBinary.toUUID() // new
```

#### Extended JSON Conversion
Previously, `Document`/`BSONDocument` had computed properties, `extendedJSON` and `canonicalExtendedJSON`, to support converting to those formats. To better signify that these methods involve a non-constant time conversion, we've converted these properties to methods named `toExtendedJSONString()` and `toCanonicalExtendedJSONString()`, respectively.

#### Errors
Previously, the BSON library used the same types of errors as the driver. As of 1.0.0, the BSON library has its own set of errors. Please see the [error handling guide](https://github.com/mongodb/mongo-swift-driver/blob/master/Guides/Error-Handling.md) for more details.

### Migrating from the 0.0.1-0.1.3 API to the 0.2.0 BSON API
In version 0.2.0 of `MongoSwift`, the public API for using BSON values was changed dramatically. This section will describe the process for migrating from the old API (BSON API v1) to this new one (BSON API v2).
#### Overview of BSON API v1
 The previous API was based around the `BSONValue` protocol. Types that conformed to this protocol could be inserted to or read out of `Document` and could aslo be used in `Document` literals. The protocol was also used in various places around the driver as an existential type or conformance requirement. A related protocol, `BSONNumber`, inherited from `BSONValue` and provided some numeric conversion helpers for the various BSON number types (e.g. `Double`, `Int32`, `Int`). 
```swift
var doc: Document = [
    "a": 5
    "b": ObjectId()
]
let value: BSONValue? = doc["a"] // 5
let intValue = (value as? BSONNumber)?.int32Value // Int32(5)
doc["c"] = "i am a string"
```
This API provided a number of benefits, the principal one being the seamless integration of standard Swift types (e.g. `Int`) and driver custom ones (e.g `ObjectId`) into `Document`'s methods. It also had a few drawbacks, however. In order for `BSONValue` to be used as an existential type, it could not have `Self` or associated type requirements. This ended being a big restriction as it meant `BSONValue` could not be `Equatable`, `Hashable`, or `Codable`. Instead, all of this functionaltiy was put onto the separate wrapper type `AnyBSONValue`, which was used instead of an existential `BSONValue` in many places in order to leverage these common protocol conformances.

Another drawback is that subdocument literals could not be inferred and had to be explicitly casted:
```swift
let x: Document = [
    "x": [
        "y": [
            z: 4
        ] as Document
    ] as Document
]
```
#### Required Updates
In BSON API v2, `BSONNumber`, `BSONValue`, and `AnyBSONValue` no longer exist. They are all entirely replaced by the `BSON` enum.

##### Updating `BSONValue` references

Anywhere in the driver that formerly accepted or returned a `BSONValue` will now accept or return a `BSON`. Wherever `BSONValue` is used as an existential value in your application, a `BSON` will probably work as a drop-in replacement. Any casts will need to be updated to call the appropriate helper property instead.
```swift
func foo(x: BSONValue) -> String? {
    guard let stringValue = x as? String else {
        return nil
    }
    return "foo" + stringValue
}
```
becomes:
```swift
func foo(x: BSON) -> String? {
    guard let stringValue = x.stringValue else {
        return nil
    }
    // or
    guard case let .string(stringValue) = x else {
        return nil
    }
    return "foo" + stringValue
}
```
Similarly, `BSON`'s `Equatable` conformance can be leveraged instead of the old `bsonEquals`.
```swift
func foo(x: BSONValue, y: BSONValue) { 
    if x.bsonEquals(y) { ... }
}
```
becomes simply:
```swift
func foo(x: BSON, y: BSON) {
    if x == y { ... }
}
```
**Generic Requirement**
Currently, there is no equivalent protocol in BSON API v2 to `BSONValue`, so if your application was using it as a generic requirement there is no alternative in the driver. You may have to implement your own similar protocol to achieve the same effect. If such a protocol would be useful to you, please [file a ticket on the driver's Jira project](https://github.com/mongodb/mongo-swift-driver#bugs--feature-requests).

##### Updating `BSONNumber` references
`BSON` should be a drop-in replacement for anywhere `BSONNumber` is used, except for as a generic requirement. One thing to note that `BSONNumber`'s properties (e.g. `.int32Value`) are _conversions_, whereas `BSON`'s are simple unwraps. The conversions on `BSON` are implemented as methods (e.g. `asInt32()`).

```swift
// old
func foo(doc: Document) -> Int? {
    // conversion
    guard let int = (doc["a"] as? BSONNumber)?.intValue else {
        return nil
    }
    // cast
    guard let otherInt = doc["b"] as? Int32 else {
        return nil
    }
    return int*Int(otherInt)
}

// new
func foo(doc: Document) -> Int? {
    // conversion
    guard let int = doc["a"]?.asInt() else {
        return nil
    }
    // cast
    guard let otherInt = doc["b"]?.int32Value else {
        return nil
    }
    // or can use case let
    guard case let .int32(otherInt) = doc["b"] else {
        return nil
    }
    return int * Int(otherInt)
}
```
##### Updating `AnyBSONValue` references
`BSON` should be able to serve as a complete replacement for `AnyBSONValue`.
`Codable` usage:
```swift
// old
struct X: Codable {
    let x: AnyBSONValue
}
// new
struct X: Codable {
    let x: BSON
}
```
`Equatable` usage:
```swift
// old 
let a: [BSONValue] = ["1", 2, false]
let b: [BSONValue] = ["not", "equal"]
return a.map { AnyBSONValue($0) } == b.map { AnyBSONValue($0) }
// new
let a: [BSON] = ["1", 2, false]
let b: [BSON] = ["not", "equal"]
return a == b
```
`Hashable` usage:
```swift
// old
let a: [AnyBSONValue: Int] = [AnyBSONValue("hello"): 4, AnyBSONValue(ObjectId()): 26]
print(a[AnyBSONValue(true)] ?? "nil")
// new
let a: [BSON, Int] = ["hello": 4, .objectId(ObjectId()): 26]
print(a[true] ?? "nil")
```

##### Updating `Document` literals
`BSON` can be expressed by a dictionary literal, string literal, integer literal, float literal, boolean literal, and array literal, so document literals consisting of those literals can largely be left alone. All the other types that formerly conformed to `BSONValue` will need to have their cases explicitly constructed. The cast to `Document` will no longer be required for subdocuments and will need to be removed. All runtime variables will also need to have their cases explicitly constructed whereas in BSON API v1 they could just be inserted directly.
```swift
// BSON API v1
let x: Document = [
    "_id": self.getDocument()
    "x": Date()
    "y": [
        "z": [1, 2, false, ["x": 123] as Document]
    ] as Document
]
```
becomes
```swift
// BSON API v2
let x: Document = [
    "_id": .document(self.getDocument())
    "x": .datetime(Date()),
    "y": [
        "z": [1, 2, false, ["x": 123]
    ]
]
```

