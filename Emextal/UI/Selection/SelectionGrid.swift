import SwiftUI

struct SelectionGrid: View {
    @Binding var selected: Model?

    var body: some View {
        ScrollViewReader { verticalScrollReader in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The model you select will be downloaded and installed locally on your system. You can change your selection from the menu later. Please ensure you have enough disk space for the model you select.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                        .padding([.leading, .trailing], 64)
                        .frame(maxWidth: .infinity)

                    ForEach(Registry.allCategories) { category in
                        let models = Registry.variants(for: category)
                        if !models.isEmpty {
                            SectionCarousel(category: category, modelList: models, selected: $selected)
                        }
                    }
                }
                .padding([.top, .bottom])
            }
            .onTapGesture {
                selected = nil
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let variant = selected?.variant, let section = Registry.category(for: variant) {
                    verticalScrollReader.scrollTo(section.id)
                }
            }
        }
        .background(PlainBackground())
        .colorScheme(.dark)
    }
}
