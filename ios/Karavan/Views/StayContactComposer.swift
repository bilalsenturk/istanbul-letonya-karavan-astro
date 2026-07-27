import MessageUI
import SwiftUI

enum StayContactAvailability: Equatable {
    case available
    case unavailable
}

struct MessageComposerSheet: UIViewControllerRepresentable {
    let action: PreparedContactAction
    let onResult: (StayContactComposerResult) -> Void

    static var availability: StayContactAvailability {
        MFMessageComposeViewController.canSendText() ? .available : .unavailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = [action.recipient]
        controller.body = action.body
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        private let onResult: (StayContactComposerResult) -> Void
        private var finished = false

        init(onResult: @escaping (StayContactComposerResult) -> Void) {
            self.onResult = onResult
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            guard !finished else { return }
            finished = true
            let mapped: StayContactComposerResult
            switch result {
            case .sent: mapped = .sent
            case .failed: mapped = .failed
            case .cancelled: mapped = .cancelled
            @unknown default: mapped = .failed
            }
            controller.dismiss(animated: true) { [onResult] in onResult(mapped) }
        }
    }
}

struct MailComposerSheet: UIViewControllerRepresentable {
    let action: PreparedContactAction
    let onResult: (StayContactComposerResult) -> Void

    static var availability: StayContactAvailability {
        MFMailComposeViewController.canSendMail() ? .available : .unavailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([action.recipient])
        controller.setSubject(action.subject ?? "")
        controller.setMessageBody(action.body, isHTML: false)
        // Do not set a sender: the system composer keeps its From-account selector available.
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onResult: (StayContactComposerResult) -> Void
        private var finished = false

        init(onResult: @escaping (StayContactComposerResult) -> Void) {
            self.onResult = onResult
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            guard !finished else { return }
            finished = true
            let mapped: StayContactComposerResult
            switch result {
            case .sent: mapped = .sent
            case .failed: mapped = .failed
            case .cancelled, .saved: mapped = .cancelled
            @unknown default: mapped = .failed
            }
            controller.dismiss(animated: true) { [onResult] in onResult(mapped) }
        }
    }
}

struct ActiveStayContactComposer: Identifiable {
    let id = UUID()
    let action: PreparedContactAction
}
