import AVFoundation
import UIKit

enum CameraPermissionOutcome {
    case authorized
    case denied
    case restricted
    case cameraUnavailable
}

enum CameraPermissionCoordinator {
    static func ensureVideoPermission() async -> CameraPermissionOutcome {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .cameraUnavailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
