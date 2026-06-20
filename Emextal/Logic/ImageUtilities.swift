#if canImport(AppKit)
    import AppKit
    typealias ImageClass = NSImage
#elseif canImport(UIKit)
    import UIKit
    typealias ImageClass = UIImage
#endif

nonisolated enum ImageUtilities {
    fileprivate nonisolated static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    fileprivate nonisolated static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue

#if canImport(AppKit)
    static func jpegData(from image: NSImage?) -> Data? {
        if let image,
           let data = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: data),
           let imgData = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(floatLiteral: 0.8)]) {
            return imgData
        }
        return nil
    }

#elseif canImport(UIKit)
    static func jpegData(from image: UIImage?) -> Data? {
        image?.jpegData(compressionQuality: 0.8)
    }
#endif
}

extension ImageClass {
    nonisolated func fit(side: CGFloat) -> ImageClass? {
        let newSize: CGSize
        if size.width > size.height {
            // landscape
            let s = side / size.height
            newSize = CGSize(width: size.width * s, height: size.height * s)
        } else {
            // square or portrait
            let s = side / size.width
            newSize = CGSize(width: size.width * s, height: size.height * s)
        }
        return scale(outputSize: newSize)
    }
}

#if canImport(AppKit)
extension NSImage {
    nonisolated var cgImage: CGImage? {
        unsafe cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private nonisolated func scale(outputSize: CGSize) -> NSImage? {
        guard let cgImage = unsafe cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelOutputWidth = Int(outputSize.width)
        let pixelOutputHeight = Int(outputSize.height)

        let cgContext = unsafe CGContext(data: nil, width: pixelOutputWidth, height: pixelOutputHeight, bitsPerComponent: 8, bytesPerRow: pixelOutputWidth * 4, space: ImageUtilities.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)

        guard let cgContext else {
            return nil
        }
        cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelOutputWidth, height: pixelOutputHeight))

        guard let result = cgContext.makeImage() else {
            return nil
        }
        return NSImage(cgImage: result, size: outputSize)
    }
}

#elseif canImport(UIKit)
extension UIImage {
    private nonisolated func scale(outputSize: CGSize) -> UIImage? {
        guard let cgImage else {
            return nil
        }

        let pixelOutputWidth = Int(outputSize.width)
        let pixelOutputHeight = Int(outputSize.height)

        let cgContext = unsafe CGContext(data: nil, width: pixelOutputWidth, height: pixelOutputHeight, bitsPerComponent: 8, bytesPerRow: pixelOutputWidth * 4, space: ImageUtilities.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)

        guard let cgContext else {
            return nil
        }
        cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelOutputWidth, height: pixelOutputHeight))

        guard let result = cgContext.makeImage() else {
            return nil
        }
        return UIImage(cgImage: result)
    }
}
#endif
