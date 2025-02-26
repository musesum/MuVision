// created by musesum on 1/22/24

import Foundation

open class LeftRight<T> {
    var left: T
    var right: T
    init(_ left: T, _ right: T) {
        self.left = left
        self.right = right
    }
}
