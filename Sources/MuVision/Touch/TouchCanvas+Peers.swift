//  created by musesum on 12/19/22.

import Foundation
import MuPeer

extension TouchCanvas: PeersControllerDelegate {

    public func didChange() {
    }

    public func received(data: Data,
                         viaStream: Bool) -> Bool {

        let decoder = JSONDecoder()
        if let item = try? decoder.decode(TouchCanvasItem.self, from: data) {
            remoteItem(item)
            return true
        }
        return false
    }

}
