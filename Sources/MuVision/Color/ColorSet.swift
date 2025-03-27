import Foundation


class ColorSet {

    var hsvs = [String: Hsv]()

    init() {
        makePresets()
    }
    func makePresets() {
        hsvs["nil"]     = Hsv(    0, 0, 0)
        hsvs["red"]     = Hsv(    0, 1, 1)
        hsvs["orange"]  = Hsv( 1/12, 1, 1)
        hsvs["yellow"]  = Hsv( 2/12, 1, 1)
        hsvs["green"]   = Hsv( 4/12, 1, 1)
        hsvs["teal"]    = Hsv( 8/12, 1, 1)
        hsvs["blue"]    = Hsv( 9/12, 1, 1)
        hsvs["indigo"]  = Hsv(10/12, 1, 1)
        hsvs["purple"]  = Hsv( 1/12, 1, 1)
        hsvs["violet"]  = Hsv( 2/12, 1, 1)
        hsvs["magenta"] = Hsv( 4/12, 1, 1)
        hsvs["white"]   = Hsv(    0, 0, 1)
        hsvs["gray"]    = Hsv(    0, 0, 0.5)
        hsvs["black"]   = Hsv(    0, 0, 0)

        hsvs["r"] = Hsv(    0, 1, 1) // red
        hsvs["o"] = Hsv( 1/12, 1, 1) // orange
        hsvs["y"] = Hsv( 2/12, 1, 1) // yellow
        hsvs["g"] = Hsv( 4/12, 1, 1) // green
        hsvs["b"] = Hsv( 8/12, 1, 1) // blue
        hsvs["i"] = Hsv( 9/12, 1, 1) // indigo
        hsvs["v"] = Hsv(10/12, 1, 1) // violet
        hsvs["k"] = Hsv(    0, 0, 1) // black
        hsvs["w"] = Hsv(    0, 0, 0) // white
    }
}
