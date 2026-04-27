import SwiftUI

@main
struct BaselineApp: App {
    @State private var store: UpdateStore

    init() {
        let initialStore = UpdateStore()
        initialStore.startIfNeeded()
        _store = State(initialValue: initialStore)
    }

    var body: some Scene {
        MenuBarExtra {
                MenuRootView(store: store)
                .frame(width: 430, height: 540)
        } label: {
            Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
                .frame(width: 560, height: 560)
        }
    }
}
