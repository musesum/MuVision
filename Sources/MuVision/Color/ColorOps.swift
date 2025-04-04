//  created by musesum on 7/30/19.

import Foundation

public struct ColorOps: OptionSet, Sendable {

    public let rawValue: Int

    public static let gradient = ColorOps(rawValue: 1 << 0) // smooth gradient between left and right
    public static let black = ColorOps(rawValue: 1 << 1)    // left and right are black
    public static let white = ColorOps(rawValue: 1 << 2)    // left and right are white
    public static let zeno = ColorOps(rawValue: 1 << 3)     // zeno fractalize 1/2 + 1/4 + 1/8 ...
    public static let flip = ColorOps(rawValue: 1 << 4)     // flip right to left

    var gradient : Bool { contains(. gradient) }
    var black    : Bool { contains(. black   ) }
    var white    : Bool { contains(. white   ) }
    var zeno     : Bool { contains(. zeno    ) }
    var flip     : Bool { contains(. flip    ) }


    public init(rawValue: Int = 0) { self.rawValue = rawValue }

    public init(with: String) {
        self.init()
        for char in with {
            switch char {
            case "/": insert(.gradient)
            case "K": insert(.black)
            case "W": insert(.white)
            case "Z": insert(.zeno)
            case "F": insert(.flip)
            default: continue
            }
        }
    }
}
