// immersion picker: windowed, mixed, full; shared by the apps that open a space

import SwiftUI

#if os(visionOS)

public struct ImmersionPicker: View {

    @Binding private var state: ImmersionModel.State

    public init(state: Binding<ImmersionModel.State>) {
        _state = state
    }

    public var body: some View {
        Picker("Immersion", selection: $state) {
            Image(systemName: "rectangle")
                .scaledToFill()
                .frame(width: 44, height: 44)
                .tag(ImmersionModel.State.windowed)
            Image("icon.room.white", bundle: .module)
                .frame(width: 44, height: 44)
                .tag(ImmersionModel.State.mixed)
            Image("icon.galaxy.white", bundle: .module)
                .frame(width: 44, height: 44)
                .tag(ImmersionModel.State.full)
        }
        .pickerStyle(.segmented)
        .frame(width: 148, height: 44)
    }
}
#endif
