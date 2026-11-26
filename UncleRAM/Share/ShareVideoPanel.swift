import AVKit
import SwiftUI

/// 共有のプレビューの「動画」の見本。できあがるまでは結果の場面の 1 コマを、できあがったら動画そのものを出す
struct ShareVideoPreview: View {
    let export: ShareVideoExport
    /// リプレイの中身。記録の無い結果は nil（明細書だけを出す）
    let script: ReplayScript?
    let content: TributeStatementContent
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    @State private var player: AVPlayer?

    var body: some View {
        let size = ReplayVideoFrame.format.canvasSize
        let scale = max(0.1, min(1, maxWidth / size.width, maxHeight / size.height))
        Group {
            if let player, export.video != nil {
                ReplayPlayerView(player: player)
                    .accessibilityLabel(Text("リプレイ動画"))
            } else {
                poster
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("リプレイ動画のプレビュー"))
            }
        }
        .frame(width: size.width * scale, height: size.height * scale)
        .overlay { Rectangle().strokeBorder(Theme.navy.opacity(0.4), lineWidth: 1) }
        .task(id: export.video?.url) {
            player = export.video.map { AVPlayer(url: $0.url) }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    /// 結果の場面の 1 コマ（記録が無いときは明細書）
    @ViewBuilder private var poster: some View {
        if let script {
            let timeline = ReplayTimeline(script: script)
            let index = Int((timeline.endCardStart - 0.2) * Double(ReplayTimeline.framesPerSecond))
            ReplayVideoFrame(script: script, frame: timeline.frame(at: index), speed: timeline.speed, content: content)
        } else {
            ReplayEndCard(content: content)
        }
    }
}

/// 共有のプレビューの「動画」の操作（作る・中止・共有する・動画を保存）
struct ShareVideoControls: View {
    let export: ShareVideoExport
    /// 記録があるか。無い結果（記録する前に開いたものなど）は動画にできない
    let isAvailable: Bool
    /// 共有シートに、動画と一緒に渡す文面
    let caption: String
    let onStart: () -> Void
    /// 保存のあとに出す一言
    let announce: (String) -> Void

    #if os(macOS)
    @State private var exportsVideo = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isAvailable {
                Text("この結果は動画にできません")
                    .scaledFont(.mincho(14))
                    .foregroundStyle(Theme.subText)
            } else {
                switch export.state {
                case .idle, .failed:
                    if export.state == .failed {
                        Text("動画を作れませんでした")
                            .scaledFont(.mincho(14))
                            .foregroundStyle(Theme.red)
                    }
                    PrimaryInkButton(title: "動画を作る", fontSize: 18, verticalPadding: 16, action: onStart)
                case let .exporting(progress):
                    progressView(progress)
                case let .ready(video):
                    ShareLink(
                        item: ShareVideoFile(url: video.url),
                        message: Text(caption),
                        preview: SharePreview("リプレイ動画", image: Image(.hatHalftone))
                    ) {
                        PrimaryInkLabel(title: "共有する…", fontSize: 18, verticalPadding: 16)
                    }
                    .buttonStyle(.plain)
                    RuleButton(title: "動画を保存") { save(video) }
                    Text("動画ができました（\(seconds(video.duration)) 秒）")
                        .scaledFont(.mincho(13))
                        .foregroundStyle(Theme.subText)
                }
            }
        }
        #if os(macOS)
        .fileExporter(
            isPresented: $exportsVideo,
            item: export.video.map { ShareVideoFile(url: $0.url) },
            contentTypes: [.mpeg4Movie],
            defaultFilename: ReplayVideoFiles.fileName
        ) { result in
            switch result {
            case .success:
                announce(String(localized: "動画を保存しました"))
            case .failure:
                announce(String(localized: "動画を保存できませんでした"))
            }
        }
        #endif
    }

    private func progressView(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("動画を作っています")
                    .scaledFont(.mincho(15))
                Spacer()
                Text(verbatim: "\(Int((progress * 100).rounded(.down)))%")
                    .font(Theme.display(17))
                    .monospacedDigit()
            }
            ProgressBar(progress: progress)
                .frame(height: 14)
                .accessibilityHidden(true)
            RuleButton(title: "中止") { export.discard() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: "\(Int((progress * 100).rounded(.down)))%"))
    }

    private func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func save(_ video: ReplayVideo) {
        #if os(macOS)
        exportsVideo = true
        #else
        Task {
            do {
                try await PhotoLibrarySaver.save(videoAt: video.url)
                announce(String(localized: "写真に保存しました"))
            } catch PhotoLibrarySaver.Failure.denied {
                announce(String(localized: "写真への追加が許可されていません。設定アプリの「Uncle RAM」から許可できます。"))
            } catch {
                announce(String(localized: "動画を保存できませんでした"))
            }
        }
        #endif
    }
}

/// 進み具合の帯（献上のゲージと同じ、赤い斜線の帯）
private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                InkSurface()
                StripedInk()
                    .frame(width: max(0, proxy.size.width - 4) * min(max(progress, 0), 1))
                    .padding(2)
            }
            .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
        }
    }
}

extension View {
    /// 「動画」を選んだら作り始め、中身（端末の表示）が変わったら作り直す。バックグラウンドに移ったら作るのを止め、
    /// 共有のプレビューを閉じたら作った動画を消す（docs/SPEC.md「実装の詳細」の「リプレイ動画」）
    func shareVideoLifecycle(
        export: ShareVideoExport,
        isSelected: Bool,
        isAvailable: Bool,
        key: String,
        start: @escaping () -> Void
    ) -> some View {
        modifier(ShareVideoLifecycle(export: export, isSelected: isSelected, isAvailable: isAvailable, key: key, start: start))
    }
}

private struct ShareVideoLifecycle: ViewModifier {
    let export: ShareVideoExport
    let isSelected: Bool
    /// 記録があるか（結果が出た直後に開いたときは、記録が届くのが少し後になる）
    let isAvailable: Bool
    let key: String
    let start: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: isSelected && isAvailable, initial: true) { _, ready in
                if ready, export.state == .idle {
                    start()
                }
            }
            .onChange(of: key) { _, key in
                // 機種名を隠したら、機種名の入った動画を残さないよう作り直す（作っている途中でも）
                guard export.key != nil, export.key != key else {
                    return
                }
                export.discard()
                if isSelected {
                    start()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    export.cancelExport()
                }
            }
            .onDisappear {
                export.discard()
            }
    }
}

/// 動画の見本の再生（OS の再生の部品）。SwiftUI の `VideoPlayer` は、Mac で AVKit が読み込まれずに落ちることがあったので
/// （`AVPlayerView` を直接使わないと、AVKit がアプリに結び付けられない）、AVKit の部品をそのまま置く
#if os(macOS)
private struct ReplayPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
#else
private struct ReplayPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.videoGravity = .resizeAspect
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
#endif
