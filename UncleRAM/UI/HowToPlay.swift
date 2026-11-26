import SwiftUI

/// 「?」から開く、絵だけの遊び方の 3 コマ（押す → 兆しを見る → 離す）。iPhone は docs/design/Help.png、Mac は MacHelp.png。
/// 読まなくても遊べる前提なので、強制しない（docs/SPEC.md「説明なしで分かる UI」の「いつでも見られる説明」）
struct HowToPlayOverlay: View {
    /// 下の画面の組み方。Mac と広い iPad では 3 コマを横に並べる。iPad では下の画面と同じだけ拡大する
    let layout: ScreenLayout
    /// 下の画面の大きさ
    let size: CGSize
    let onClose: () -> Void

    private var wide: Bool {
        layout.isWide
    }

    var body: some View {
        ZStack {
            Theme.navy.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            ScrollView {
                sheet
                    .padding(.horizontal, wide ? 36 : 20)
                    .padding(.vertical, 40)
                    .frame(maxWidth: wide ? 1_000 : 420)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
            .scaledToLayout(layout, in: size)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("遊び方")
                    .scaledFont(.mincho(22, .extraBold))
                    .tracking(3)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onClose) {
                    Text(verbatim: "×")
                        .font(Theme.display(26))
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text("閉じる"))
            }
            if wide {
                // 3 枚の札の高さをそろえる（いちばん高い札に合わせる）
                HStack(alignment: .top, spacing: 18) {
                    panels
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 14) {
                    panels
                }
            }
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background { InkSurface() }
        .shadow(color: Theme.navy.opacity(0.25), radius: 18, y: 8)
    }

    @ViewBuilder private var panels: some View {
        HowToPlayPanel(number: 1, wide: wide) {
            PressPicture()
        } caption: {
            PressCaption()
        }
        HowToPlayPanel(number: 2, wide: wide) {
            SignPicture()
        } caption: {
            SignCaption()
        }
        HowToPlayPanel(number: 3, wide: wide) {
            ReleasePicture()
        } caption: {
            ReleaseCaption()
        }
    }
}

/// 1 コマ（番号・絵・見出し）。紺の二重の枠で囲む。
/// Mac と広い iPad は絵の下に見出し（MacHelp.png）、iPhone は絵の右に見出し（Help.png）
private struct HowToPlayPanel<Picture: View, Caption: View>: View {
    let number: Int
    let wide: Bool
    @ViewBuilder let picture: Picture
    @ViewBuilder let caption: Caption

    var body: some View {
        Group {
            if wide {
                VStack(spacing: 12) {
                    picture
                        .frame(height: 120)
                    caption
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 22)
            } else {
                HStack(spacing: 14) {
                    picture
                        .frame(width: 110, height: 100)
                    caption
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 18)
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .topLeading) {
            Text(verbatim: "\(number)")
                .font(Theme.display(14))
                .padding(12)
                .accessibilityHidden(true)
        }
        .doubleFrame()
        .accessibilityElement(children: .combine)
    }
}

/// 赤いインクの丸（長押しのボタンの絵）
private struct InkButtonPicture: View {
    var diameter: CGFloat = 76

    var body: some View {
        InkSurface(color: Theme.red)
            .clipShape(Circle())
            .frame(width: diameter, height: diameter)
            .padding(diameter * 0.04)
            .overlay { Circle().strokeBorder(Theme.navy, lineWidth: 2) }
            .accessibilityHidden(true)
    }
}

/// 上下の矢印（押す ↓ / 離す ↑）
private struct ArrowPicture: View {
    let down: Bool

    var body: some View {
        Image(systemName: down ? "arrow.down" : "arrow.up")
            .font(.system(size: 26, weight: .semibold))
            .accessibilityHidden(true)
    }
}

private struct PressPicture: View {
    var body: some View {
        VStack(spacing: 4) {
            ArrowPicture(down: true)
            InkButtonPicture()
        }
    }
}

private struct PressCaption: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("押す")
                .scaledFont(.mincho(22, .extraBold))
                .tracking(4)
            #if os(macOS)
            HStack(spacing: 8) {
                Text(verbatim: "space")
                    .scaledFont(.typewriter(13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
                Text("でも")
                    .scaledFont(.mincho(13))
            }
            #else
            DonationGauge(fill: 0.4, safetyLine: 0.85, height: 16, showsSafetyLabel: false)
                .frame(width: 130)
            Text("▲ 押すほど増える")
                .scaledFont(.mincho(13))
            #endif
        }
    }
}

private struct SignPicture: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ChairmanHat(leaning: true, size: CGSize(width: 84, height: 56))
                .padding(.top, 34)
                .padding(.trailing, 30)
            Image(.airshipHalftone)
                .resizable()
                .scaledToFit()
                .frame(width: 64)
                .accessibilityHidden(true)
        }
    }
}

private struct SignCaption: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("兆しを見る")
                .scaledFont(.mincho(22, .extraBold))
                .tracking(4)
            HintIndicator(stage: .approach)
            Text("表情 → 音 → ノイズ")
                .scaledFont(.mincho(13))
        }
    }
}

private struct ReleasePicture: View {
    @Environment(LocalStore.self) private var store: LocalStore?

    var body: some View {
        VStack(spacing: 4) {
            ArrowPicture(down: store?.tapToDonate == true)
            InkButtonPicture()
        }
    }
}

private struct ReleaseCaption: View {
    @Environment(LocalStore.self) private var store: LocalStore?

    var body: some View {
        VStack(spacing: 8) {
            // タップで献上のときは、離しても納品しないので「もう一度押す」にする
            Text(store?.tapToDonate == true ? "もう一度押す" : "離す")
                .scaledFont(.mincho(22, .extraBold))
                .tracking(4)
            CircleStamp(text: "納品", diameter: 64)
        }
    }
}

/// ラウンドの画面とタイトルの右上に置く「?」（docs/design/Tutorial.png の、紺の丸の中の ?）
struct HowToPlayButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "?")
                .scaledFont(.typewriter(12))
                .foregroundStyle(Theme.subText)
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(Theme.navy, lineWidth: 1.5) }
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("遊び方"))
    }
}
