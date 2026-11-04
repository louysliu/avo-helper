import SwiftUI

struct CropEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onApply: (NormalizedCrop) -> Void
    @State private var crop: NormalizedCrop

    init(
        image: UIImage,
        initialCrop: NormalizedCrop,
        onApply: @escaping (NormalizedCrop) -> Void
    ) {
        self.image = image
        self.onApply = onApply
        _crop = State(initialValue: initialCrop)
    }

    var body: some View {
        VStack(spacing: 0) {
            CropCanvas(image: image, crop: $crop)
                .padding(16)

            HStack {
                Button {
                    crop = .full
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                }
                .disabled(crop.isFull)

                Spacer()

                Text("拖动边角或边缘调整裁剪范围")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .background(Color.black.opacity(0.92))
        .navigationTitle("裁剪")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    onApply(crop)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}

private struct CropCanvas: View {
    let image: UIImage
    @Binding var crop: NormalizedCrop
    @State private var dragState: CropDragState?

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = fittedFrame(in: proxy.size)
            let cropFrame = displayCropFrame(in: imageFrame)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                CropMask(cropFrame: cropFrame)
                    .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))

                CropGrid()
                    .stroke(.white.opacity(0.72), lineWidth: 0.7)
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)

                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)

                ForEach(CropHandle.allCases) { handle in
                    handleView(handle, cropFrame: cropFrame, imageFrame: imageFrame)
                }
            }
            .coordinateSpace(name: "cropCanvas")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("裁剪区域")
        }
    }

    private func fittedFrame(in availableSize: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(availableSize.width / image.size.width, availableSize.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (availableSize.width - size.width) / 2,
            y: (availableSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func displayCropFrame(in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + crop.x * imageFrame.width,
            y: imageFrame.minY + crop.y * imageFrame.height,
            width: crop.width * imageFrame.width,
            height: crop.height * imageFrame.height
        )
    }

    private func handleView(
        _ handle: CropHandle,
        cropFrame: CGRect,
        imageFrame: CGRect
    ) -> some View {
        CropHandleControl(handle: handle)
            .position(handle.position(in: cropFrame))
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("cropCanvas"))
                    .onChanged { value in
                        updateCrop(
                            handle: handle,
                            translation: value.translation,
                            imageFrame: imageFrame
                        )
                    }
                    .onEnded { _ in
                        dragState = nil
                    }
            )
            .accessibilityLabel(handle.accessibilityLabel)
            .accessibilityIdentifier("crop-handle-\(handle.rawValue)")
            .accessibilityAddTraits(.isButton)
    }

    private func updateCrop(handle: CropHandle, translation: CGSize, imageFrame: CGRect) {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }

        let startingCrop: NormalizedCrop
        if let dragState, dragState.handle == handle {
            startingCrop = dragState.startingCrop
        } else {
            startingCrop = crop
            dragState = CropDragState(handle: handle, startingCrop: crop)
        }

        let startingPosition = handle.position(in: startingCrop.rect)
        let point = CGPoint(
            x: startingPosition.x + translation.width / imageFrame.width,
            y: startingPosition.y + translation.height / imageFrame.height
        )
        crop = CropGeometry.updatedCrop(
            startingAt: startingCrop,
            moving: handle,
            to: point
        )
    }
}

private struct CropHandleControl: View {
    let handle: CropHandle

    var body: some View {
        Group {
            if handle.isCorner {
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                    .frame(width: 44, height: 44)
            } else if handle.isHorizontalEdge {
                Capsule()
                    .fill(.white)
                    .frame(width: 42, height: 6)
                    .frame(width: 52, height: 36)
            } else {
                Capsule()
                    .fill(.white)
                    .frame(width: 6, height: 42)
                    .frame(width: 36, height: 52)
            }
        }
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.35), radius: 3)
    }
}

private struct CropDragState {
    let handle: CropHandle
    let startingCrop: NormalizedCrop
}

enum CropGeometry {
    static func updatedCrop(
        startingAt crop: NormalizedCrop,
        moving handle: CropHandle,
        to location: CGPoint,
        minimumSize: CGFloat = 0.04
    ) -> NormalizedCrop {
        let start = crop.clamped(minimumSize: minimumSize).rect
        let point = CGPoint(
            x: min(max(location.x, 0), 1),
            y: min(max(location.y, 0), 1)
        )

        switch handle {
        case .topLeft:
            let left = min(point.x, start.maxX - minimumSize)
            let top = min(point.y, start.maxY - minimumSize)
            return NormalizedCrop(
                x: left,
                y: top,
                width: start.maxX - left,
                height: start.maxY - top
            )
        case .top:
            let top = min(point.y, start.maxY - minimumSize)
            return NormalizedCrop(
                x: start.minX,
                y: top,
                width: start.width,
                height: start.maxY - top
            )
        case .topRight:
            let right = max(point.x, start.minX + minimumSize)
            let top = min(point.y, start.maxY - minimumSize)
            return NormalizedCrop(
                x: start.minX,
                y: top,
                width: right - start.minX,
                height: start.maxY - top
            )
        case .right:
            let right = max(point.x, start.minX + minimumSize)
            return NormalizedCrop(
                x: start.minX,
                y: start.minY,
                width: right - start.minX,
                height: start.height
            )
        case .bottomLeft:
            let left = min(point.x, start.maxX - minimumSize)
            let bottom = max(point.y, start.minY + minimumSize)
            return NormalizedCrop(
                x: left,
                y: start.minY,
                width: start.maxX - left,
                height: bottom - start.minY
            )
        case .bottom:
            let bottom = max(point.y, start.minY + minimumSize)
            return NormalizedCrop(
                x: start.minX,
                y: start.minY,
                width: start.width,
                height: bottom - start.minY
            )
        case .bottomRight:
            let right = max(point.x, start.minX + minimumSize)
            let bottom = max(point.y, start.minY + minimumSize)
            return NormalizedCrop(
                x: start.minX,
                y: start.minY,
                width: right - start.minX,
                height: bottom - start.minY
            )
        case .left:
            let left = min(point.x, start.maxX - minimumSize)
            return NormalizedCrop(
                x: left,
                y: start.minY,
                width: start.maxX - left,
                height: start.height
            )
        }
    }
}

private struct CropMask: Shape {
    let cropFrame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cropFrame)
        return path
    }
}

private struct CropGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
            path.move(to: CGPoint(x: rect.width * fraction, y: 0))
            path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
            path.move(to: CGPoint(x: 0, y: rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        return path
    }
}

enum CropHandle: String, CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .topLeft: return "左上角裁剪手柄"
        case .top: return "上边缘裁剪手柄"
        case .topRight: return "右上角裁剪手柄"
        case .right: return "右边缘裁剪手柄"
        case .bottomRight: return "右下角裁剪手柄"
        case .bottom: return "下边缘裁剪手柄"
        case .bottomLeft: return "左下角裁剪手柄"
        case .left: return "左边缘裁剪手柄"
        }
    }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        case .top, .right, .bottom, .left: return false
        }
    }

    var isHorizontalEdge: Bool {
        self == .top || self == .bottom
    }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}
