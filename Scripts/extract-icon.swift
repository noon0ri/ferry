// 빌드된 .app에서 시스템 아이콘 파이프라인을 통해 아이콘을 PNG로 뽑는다.
//
// actool이 만드는 icon.icns에는 256px까지만 들어간다(macOS 26은 Assets.car를 쓰므로
// 고전 icns를 축약해서 내놓는다). 하지만 Assets.car 안에는 1024px 렌디션이 있고,
// NSWorkspace가 그걸 읽는다. 그래서 앱을 한 번 조립한 뒤 여기서 1024를 뽑아
// 완전한 icns를 다시 만든다.
import AppKit

guard CommandLine.arguments.count >= 4,
      let size = Int(CommandLine.arguments[3]) else {
    FileHandle.standardError.write(Data("usage: extract-icon <app> <out.png> <size>\n".utf8))
    exit(2)
}
let appPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

let icon = NSWorkspace.shared.icon(forFile: appPath)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
          from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outPath))
