//  created by musesum on 8/6/26.

import Metal
import MuFlo

/// compile error mapped into the embed body's own line space
public struct EmbedError: Sendable {
    public let line: Int      /// 1-based line within embed body
    public let col: Int
    public let message: String

    public init(line: Int, col: Int, message: String) {
        self.line = line
        self.col = col
        self.message = message
    }
}

public enum StitchError: Error {
    case missingMarkers  /// template has no {{ }} region
    case bodyClosesEmbed /// body contains `}}`, which ends a .flo embed
}

extension Shader {

    /// splice embed body between the first {{ }} region of template;
    /// returns stitched source plus the {{ marker's 1-based line
    public static func stitch(_ template: String,
                              body: String) throws -> (source: String, bodyLine: Int) {

        if body.contains("}}") { throw StitchError.bodyClosesEmbed }

        guard let open = template.range(of: "{{"),
              let close = template.range(of: "}}", range: open.upperBound ..< template.endIndex)
        else { throw StitchError.missingMarkers }

        let source = (template[..<open.upperBound] +
                      body +
                      template[close.lowerBound...])
        let bodyLine = template[..<open.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return (String(source), bodyLine)
    }

    /// inner text of template's first {{ }} region
    public static func templateBody(_ template: String) -> String? {
        guard let open = template.range(of: "{{"),
              let close = template.range(of: "}}", range: open.upperBound ..< template.endIndex)
        else { return nil }
        return String(template[open.upperBound ..< close.lowerBound])
    }

    /// parse `program_source:LINE:COL: error: msg` into embed-relative lines
    public static func embedErrors(_ log: String,
                                   bodyLine: Int) -> [EmbedError] {
        var result = [EmbedError]()
        let pattern = #"program_source:(\d+):(\d+): (?:fatal )?error: ([^\n]*)"#
        guard let regx = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(log.startIndex..., in: log)
        for match in regx.matches(in: log, range: range) {
            if let lineR = Range(match.range(at: 1), in: log),
               let colR  = Range(match.range(at: 2), in: log),
               let msgR  = Range(match.range(at: 3), in: log) {

                let line = (Int(log[lineR]) ?? 1) - bodyLine + 1
                result.append(EmbedError(line: max(1, line),
                                         col: Int(log[colR]) ?? 0,
                                         message: String(log[msgR])))
            }
        }
        return result
    }

}
