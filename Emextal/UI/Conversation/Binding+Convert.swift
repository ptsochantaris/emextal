import Foundation
import SwiftUI

extension Binding {
    // thanks to https://stackoverflow.com/questions/65736518/how-do-i-create-a-slider-in-swiftui-for-an-int-type-property

    static func convert<TInt: BinaryInteger & Sendable, TFloat: BinaryFloatingPoint & Sendable>(from intBinding: Binding<TInt>) -> Binding<TFloat> {
        Binding<TFloat>(
            get: { TFloat(intBinding.wrappedValue) },
            set: { intBinding.wrappedValue = TInt($0) }
        )
    }

    static func convert<TFloat: BinaryFloatingPoint & Sendable, TInt: BinaryInteger & Sendable>(from floatBinding: Binding<TFloat>) -> Binding<TInt> {
        Binding<TInt>(
            get: { TInt(floatBinding.wrappedValue) },
            set: { floatBinding.wrappedValue = TFloat($0) }
        )
    }

    static func round<TFloat: BinaryFloatingPoint & Sendable>(from floatBinding: Binding<TFloat>) -> Binding<TFloat> {
        Binding<TFloat>(
            get: { floatBinding.wrappedValue },
            set: { floatBinding.wrappedValue = ($0 * 100.0).rounded() / 100.0 }
        )
    }
}
