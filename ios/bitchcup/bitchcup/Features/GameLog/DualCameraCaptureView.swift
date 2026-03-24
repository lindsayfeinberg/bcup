import AVFoundation
import SwiftUI
import UIKit

// MARK: - SwiftUI entry

/// Camera-only: live dual preview + one shutter when multi-cam is supported; otherwise back-then-front with `UIImagePickerController` (no photo library).
struct DualCameraCaptureView: View {
    let onCaptured: (Data, Data) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            DualCameraPickerRepresentable(onCaptured: onCaptured, onCancel: onCancel)
                .ignoresSafeArea()

            Button("Cancel") {
                onCancel()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.leading, 16)
            .padding(.top, 56)
        }
    }
}

// MARK: - UIViewControllerRepresentable

private struct DualCameraPickerRepresentable: UIViewControllerRepresentable {
    let onCaptured: (Data, Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> DualCameraContainerController {
        DualCameraContainerController(onCaptured: onCaptured, onCancel: onCancel)
    }

    func updateUIViewController(_ uiViewController: DualCameraContainerController, context: Context) {}
}

// MARK: - Container

final class DualCameraContainerController: UIViewController {
    private let onCaptured: (Data, Data) -> Void
    private let onCancel: () -> Void

    init(onCaptured: @escaping (Data, Data) -> Void, onCancel: @escaping () -> Void) {
        self.onCaptured = onCaptured
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let child: UIViewController
        if AVCaptureMultiCamSession.isMultiCamSupported {
            child = DualMultiCamViewController(onCaptured: onCaptured, onCancel: onCancel)
        } else {
            child = SequentialCameraViewController(onCaptured: onCaptured, onCancel: onCancel)
        }

        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }
}

// MARK: - Multi-cam

final class DualMultiCamViewController: UIViewController {
    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "com.bcup.dualcam.session")
    private let backPhotoOutput = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()

    private let backPreview = AVCaptureVideoPreviewLayer()
    private let frontPreview = AVCaptureVideoPreviewLayer()

    private let shutterButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = .white
        b.layer.cornerRadius = 36
        b.layer.borderWidth = 4
        b.layer.borderColor = UIColor.lightGray.cgColor
        return b
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.textColor = .white
        l.font = .preferredFont(forTextStyle: .subheadline)
        l.textAlignment = .center
        l.numberOfLines = 2
        l.text = "Both cameras active — tap to capture"
        return l
    }()

    private let onCaptured: (Data, Data) -> Void
    private let onCancel: () -> Void
    private var captureState: DualPhotoCaptureState?

    init(onCaptured: @escaping (Data, Data) -> Void, onCancel: @escaping () -> Void) {
        self.onCaptured = onCaptured
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    deinit {
        let s = session
        sessionQueue.sync {
            if s.isRunning {
                s.stopRunning()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        backPreview.videoGravity = .resizeAspectFill
        frontPreview.videoGravity = .resizeAspectFill

        view.layer.addSublayer(backPreview)
        view.layer.addSublayer(frontPreview)

        view.addSubview(hintLabel)
        view.addSubview(shutterButton)
        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hintLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -16),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72)
        ])

        shutterButton.addTarget(self, action: #selector(didTapShutter), for: .touchUpInside)
        sessionQueue.async { self.configureSession() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backPreview.frame = view.bounds

        let pipWidth: CGFloat = min(140, view.bounds.width * 0.28)
        let pipHeight = pipWidth * 4 / 3
        let margin: CGFloat = 16
        frontPreview.frame = CGRect(
            x: view.bounds.maxX - pipWidth - margin,
            y: view.safeAreaInsets.top + margin,
            width: pipWidth,
            height: pipHeight
        )
        frontPreview.cornerRadius = 12
        frontPreview.masksToBounds = true
    }

    private func videoPort(from input: AVCaptureDeviceInput) -> AVCaptureInput.Port? {
        input.ports.first { $0.mediaType == .video }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // `AVCaptureMultiCamSession` does not support `.photo` on some devices/OS builds.
        // Keep the default preset and rely on `AVCapturePhotoOutput` for still capture.

        guard
            let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else {
            DispatchQueue.main.async { self.replaceWithSequential() }
            return
        }

        do {
            let bIn = try AVCaptureDeviceInput(device: backDevice)
            let fIn = try AVCaptureDeviceInput(device: frontDevice)

            guard session.canAddInput(bIn), session.canAddInput(fIn) else {
                DispatchQueue.main.async { self.replaceWithSequential() }
                return
            }
            session.addInputWithNoConnections(bIn)
            session.addInputWithNoConnections(fIn)

            guard session.canAddOutput(backPhotoOutput), session.canAddOutput(frontPhotoOutput) else {
                DispatchQueue.main.async { self.replaceWithSequential() }
                return
            }
            session.addOutputWithNoConnections(backPhotoOutput)
            session.addOutputWithNoConnections(frontPhotoOutput)

            guard let backPort = videoPort(from: bIn), let frontPort = videoPort(from: fIn) else {
                DispatchQueue.main.async { self.replaceWithSequential() }
                return
            }

            backPreview.setSessionWithNoConnection(session)
            frontPreview.setSessionWithNoConnection(session)

            let backPreviewConn = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backPreview)
            session.addConnection(backPreviewConn)

            let backPhotoConn = AVCaptureConnection(inputPorts: [backPort], output: backPhotoOutput)
            session.addConnection(backPhotoConn)

            let frontPreviewConn = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontPreview)
            session.addConnection(frontPreviewConn)

            let frontPhotoConn = AVCaptureConnection(inputPorts: [frontPort], output: frontPhotoOutput)
            session.addConnection(frontPhotoConn)
        } catch {
            DispatchQueue.main.async { self.replaceWithSequential() }
            return
        }

        sessionQueue.async {
            self.session.startRunning()
        }
    }

    private func replaceWithSequential() {
        guard let parent = parent else {
            onCancel()
            return
        }
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()

        let seq = SequentialCameraViewController(onCaptured: onCaptured, onCancel: onCancel)
        parent.addChild(seq)
        seq.view.frame = parent.view.bounds
        seq.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(seq.view)
        seq.didMove(toParent: parent)
    }

    @objc private func didTapShutter() {
        sessionQueue.async {
            guard self.session.isRunning else { return }

            // Each output needs its own settings instance for concurrent capture.
            let backSettings = AVCapturePhotoSettings()
            let frontSettings = AVCapturePhotoSettings()
            let state = DualPhotoCaptureState { [weak self] frontData, backData in
                guard let self, let f = frontData, let b = backData else { return }
                DispatchQueue.main.async {
                    self.onCaptured(f, b)
                }
            }
            self.captureState = state

            self.backPhotoOutput.capturePhoto(with: backSettings, delegate: state.backDelegate)
            self.frontPhotoOutput.capturePhoto(with: frontSettings, delegate: state.frontDelegate)
        }
    }
}

