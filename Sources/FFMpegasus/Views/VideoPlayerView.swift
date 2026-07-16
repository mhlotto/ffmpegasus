import AVFoundation
import SwiftUI

struct VideoPlayerView: View {
    let player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Open a video file")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 360)
        .background(Color(nsColor: .black))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class PlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
