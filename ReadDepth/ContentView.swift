import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

class DepthImage: ObservableObject {
    @Published var image: NSImage?
    var depthData: [Float] = []
    var width: Int = 0
    var height: Int = 0

    func loadTIFF(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("Failed to load image from \(url)")
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

            // Ensure the data length matches the expected size
            if totalPixels == width * height {
                self.depthData = [Float](repeating: 0, count: totalPixels)
                _ = self.depthData.withUnsafeMutableBytes { buffer in
                    memcpy(buffer.baseAddress!, ptr, length)
                }
            } else {
                print("Data length does not match width * height")
            }
        } else {
            print("Failed to get data provider")
        }

        // Create NSImage from CGImage
        self.image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    func depthAt(x: Int, y: Int) -> Float? {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return nil
        }
        let index = y * width + x
        return depthData[index]
    }
}

struct ContentView: View {
    @StateObject var depthImage = DepthImage()
    @State private var depthValue: Float?
    @State private var mouseLocation: CGPoint = .zero

    var body: some View {
        VStack {
            if let image = depthImage.image {
                GeometryReader { geometry in
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        handleMouseHover(at: value.location, in: geometry.size)
                                    }
                            )
                        if let depth = depthValue {
                            let depthInMillimeters = depth * 1000
                                Text(String(format: "Depth: %.1f mm", depthInMillimeters))
                                    .padding(8)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                                    .position(x: mouseLocation.x + 80, y: mouseLocation.y + 20)
                        }
                    }
                }
            } else {
                Text("No image loaded")
            }
            Button("Load Depth Image") {
                openFile()
            }
            .padding()
        }
    }

    func handleMouseHover(at location: CGPoint, in viewSize: CGSize) {
        let imageSize = CGSize(width: depthImage.width, height: depthImage.height)

        // Calculate scale factors
        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height

        // Adjust for aspect fit scaling
        let aspectWidth = min(viewSize.width, viewSize.height * (imageSize.width / imageSize.height))
        let aspectHeight = min(viewSize.height, viewSize.width * (imageSize.height / imageSize.width))
        let offsetX = (viewSize.width - aspectWidth) / 2
        let offsetY = (viewSize.height - aspectHeight) / 2

        let x = Int((location.x - offsetX) * scaleX)
        let y = Int((viewSize.height - location.y - offsetY) * scaleY)

        if let depth = depthImage.depthAt(x: x, y: y) {
            depthValue = depth
            mouseLocation = location
        } else {
            depthValue = nil
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                depthImage.loadTIFF(url: url)
            }
        }
    }
}