// MARK: - Dual photo delegates

private final class DualPhotoCaptureState: NSObject {
    private let lock = NSLock()
    private var frontJPEG: Data?
    private var backJPEG: Data?
    private let completion: (Data?, Data?) -> Void

    lazy var frontDelegate: DualPhotoDelegate = DualPhotoDelegate(owner: self, isFront: true)
    lazy var backDelegate: DualPhotoDelegate = DualPhotoDelegate(owner: self, isFront: false)

    init(completion: @escaping (Data?, Data?) -> Void) {
        self.completion = completion
    }

    fileprivate func deliver(front: Data?, back: Data?) {
        lock.lock()
        if let f = front { frontJPEG = f }
        if let b = back { backJPEG = b }
        let done = (frontJPEG != nil && backJPEG != nil)
        let fOut = frontJPEG
        let bOut = backJPEG
        lock.unlock()

        if done, let fOut, let bOut {
            completion(fOut, bOut)
        }
    }
}

private final class DualPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private weak var owner: DualPhotoCaptureState?
    private let isFront: Bool

    init(owner: DualPhotoCaptureState, isFront: Bool) {
        self.owner = owner
        self.isFront = isFront
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            AppDebugLog.log("DualPhotoDelegate error: \(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation() else { return }
        if isFront {
            owner?.deliver(front: data, back: nil)
        } else {
            owner?.deliver(front: nil, back: data)
        }
    }
}

// MARK: - Sequential camera-only fallback

final class SequentialCameraViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onCaptured: (Data, Data) -> Void
    private let onCancel: () -> Void
    private var backPhotoData: Data?
    private var mode: CaptureMode = .camera
    private var currentStep: Step = .back

    private enum CaptureMode {
        case camera
        case libraryFallback
    }

    private enum Step {
        case back
        case front
    }

    private let messageLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.textColor = .white
        l.textAlignment = .center
        l.numberOfLines = 0
        l.font = .preferredFont(forTextStyle: .title3)
        return l
    }()

    init(onCaptured: @escaping (Data, Data) -> Void, onCancel: @escaping () -> Void) {
        self.onCaptured = onCaptured
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            mode = .camera
            messageLabel.text = "Capture the back camera photo first."
        } else {
            mode = .libraryFallback
            messageLabel.text = "Camera unavailable. Select your back photo from library."
        }
        currentStep = .back
        presentPicker(for: currentStep)
    }

    private func presentPicker(for step: Step) {
        let picker = UIImagePickerController()
        picker.sourceType = (mode == .camera) ? .camera : .photoLibrary
        if mode == .camera {
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = (step == .front) ? .front : .rear
        }
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) {
            self.onCancel()
        }
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.85)
            else {
                self.onCancel()
                return
            }

            if self.backPhotoData == nil {
                self.backPhotoData = data
                self.currentStep = .front
                self.messageLabel.text = self.mode == .camera
                    ? "Now capture the front camera photo."
                    : "Now select your front photo from library."
                self.presentPicker(for: .front)
            } else if let back = self.backPhotoData {
                // `data` is front, `back` is rear — matches (front, back) for game log.
                self.onCaptured(data, back)
            } else {
                self.onCancel()
            }
        }
    }
}
