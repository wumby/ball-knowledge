import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("usage: render_svg input.svg output.png") }
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let data = try Data(contentsOf: input)
guard let image = NSImage(data: data),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render SVG")
}
try png.write(to: output)
