import SwiftUI

struct ReceiptCropEditorView: View {
    let image: UIImage
    @Binding var quadrilateral: ReceiptQuadrilateral
    let isDetecting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let imageFrame = fittedImageFrame(for: image.size, in: geometry.size)

                ZStack {
                    // A photo editor reads best on black regardless of appearance.
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    CropOverlayView(quadrilateral: $quadrilateral, imageFrame: imageFrame)

                    if isDetecting {
                        VStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Detecting receipt edges")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use Crop", action: onConfirm)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func fittedImageFrame(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let scale = min(widthScale, heightScale)

        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )

        return CGRect(origin: origin, size: fittedSize)
    }
}

struct CropOverlayView: View {
    @Binding var quadrilateral: ReceiptQuadrilateral
    let imageFrame: CGRect

    private let minimumHorizontalGap: CGFloat = 0.14
    private let minimumVerticalGap: CGFloat = 0.18
    @State private var dragStartQuadrilateral: ReceiptQuadrilateral?

    var body: some View {
        let topLeft = pointInImageFrame(quadrilateral.topLeft)
        let topRight = pointInImageFrame(quadrilateral.topRight)
        let bottomRight = pointInImageFrame(quadrilateral.bottomRight)
        let bottomLeft = pointInImageFrame(quadrilateral.bottomLeft)
        let polygon = [topLeft, topRight, bottomRight, bottomLeft]

        ZStack {
            Path { path in
                path.addRect(imageFrame)
                path.addLines(polygon + [topLeft])
                path.closeSubpath()
            }
            .fill(
                Color.black.opacity(0.5),
                style: FillStyle(eoFill: true)
            )

            Path { path in
                path.addLines(polygon + [topLeft])
            }
                .stroke(.white, lineWidth: 2)

            cropHandle(.topLeft, position: topLeft)
            cropHandle(.topRight, position: topRight)
            cropHandle(.bottomRight, position: bottomRight)
            cropHandle(.bottomLeft, position: bottomLeft)
        }
    }

    private func pointInImageFrame(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageFrame.minX + point.x * imageFrame.width,
            y: imageFrame.minY + (1 - point.y) * imageFrame.height
        )
    }

    private func cropHandle(_ corner: CropCorner, position: CGPoint) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        moveCorner(corner, translation: value.translation)
                    }
                    .onEnded { _ in
                        dragStartQuadrilateral = nil
                    }
            )
    }

    private func moveCorner(_ corner: CropCorner, translation: CGSize) {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }
        let startQuadrilateral = dragStartQuadrilateral ?? quadrilateral
        if dragStartQuadrilateral == nil {
            dragStartQuadrilateral = startQuadrilateral
        }

        let updatedPoint = CGPoint(
            x: min(max(startQuadrilateral[corner].x + (translation.width / imageFrame.width), 0.02), 0.98),
            y: min(max(startQuadrilateral[corner].y - (translation.height / imageFrame.height), 0.02), 0.98)
        )

        var updatedQuadrilateral = startQuadrilateral
        updatedQuadrilateral[corner] = updatedPoint
        quadrilateral = constrained(updatedQuadrilateral)
    }

    private func constrained(_ quad: ReceiptQuadrilateral) -> ReceiptQuadrilateral {
        var result = quad

        result.topLeft.x = clamp(result.topLeft.x, min: 0.02, max: result.topRight.x - minimumHorizontalGap)
        result.bottomLeft.x = clamp(result.bottomLeft.x, min: 0.02, max: result.bottomRight.x - minimumHorizontalGap)

        result.topRight.x = clamp(result.topRight.x, min: result.topLeft.x + minimumHorizontalGap, max: 0.98)
        result.bottomRight.x = clamp(result.bottomRight.x, min: result.bottomLeft.x + minimumHorizontalGap, max: 0.98)

        result.topLeft.y = clamp(result.topLeft.y, min: result.bottomLeft.y + minimumVerticalGap, max: 0.98)
        result.topRight.y = clamp(result.topRight.y, min: result.bottomRight.y + minimumVerticalGap, max: 0.98)

        result.bottomLeft.y = clamp(result.bottomLeft.y, min: 0.02, max: result.topLeft.y - minimumVerticalGap)
        result.bottomRight.y = clamp(result.bottomRight.y, min: 0.02, max: result.topRight.y - minimumVerticalGap)

        return result
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

enum CropCorner {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

extension ReceiptQuadrilateral {
    subscript(corner: CropCorner) -> CGPoint {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomRight: bottomRight
            case .bottomLeft: bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }
}
