import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import Foundation

enum RotationAngle: Int, CaseIterable, Identifiable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270

    var id: Int { self.rawValue }
    var description: String {
        "\(self.rawValue)°"
    }
}

struct ContentView: View {
    @StateObject var depthImage = DepthImage()
    @State private var depthValue: Float?
    @State private var mouseLocation: CGPoint = .zero
    @State private var selectedUnit: UnitLength = .millimeters
    @State private var overlayOpacity: Double = 0.5
    
    @State private var selectedRotation: RotationAngle = .degrees0

    var body: some View {
            VStack {
                if let colorImage = depthImage.colorImage {
                    GeometryReader { geometry in
                        ZStack {
                            Image(nsImage: colorImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            handleMouseHover(at: value.location, in: geometry.size)
                                        }
                                )
                            if let overlayImage = depthImage.depthOverlayImage {
                                Image(nsImage: overlayImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .opacity(overlayOpacity)
                                    .allowsHitTesting(false)
                            }
                            if let depth = depthValue {
                                let convertedDepth = convertDepth(depth, to: selectedUnit)
                                let unitSymbol = symbolForUnit(selectedUnit)
                                Text(String(format: "Depth: %.2f %@", convertedDepth, unitSymbol))
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
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: openColorImageFile) {
                        Label("Load Color Image", systemImage: "photo")
                    }
                    Button(action: openDepthFile) {
                        Label("Load Depth Map", systemImage: "cube")
                    }
                }
                ToolbarItemGroup(placement: .automatic) {
                    Picker("Unit", selection: $selectedUnit) {
                        Text("mm").tag(UnitLength.millimeters)
                        Text("cm").tag(UnitLength.centimeters)
                        Text("m").tag(UnitLength.meters)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 150)
                }
                ToolbarItemGroup(placement: .automatic) {
                    Picker("Rotation", selection: $selectedRotation) {
                        ForEach(RotationAngle.allCases) { angle in
                            Text(angle.description).tag(angle)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                    .onChange(of: selectedRotation) { newAngle in
                        depthImage.applyManualRotation(angle: newAngle)
                    }
                }
                ToolbarItemGroup(placement: .status) {
                    HStack {
                        Text("Opacity")
                        Slider(value: $overlayOpacity, in: 0...1)
                            .frame(width: 100)
                        Text(String(format: "%.0f%%", overlayOpacity * 100))
                    }
                }
            }
        }

    func handleMouseHover(at location: CGPoint, in viewSize: CGSize) {
        let imageWidth = depthImage.width
        let imageHeight = depthImage.height
        let imageSize = CGSize(width: imageWidth, height: imageHeight)

        // Calculate aspect ratios
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        // Determine how the image fits into the view
        var displayedImageSize = CGSize.zero
        if imageAspect > viewAspect {
            // Image is wider than the view
            displayedImageSize.width = viewSize.width
            displayedImageSize.height = viewSize.width / imageAspect
        } else {
            // Image is taller than the view
            displayedImageSize.height = viewSize.height
            displayedImageSize.width = viewSize.height * imageAspect
        }

        // Calculate scaling factors
        let scaleX = imageSize.width / displayedImageSize.width
        let scaleY = imageSize.height / displayedImageSize.height

        // Calculate offsets
        let offsetX = (viewSize.width - displayedImageSize.width) / 2
        let offsetY = (viewSize.height - displayedImageSize.height) / 2

        // Convert the location in the view to image coordinates
        let localX = location.x - offsetX
        let localY = location.y - offsetY

        // Check if the touch is within the displayed image
        if localX >= 0 && localX <= displayedImageSize.width && localY >= 0 && localY <= displayedImageSize.height {
            // Map the local touch point to image pixel coordinates
            var x = Int(localX * scaleX)
            var y = Int((displayedImageSize.height - localY) * scaleY) // Flip y-axis

            // Map coordinates based on rotation angle
            (x, y) = mapCoordinates(x: x, y: y, width: imageWidth, height: imageHeight, angle: selectedRotation)

            if let depth = depthImage.depthAt(x: x, y: y) {
                depthValue = depth
                mouseLocation = location
            } else {
                depthValue = nil
            }
        } else {
            depthValue = nil
        }
    }

    func openColorImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.image] // Allow all image types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                depthImage.loadColorImage(url: url)
            }
        }
    }

    func openDepthFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                depthImage.loadDepthTIFF(url: url)
            }
        }
    }

    func convertDepth(_ depthInMeters: Float, to unit: UnitLength) -> Float {
        switch unit {
        case .millimeters:
            return depthInMeters * 1000
        case .centimeters:
            return depthInMeters * 100
        case .meters:
            return depthInMeters
        default:
            return depthInMeters
        }
    }
    
    func mapCoordinates(x: Int, y: Int, width: Int, height: Int, angle: RotationAngle) -> (Int, Int) {
        switch angle {
        case .degrees0:
            return (x, y)
        case .degrees90:
            return (height - y - 1, x)
        case .degrees180:
            return (width - x - 1, height - y - 1)
        case .degrees270:
            return (y, width - x - 1)
        }
    }

    func symbolForUnit(_ unit: UnitLength) -> String {
        switch unit {
        case .millimeters:
            return "mm"
        case .centimeters:
            return "cm"
        case .meters:
            return "m"
        default:
            return "m"
        }
    }
}
