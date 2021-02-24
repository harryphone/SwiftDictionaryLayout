//
//  main.swift
//  SwiftDictionaryLayout
//
//  Created by HarryPhone on 2021/2/22.
//

// Native dictionary storage uses a data structure like this::
//
//   struct Dictionary<K,V>
//   +------------------------------------------------+
//   | enum Dictionary<K,V>._Variant                  |
//   | +--------------------------------------------+ |
//   | | [struct _NativeDictionary<K,V>             | |
//   | +---|----------------------------------------+ |
//   +----/-------------------------------------------+
//       /
//      |
//      V
//   class __RawDictionaryStorage
//   +-----------------------------------------------------------+
//   | <isa>                                                     |
//   | <refcount>                                                |
//   | _count                                                    |
//   | _capacity                                                 |
//   | _scale                                                    |
//   | _age                                                      |
//   | _seed                                                     |
//   | _rawKeys                                                  |
//   | _rawValue                                                 |
//   | [inline bitset of occupied entries]                       |
//   | [inline array of keys]                                    |
//   | [inline array of values]                                  |
//   +-----------------------------------------------------------+
//

import Foundation


struct NativeDictionary<Key: Hashable, Value> {
    var storage: UnsafeMutablePointer<RawDictionaryStorage<Key, Value>>
}


struct RawDictionaryStorage<Key: Hashable, Value> {
    var metadata: UnsafeMutableRawPointer
    var refCounts: UInt
    // The current number of occupied entries in this dictionary.
    var count: Int
    // The maximum number of elements that can be inserted into this set without exceeding the hash table's maximum load factor.
    var capacity: Int
    // The scale of this dictionary. The number of buckets is 2 raised to the power of `scale`.
    var scale: Int8
    // The scale corresponding to the highest `reserveCapacity(_:)` call so far, or 0 if there were none. This may be used later to allow removals to resize storage.
    var reservedScale: Int8
    // Currently unused, set to zero.
    var extra: Int16
    // A mutation count, enabling stricter index validation.
    var age: Int32
    // The hash seed used to hash elements in this dictionary instance.
    // 这个hash用的种子，这里存放的是RawDictionaryStorage自己本身的地址，也就是用地址值做成的种子
    var seed: Int
    
    // A raw pointer to the start of the tail-allocated hash buffer holding keys.
    var rawKeys: UnsafeMutablePointer<Key>
    // A raw pointer to the start of the tail-allocated hash buffer holding values.
    var rawValues: UnsafeMutablePointer<Value>
    
    mutating func getHashTable() -> HashTable {
        let hashTablePtr = withUnsafeMutablePointer(to: &self) {
            return UnsafeMutableRawPointer($0.advanced(by: 1)).assumingMemoryBound(to: HashTable.Word.self)
        }
        let bucketCount = (1 as Int) &<< scale
        return HashTable.init(words: hashTablePtr, bucketMask: bucketCount &- 1)
    }
    
    mutating func printAllKeysAndValues() {
        let hashTable = getHashTable()
        for i in 0..<(1 &<< Int(scale)) {
            if ((1 &<< i & hashTable.words.pointee) != 0) {
                print("字典的key：\(rawKeys.advanced(by: i).pointee)")
                print("字典的value：\(rawValues.advanced(by: i).pointee)")
                print("-------------------")
            }
        }
    }

}

struct HashTable {
    typealias Word = UInt
    var words: UnsafeMutablePointer<Word>
    var bucketMask: Int
}

var dic = [1: "dog", 2: "cat", 3: "bike", 4: "car"]

func getDictionaryBuffer<Key: Hashable, Value>(from dic: inout Dictionary<Key, Value>) -> NativeDictionary<Key, Value> {
    return unsafeBitCast(dic, to: NativeDictionary<Key, Value>.self)
}

var buffer = getDictionaryBuffer(from: &dic)
print("字典内容个数：\(buffer.storage.pointee.count)")

buffer.storage.pointee.printAllKeysAndValues()
print(dic)

print("\n\n-------华丽的分隔符，很神奇哦，每次打印的顺序都不一样--------\n\n")

dic[777] = "joke"
dic[7774] = "joke3"
dic[7775] = "joke4"
dic[7776] = "joke5"
dic[7777] = "joke6"

buffer = getDictionaryBuffer(from: &dic)

print("字典内容个数：\(buffer.storage.pointee.count)")

buffer.storage.pointee.printAllKeysAndValues()
print(dic)
//print("end")


// key通过hash完一系列操作获得bucket的位置，然后在rawKeys和rawValues中取对应的值，由于hash流程封装有点复杂，没有实现

