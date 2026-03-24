import SwiftUI

struct GameLogCaptureEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var frontPhotoData: Data?
    @State private var backPhotoData: Data?
    @State private var showDualCapture = false
    @State private var hasStartedCapture = false

    private var hasBothPhotos: Bool {
        frontPhotoData != nil && backPhotoData != nil
    }

    var body: some View {
        Group {
            if hasBothPhotos {
                GameLogView(frontPhotoData: frontPhotoData, backPhotoData: backPhotoData)
            } else {
                ProgressView("Opening camera…")
                .navigationTitle("Capture Game Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showDualCapture) {
            DualCameraCaptureView(
                onCaptured: { front, back in
                    frontPhotoData = front
                    backPhotoData = back
                    showDualCapture = false
                },
                onCancel: {
                    showDualCapture = false
                    dismiss()
                }
            )
            .ignoresSafeArea()
        }
        .onAppear {
            guard !hasStartedCapture else { return }
            hasStartedCapture = true
            showDualCapture = true
        }
    }
}
