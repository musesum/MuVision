import Foundation
import MuFlo

public struct MuVision {

    public static let bundle = Bundle.module

    public static func read(_ filename: String,
                            _ ext: String) -> String? {

        guard let path = Bundle.module.path(forResource: filename,
                                            ofType: ext)  else {
            print("⁉️ MuVision:: couldn't find file: \(filename).\(ext)")
            return nil
        }
        do {
            return try String(contentsOfFile: path) }
        catch {
            print("⁉️ MuVision \(#function) error:\(error) loading contents of:\(path)")
        }
        return nil
    }
    @discardableResult
    static public func parseFlo(_ root: Flo,
                                _ filename: String,
                                _ ext: String = "flo.h") -> Bool {

        guard let script = MuVision.read(filename, ext) ?? read(filename, ext) else {
            return false
        }
        let success = FloParse().parseScript(root, script)
        print(filename + (success ? " ✓" : " ⁉️ parse failed"))
        return success
    }


    static public func mergeScript(_ root: Flo,
                                   _ script: String) -> Bool {

        let mergeFlo = Flo("√")
        let success = FloParse().parseScript(mergeFlo, script)
        if success {
            mergeNow(mergeFlo, with: root)
        }
        return success
    }

    static func mergeNow(_ mergeFlo: Flo, with root: Flo) {
        if let dispatch = root.dispatch?.dispatch,
           let (flo,_) = dispatch[mergeFlo.hash],
           let mergeExprs = mergeFlo.exprs,
           let floExprs = flo.exprs {

            _ = floExprs.setFromAny(mergeExprs, Visitor(0))
        }
    }


}
