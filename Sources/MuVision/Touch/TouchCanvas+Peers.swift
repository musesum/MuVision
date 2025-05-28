//  created by musesum on 12/19/22.

import Foundation
import MuPeers

extension TouchCanvas: PeersDelegate {

    public func didChange() {}

    public func received(data: Data) {

        let decoder = JSONDecoder()
        if let item = try? decoder.decode(TouchCanvasItem.self, from: data) {
            remoteItem(item)
        }
    }

}
