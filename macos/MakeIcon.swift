import AppKit

let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let bounds = NSRect(x: 42, y: 42, width: 940, height: 940)
let background = NSBezierPath(roundedRect: bounds, xRadius: 220, yRadius: 220)
NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.44, blue: 0.32, alpha: 1), ending: NSColor(srgbRed: 0.08, green: 0.23, blue: 0.18, alpha: 1))!.draw(in: background, angle: -70)
let glow = NSBezierPath(ovalIn: NSRect(x: 105, y: 560, width: 610, height: 310))
NSColor.white.withAlphaComponent(0.025).setFill()
glow.fill()
let path = NSBezierPath()
path.move(to: NSPoint(x: 210, y: 500))
path.line(to: NSPoint(x: 340, y: 500))
path.line(to: NSPoint(x: 422, y: 650))
path.line(to: NSPoint(x: 524, y: 340))
path.line(to: NSPoint(x: 626, y: 720))
path.line(to: NSPoint(x: 697, y: 500))
path.line(to: NSPoint(x: 814, y: 500))
path.lineWidth = 48
path.lineJoinStyle = .round
path.lineCapStyle = .round
NSColor(srgbRed: 0.82, green: 0.94, blue: 0.48, alpha: 1).setStroke()
path.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
