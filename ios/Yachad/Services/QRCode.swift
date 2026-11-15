import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCode {
    /// Renders `text` as a crisp QR code image (upscaled with nearest-
    /// neighbor filtering so edges stay sharp instead of blurring).
    static func image(for text: String, scale: CGFloat = 10) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard
            let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
            let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            return Image(systemName: "qrcode")
        }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
