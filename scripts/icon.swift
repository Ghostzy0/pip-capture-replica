import AppKit
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
let body = NSBezierPath(roundedRect: NSRect(x: 245, y: 260, width: 550, height: 500), xRadius: 210, yRadius: 210)
let transform = AffineTransform(translationByX: -512, byY: -512)
body.transform(using: transform)
var rotation = AffineTransform(); rotation.rotate(byDegrees: 8); body.transform(using: rotation)
body.transform(using: AffineTransform(translationByX: 512, byY: 512)); body.fill()
NSColor.white.setFill()
for x in [530, 630] { NSBezierPath(roundedRect: NSRect(x: x, y: 500, width: 40, height: 72), xRadius: 20, yRadius: 20).fill() }
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
