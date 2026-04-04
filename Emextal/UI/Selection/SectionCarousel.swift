import SwiftUI

struct SectionCarousel: View {
    let category: Model.Category
    let modelList: [Model]
    @Binding var selected: Model?

    var body: some View {
        ScrollViewReader { horizontalScrollReader in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    SectionCell(category: category)
                        .frame(width: 200)

                    ForEach(modelList) {
                        AssetCell(model: $0, selected: $selected)
                            .id($0.id)
                    }
                    #if canImport(AppKit)
                    .aspectRatio(1.2, contentMode: .fit)
                    #else
                    .aspectRatio(1.8, contentMode: .fit)
                    #endif
                }
                .frame(height: 200)
                .scrollIndicators(.hidden)
                .padding([.trailing, .top, .bottom])
            }
            .background(.white.opacity(0.3).blendMode(.softLight))
            .onAppear {
                horizontalScrollReader.scrollTo(selected?.id, anchor: .center)
            }
        }
    }
}
