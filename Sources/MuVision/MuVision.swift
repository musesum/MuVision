import Foundation
import MuFlo

public struct MuVision {

    public static let bundle = Bundle.module

    public static func read(_ filename: String,
                            _ ext: String) -> String? {

        guard let path = Bundle.module.path(forResource: filename,
                                            ofType: ext)  else {
            PrintLog("⁉️ MuVision:: couldn't find file: \(filename).\(ext)")
            return nil
        }
        do {
            return try String(contentsOfFile: path) }
        catch {
            PrintLog("⁉️ MuVision::read err: \(error) loading contents of:\(path)")
        }
        return nil
    }

}
