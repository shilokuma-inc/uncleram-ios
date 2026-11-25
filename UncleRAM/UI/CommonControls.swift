import SwiftUI

/// インク（既定は赤）の主ボタン（「献上をはじめる」「もう一度献上する」など）。紺の細い枠で囲む
struct PrimaryInkButton: View {
    let title: LocalizedStringKey
    /// ボタンの中で、題の右に小さく添える文字（Mac のタイトルの「速達便 · 約 20 秒」）
    var caption: LocalizedStringKey?
    var fontSize: CGFloat = 20
    var verticalPadding: CGFloat = 22
    /// インクの色。回収演出の「結果を見る」は、デザインどおり紺にする
    var color: Color = Theme.red
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryInkLabel(title: title, caption: caption, fontSize: fontSize, verticalPadding: verticalPadding, color: color)
        }
        .buttonStyle(.plain)
    }
}

/// `PrimaryInkButton` の見た目。`ShareLink` のようにボタンを自分で作る部品の label に使う
struct PrimaryInkLabel: View {
    let title: LocalizedStringKey
    var caption: LocalizedStringKey?
    var fontSize: CGFloat = 20
    var verticalPadding: CGFloat = 22
    var color: Color = Theme.red

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .scaledFont(.mincho(fontSize, .extraBold))
                .tracking(fontSize * 0.2)
            if let caption {
                Text(caption)
                    .scaledFont(.mincho(13))
                    .tracking(1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(Theme.lightPaper)
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
        .background { InkSurface(color: color) }
        .padding(6)
        .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
        .contentShape(Rectangle())
    }
}

/// 上下を二重線で挟んだボタン（デザインの「もう一度献上する」「画像を保存」など、主ボタンの下に並べるもの）
struct RuleButton: View {
    let title: LocalizedStringKey
    var fontSize: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RuleButtonLabel(title: title, fontSize: fontSize)
        }
        .buttonStyle(.plain)
    }
}

/// `RuleButton` の見た目
struct RuleButtonLabel: View {
    let title: LocalizedStringKey
    var fontSize: CGFloat = 15

    var body: some View {
        Text(title)
            .scaledFont(.mincho(fontSize))
            .tracking(fontSize * 0.14)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Theme.navy)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { DoubleRule() }
            .overlay(alignment: .bottom) { DoubleRule() }
            .contentShape(Rectangle())
    }
}

/// 紺の二重の横線（1pt の線を 1pt あけて 2 本。デザインの `3px double`）
struct DoubleRule: View {
    var body: some View {
        VStack(spacing: 1) {
            Rectangle().frame(height: 1)
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(Theme.navy)
        .accessibilityHidden(true)
    }
}

/// 下線つきの文字のリンク（「設定」「タイトルへ」など）
struct TextLink: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .scaledFont(.mincho(14))
                .underline()
                .foregroundStyle(Theme.navy)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 募兵ポスター風の「I WANT YOUR RAM」（指差す手・見出し・副題）。タイトルと、Mac のラウンド画面の左に置く
struct RecruitPoster: View {
    /// 指差す手の絵の高さ。画面の高さに合わせて縮められるよう、下限と上限で渡す
    var imageHeight: ClosedRange<CGFloat> = 300...300
    var headlineSize: CGFloat = 34
    /// タイトル画面では「NEAREST ALLOCATION STATION」も添える
    var showsStation = false

    var body: some View {
        VStack(spacing: 0) {
            Image(.handHalftone)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                // 指差す手は絵の上のほうにあるので、横長に切り抜くときも上に合わせる
                .frame(minHeight: imageHeight.lowerBound, maxHeight: imageHeight.upperBound, alignment: .top)
                .clipped()
                .allowsHitTesting(false)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.navy).frame(height: 1.5)
                }
                .accessibilityHidden(true)
            Text(verbatim: "I WANT")
                .font(Theme.display(headlineSize))
                .padding(.top, 8)
            Text(verbatim: "YOUR RAM")
                .font(Theme.display(headlineSize))
                .foregroundStyle(Theme.red)
            Text("あなたの RAM が必要だ")
                .scaledFont(.mincho(12))
                .tracking(1.4)
                .foregroundStyle(Theme.subText)
                .padding(.top, 4)
            if showsStation {
                Text(verbatim: "NEAREST ALLOCATION STATION")
                    .font(Theme.display(11))
                    .tracking(1.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background { InkSurface() }
        .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 3) }
        .padding(7)
        .overlay { Rectangle().strokeBorder(Theme.red, lineWidth: 3) }
    }
}

/// 社名と社是（帽子・「ALLOCATE CORP.」・「全人類の RAM を、ひとつの AI に。」）
struct CorporateMasthead: View {
    var hatSize = CGSize(width: 44, height: 29)
    var fontSize: CGFloat = 14

    var body: some View {
        // 1 行に入らないときは文字を少し縮め、それでも入らないとき（Dynamic Type で大きくしたときなど）は社是を 2 行目に送る（切らない）
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                hat
                corporateName(fontSize)
                motto(fontSize)
            }
            HStack(spacing: 8) {
                hat
                corporateName(fontSize * 0.85)
                motto(fontSize * 0.85)
            }
            HStack(spacing: 14) {
                hat
                VStack(alignment: .leading, spacing: 2) {
                    corporateName(fontSize)
                    motto(fontSize)
                }
            }
        }
    }

    private var hat: some View {
        Image(.hatHalftone)
            .resizable()
            .scaledToFit()
            .frame(width: hatSize.width, height: hatSize.height)
            .accessibilityHidden(true)
    }

    private func corporateName(_ size: CGFloat) -> some View {
        Text(verbatim: "ALLOCATE CORP.")
            .scaledFont(.typewriter(size))
            .tracking(1.1)
            .lineLimit(1)
    }

    private func motto(_ size: CGFloat) -> some View {
        Text("全人類の RAM を、ひとつの AI に。")
            .scaledFont(.mincho(size))
            .tracking(0.5)
            .foregroundStyle(Theme.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}
