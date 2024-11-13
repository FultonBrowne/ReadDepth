//
//  DepthImage.swift
//  ReadDepth
//
//  Created by Fulton Browne on 11/13/24.
//


import SwiftUI
import CoreGraphics
import ImageIO

class DepthImage: ObservableObject {
    @Published var colorImage: NSImage?
    @Published var depthOverlayImage: NSImage?
    var depthData: [Float] = []
    var colorImageOrientation: UInt32 = 1 // Default orientation
    var width: Int = 0
    var height: Int = 0

    func loadDepthTIFF(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("Failed to load depth map from \(url)")
            return
        }

        self.width = cgImage.width
        self.height = cgImage.height

        // Extract the depth data
        if let dataProvider = cgImage.dataProvider,
           let data = dataProvider.data {
            let ptr = CFDataGetBytePtr(data)
            let length = CFDataGetLength(data)
            let totalPixels = length / MemoryLayout<Float>.size

            if totalPixels == width * height {
                self.depthData = [Float](repeating: 0, count: totalPixels)
                _ = self.depthData.withUnsafeMutableBytes { buffer in
                    memcpy(buffer.baseAddress!, ptr, length)
                }
                rotateDepthData(orientation: colorImageOrientation)
                createDepthOverlayImage()
            } else {
                print("Data length does not match width * height")
            }
        } else {
            print("Failed to get data provider")
        }
    }
    
    func applyManualRotation(angle: RotationAngle) {
        // Rotate the depth data
        rotateDepthDataByAngle(angle: angle)
        
        // Recreate the depth overlay image with the rotated data
        createDepthOverlayImage()
    }

    func loadColorImage(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("Failed to load color image from \(url)")
            return
        }

        // Get image properties
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as Dictionary?
        var orientationValue: UInt32 = 1 // Default orientation

        if let orientationNumber = properties?[kCGImagePropertyOrientation] as? NSNumber {
            orientationValue = orientationNumber.uint32Value
        }

        // Store the orientation
        self.colorImageOrientation = orientationValue

        // Create NSImage from CGImage
        self.colorImage = NSImage(cgImage: cgImage, size: NSSize.zero)
    }
    
    func rotateDepthDataByAngle(angle: RotationAngle) {
        let size = CGSize(width: width, height: height)
        var rotatedData = depthData

        switch angle {
        case .degrees0:
            // No rotation needed
            return
        case .degrees90:
            rotatedData = rotateDepthDataBy90CW(data: depthData, size: size)
            swap(&width, &height)
        case .degrees180:
            rotatedData = rotateDepthDataBy180(data: depthData, size: size)
        case .degrees270:
            rotatedData = rotateDepthDataBy90CCW(data: depthData, size: size)
            swap(&width, &height)
        }

        depthData = rotatedData
    }
    
    func rotateDepthDataBy180(data: [Float], size: CGSize) -> [Float] {
        let width = Int(size.width)
        let height = Int(size.height)
        var rotatedData = [Float](repeating: 0, count: data.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = (height - y - 1) * width + (width - x - 1)
                rotatedData[dstIndex] = data[srcIndex]
            }
        }
        
        return rotatedData
    }

    func rotateDepthDataBy90CW(data: [Float], size: CGSize) -> [Float] {
        let width = Int(size.width)
        let height = Int(size.height)
        var rotatedData = [Float](repeating: 0, count: data.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = x * height + (height - y - 1)
                rotatedData[dstIndex] = data[srcIndex]
            }
        }
        
        return rotatedData
    }

    func rotateDepthDataBy90CCW(data: [Float], size: CGSize) -> [Float] {
        let width = Int(size.width)
        let height = Int(size.height)
        var rotatedData = [Float](repeating: 0, count: data.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = (width - x - 1) * height + y
                rotatedData[dstIndex] = data[srcIndex]
            }
        }
        
        return rotatedData
    }

    func createDepthOverlayImage() {
        guard depthData.count == width * height else { return }
        if let depthImage = createDepthMapImage() {
            self.depthOverlayImage = depthImage
        }
    }
    
    
    func rotateImage(image: NSImage, orientation: UInt32) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        var transform = CGAffineTransform.identity

        switch orientation {
        case 1:
            // Default orientation, do nothing
            break
        case 3:
            // 180 degrees
            transform = transform.rotated(by: CGFloat.pi)
        case 6:
            // 90 degrees clockwise
            transform = transform.rotated(by: CGFloat.pi / 2)
        case 8:
            // 90 degrees counterclockwise
            transform = transform.rotated(by: -CGFloat.pi / 2)
        default:
            // Other orientations can be added as needed
            break
        }

        let contextSize = CGSize(width: cgImage.width, height: cgImage.height)
        let bitmapContext = CGContext(data: nil,
                                      width: Int(contextSize.width),
                                      height: Int(contextSize.height),
                                      bitsPerComponent: cgImage.bitsPerComponent,
                                      bytesPerRow: 0,
                                      space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: cgImage.bitmapInfo.rawValue)

        bitmapContext?.concatenate(transform)
        bitmapContext?.draw(cgImage, in: CGRect(origin: .zero, size: contextSize))

        if let newCGImage = bitmapContext?.makeImage() {
            return NSImage(cgImage: newCGImage, size: NSSize(width: contextSize.width, height: contextSize.height))
        } else {
            return image
        }
    }
    
    func rotateDepthData(orientation: UInt32) {
        let size = CGSize(width: width, height: height)
        var rotatedData = depthData

        switch orientation {
        case 1:
            // Default orientation, do nothing
            return
        case 3:
            // 180 degrees
            rotatedData = rotateDepthDataBy180(data: depthData, size: size)
        case 6:
            // 90 degrees clockwise
            rotatedData = rotateDepthDataBy90CW(data: depthData, size: size)
            swap(&width, &height)
        case 8:
            // 90 degrees counterclockwise
            rotatedData = rotateDepthDataBy90CCW(data: depthData, size: size)
            swap(&width, &height)
        default:
            // Other orientations can be added as needed
            return
        }

        depthData = rotatedData
    }
    

    func createDepthMapImage() -> NSImage? {
        guard depthData.count == width * height else { return nil }

        let bitsPerComponent = 8
        let bytesPerPixel = 4 // RGBA
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        // Get min and max depth values for normalization
        guard let minDepth = depthData.min(), let maxDepth = depthData.max(), maxDepth > minDepth else {
            return nil
        }

        for i in 0..<depthData.count {
            let normalized = (depthData[i] - minDepth) / (maxDepth - minDepth)
            let color = colorForValue(normalized)
            let offset = i * bytesPerPixel
            pixelData[offset] = UInt8(color.redComponent * 255)
            pixelData[offset + 1] = UInt8(color.greenComponent * 255)
            pixelData[offset + 2] = UInt8(color.blueComponent * 255)
            pixelData[offset + 3] = 255 // Alpha
        }

        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(width: width,
                                    height: height,
                                    bitsPerComponent: bitsPerComponent,
                                    bitsPerPixel: bitsPerComponent * bytesPerPixel,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider,
                                    decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    func colorForValue(_ value: Float) -> NSColor {
        // Use a simple rainbow color map (from blue to red)
        let hue = CGFloat((1.0 - CGFloat(value)) * 240.0 / 360.0) // 0.0 (red) to 0.666... (blue)
        return NSColor(calibratedHue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
    }

    func depthAt(x: Int, y: Int) -> Float? {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return nil
        }
        let index = y * width + x
        let depth = depthData[index]
        if depth.isFinite {
            return depth
        } else {
            return nil
        }
    }
}
