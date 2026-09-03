import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
    NSColor(calibratedRed:0.13,green:0.25,blue:0.21,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:s*0.06,y:s*0.06,width:s*0.88,height:s*0.88),xRadius:s*0.2,yRadius:s*0.2).fill()
    NSColor(calibratedRed:0.86,green:0.91,blue:0.80,alpha:1).setFill()
    for (i, height) in [0.18,0.40,0.60,0.35,0.20].enumerated() {
        let h = s*height, w = s*0.066
        NSBezierPath(roundedRect:NSRect(x:s*(0.256+Double(i)*0.104),y:(s-h)/2,width:w,height:h),xRadius:w/2,yRadius:w/2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using:.png,properties:[:]) else { exit(1) }
    try png.write(to:folder.appendingPathComponent(name+".png"))
}
