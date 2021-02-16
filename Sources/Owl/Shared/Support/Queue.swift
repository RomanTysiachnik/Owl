//  Created by Roman Tysiachnik on 2/16/21.

import Foundation

struct Queue<T> {
    private var array = [T]()

    var isEmpty: Bool {
        array.isEmpty
    }

    var count: Int {
        array.count
    }

    mutating func enqueue(_ element: T) {
        synchronized(self) {
            array.append(element)
        }
    }

    mutating func dequeue() -> T? {
        synchronized(self) {
            if isEmpty {
                return nil
            } else {
                return array.removeFirst()
            }
        }
    }

    mutating func dequeueAll() -> [T] {
        synchronized(self) {
            let result = array
            array.removeAll()
            return result
        }
    }

    var front: T? {
        synchronized(self) {
            array.first
        }
    }

    var all: [T] {
        synchronized(self) {
            array
        }
    }
}

@discardableResult
func synchronized<T>(_ lock: Any, body: () throws -> T) rethrows -> T {
    objc_sync_enter(lock)
    defer { objc_sync_exit(lock) }
    return try body()
}
