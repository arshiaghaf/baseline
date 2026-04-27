import SwiftUI

extension View {
    func menuSectionHeaderStyle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .textCase(nil)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(1)
    }

    func menuListContainerStyle() -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 0)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .stroke(.quaternary.opacity(0.24), lineWidth: 1)
            }
    }

    func menuCardStyle() -> some View {
        self
            .padding(10)
            .background(.quaternary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassEffect()
    }
}
