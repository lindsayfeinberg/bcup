import SwiftUI
import UIKit

enum CameraLens: Identifiable {
    case front
    case back

    var id: String {
        switch self {
        case .front: return "front"
        case .back: return "back"
        }
    }
}

struct CaptureRequest: Identifiable {
    let lens: CameraLens
    let forcePhotoLibrary: Bool

    var id: String {
        "\(lens.id)-\(forcePhotoLibrary ? "library" : "camera")"
    }
}

struct GameLogCaptureEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var frontPhotoData: Data?
    @State private var backPhotoData: Data?
    @State private var activeCaptureRequest: CaptureRequest?

    private var hasBothPhotos: Bool {
        frontPhotoData != nil && backPhotoData != nil
    }

    private var captureLabelPrefix: String {
        UIImagePickerController.isSourceTypeAvailable(.camera) ? "Capture" : "Select"
    }

    var body: some View {
        Group {
            if hasBothPhotos {
                GameLogView(frontPhotoData: frontPhotoData, backPhotoData: backPhotoData)
            } else {
                VStack(spacing: 16) {
                    Text(UIImagePickerController.isSourceTypeAvailable(.camera) ?
                         "Capture both photos to continue" :
                         "Select both photos to continue")
                        .font(.headline)

                    HStack(spacing: 12) {
                        photoPreview(data: frontPhotoData, title: "Front")
                        photoPreview(data: backPhotoData, title: "Back")
                    }

                    Button(frontPhotoData == nil ? "\(captureLabelPrefix) Front" : "Retake Front") {
                        activeCaptureRequest = CaptureRequest(lens: .front, forcePhotoLibrary: false)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(backPhotoData == nil ? "\(captureLabelPrefix) Back" : "Retake Back") {
                        activeCaptureRequest = CaptureRequest(lens: .back, forcePhotoLibrary: false)
                    }
                    .buttonStyle(.borderedProminent)

                    // Explicit simulator-friendly actions.
                    HStack(spacing: 12) {
                        Button("Select Front") {
                            activeCaptureRequest = CaptureRequest(lens: .front, forcePhotoLibrary: true)
                        }
                        .buttonStyle(.bordered)

                        Button("Select Back") {
                            activeCaptureRequest = CaptureRequest(lens: .back, forcePhotoLibrary: true)
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }
                .padding()
                .navigationTitle("Capture Game Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .sheet(item: $activeCaptureRequest) { request in
            CameraCapturePicker(lens: request.lens, forcePhotoLibrary: request.forcePhotoLibrary) { data in
                switch request.lens {
                case .front:
                    frontPhotoData = data
                case .back:
                    backPhotoData = data
                }
            }
        }
    }

    @ViewBuilder
    private func photoPreview(data: Data?, title: String) -> some View {
        VStack(spacing: 8) {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                    .frame(width: 150, height: 210)
                    .overlay(Text("No photo").foregroundStyle(.secondary))
            }
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct CameraCapturePicker: UIViewControllerRepresentable {
    let lens: CameraLens
    let forcePhotoLibrary: Bool
    let onCaptured: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        if forcePhotoLibrary {
            picker.sourceType = .photoLibrary
        } else {
            picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        }
        if picker.sourceType == .camera {
            picker.cameraDevice = (lens == .front) ? .front : .rear
            picker.cameraCaptureMode = .photo
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCapturePicker

        init(_ parent: CameraCapturePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.dismiss() }
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85) else {
                return
            }
            parent.onCaptured(data)
        }
    }
}

