import AppKit
import Foundation

/// Makes only the near-white background connected to an image edge transparent.
/// White details enclosed by a logo (for example the Nets basketball) stay intact.
guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("usage: normalize_logo input.png output.png\n", stderr)
    exit(64)
}

let side = 512
let sourceSize = image.size
let width = max(1, Int(sourceSize.width.rounded()))
let height = max(1, Int(sourceSize.height.rounded()))
guard let source = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: source)
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()

let bytesPerRow = source.bytesPerRow
let pixels = source.bitmapData!
func isBackground(_ x: Int, _ y: Int) -> Bool {
    let offset = y * bytesPerRow + x * 4
    return pixels[offset] >= 245 && pixels[offset + 1] >= 245 && pixels[offset + 2] >= 245 && pixels[offset + 3] > 0
}
var visited = Array(repeating: false, count: width * height)
var queue: [(Int, Int)] = []
func enqueue(_ x: Int, _ y: Int) {
    let index = y * width + x
    guard !visited[index], isBackground(x, y) else { return }
    visited[index] = true
    queue.append((x, y))
}
for x in 0..<width { enqueue(x, 0); enqueue(x, height - 1) }
for y in 0..<height { enqueue(0, y); enqueue(width - 1, y) }
var index = 0
while index < queue.count {
    let (x, y) = queue[index]
    index += 1
    let offset = y * bytesPerRow + x * 4
    pixels[offset + 3] = 0
    if x > 0 { enqueue(x - 1, y) }
    if x + 1 < width { enqueue(x + 1, y) }
    if y > 0 { enqueue(x, y - 1) }
    if y + 1 < height { enqueue(x, y + 1) }
}

guard let output = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
let scale = min(CGFloat(side) / sourceSize.width, CGFloat(side) / sourceSize.height)
let target = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
source.draw(in: NSRect(x: (CGFloat(side) - target.width) / 2, y: (CGFloat(side) - target.height) / 2, width: target.width, height: target.height))
NSGraphicsContext.restoreGraphicsState()
try output.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
