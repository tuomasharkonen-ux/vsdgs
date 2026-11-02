// Turns a portrait photo into a background-free halftone dot SVG.
// Usage: swift tools/halftone.swift <input.jpg> <output.svg> [columns] [hex color]
// Uses macOS Vision (macOS 14+) to cut the person out of the background.

import Foundation
import CoreGraphics
import ImageIO
import Vision

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: swift halftone.swift <input> <output.svg> [columns=64] [color=#ffcb47]")
    exit(1)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let columns = args.count > 3 ? Int(args[3])! : 64
let color = args.count > 4 ? args[4] : "#ffcb47"

guard let src = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fatalError("Could not read \(inputURL.path)")
}
let w = image.width, h = image.height

// 1. Foreground mask from Vision (Float32, 0...1, same size as the input), plus the face box.
let handler = VNImageRequestHandler(cgImage: image)
let request = VNGenerateForegroundInstanceMaskRequest()
let faceRequest = VNDetectFaceRectanglesRequest()
try handler.perform([request, faceRequest])
guard let observation = request.results?.first else { fatalError("No person found") }

// Crop to head and shoulders around the face (square, in top-left pixel coordinates).
var cropX = 0.0, cropY = 0.0, cropSide = Double(min(w, h))
if let face = faceRequest.results?.first?.boundingBox {
    let fw = face.width * Double(w)
    let fcx = face.midX * Double(w)
    let ftop = (1 - face.maxY) * Double(h)
    cropSide = min(fw * 2.3, Double(min(w, h)))
    cropX = min(max(fcx - cropSide / 2, 0), Double(w) - cropSide)
    cropY = min(max(ftop - fw * 0.6, 0), Double(h) - cropSide)
}
let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)

CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
let maskBase = CVPixelBufferGetBaseAddress(maskBuffer)!
let maskStride = CVPixelBufferGetBytesPerRow(maskBuffer)
func mask(_ x: Int, _ y: Int) -> Float {
    maskBase.advanced(by: y * maskStride).assumingMemoryBound(to: Float32.self)[x]
}

// 2. Grayscale pixels.
var gray = [UInt8](repeating: 0, count: w * h)
let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// 3. One dot per cell; brighter areas get bigger dots (the site background is dark).
let cell = cropSide / Double(columns)
let rows = columns
let size = 100.0 / Double(columns)   // SVG units per cell; viewBox is 100 x 100
struct Cell { let x: Double; let y: Double; let lum: Double; let alpha: Double }
var cells: [Cell] = []

for row in 0..<rows {
    let offset = row % 2 == 0 ? 0.0 : 0.5   // staggered rows read more like print halftone
    for col in 0..<columns {
        let cx = cropX + (Double(col) + 0.5 + offset) * cell
        guard cx < cropX + cropSide else { continue }
        let x0 = Int(cx - cell / 2), y0 = Int(cropY + Double(row) * cell)
        var lum = 0.0, alpha = 0.0, n = 0.0
        for y in stride(from: max(y0, 0), to: min(y0 + Int(cell), h), by: 1) {
            for x in stride(from: max(x0, 0), to: min(x0 + Int(cell), w), by: 1) {
                lum += Double(gray[y * w + x]) / 255
                alpha += Double(mask(x, y))
                n += 1
            }
        }
        guard n > 0 else { continue }
        lum /= n; alpha /= n
        guard alpha > 0.35 else { continue }
        cells.append(Cell(x: (Double(col) + 0.5 + offset) * size, y: (Double(row) + 0.5) * size, lum: lum, alpha: alpha))
    }
}
CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly)

// Stretch contrast across the person only (ignores the removed background).
let sorted = cells.map(\.lum).sorted()
let lo = sorted[Int(Double(sorted.count) * 0.02)]
let hi = sorted[Int(Double(sorted.count) * 0.995)]

var circles: [String] = []
for c in cells {
    let t = min(1, max(0, (c.lum - lo) / (hi - lo)))
    let tone = pow(t, 1.4)   // keeps separation in the bright skin tones
    let r = size * 0.5 * tone * min(1, c.alpha * 1.2)   // max 0.5: dots touch but never merge
    guard r > size * 0.08 else { continue }
    circles.append(String(format: "<circle cx=\"%.2f\" cy=\"%.2f\" r=\"%.2f\"/>", c.x, c.y, r))
}

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
<g fill="\(color)">
\(circles.joined(separator: "\n"))
</g>
</svg>
"""
try svg.write(to: outputURL, atomically: true, encoding: .utf8)
print("Wrote \(circles.count) dots to \(outputURL.path)")
