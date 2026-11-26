import SwiftUI

/// ランキングの画面。Game Center の順位を、明細書風の自前の画面で見せる（docs/SPEC.md「Game Center と名前の扱い」）。
/// デザインは無いので、設定と同じ紙と二重の枠でそろえる。サインインしていない人には、自分の最高記録とサインインの案内を出す
struct RankingScreen: View {
    let onClose: () -> Void

    @Environment(RankingCenter.self) private var ranking
    @State private var model: RankingBoardModel?

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Ornament()
                    if let model {
                        RankingBoard(model: model, isSignedIn: ranking.signIn.state == .signedIn)
                    }
                    personalBests
                    if ranking.signIn.state != .signedIn {
                        signInNotice
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Theme.navy)
        .preferredColorScheme(.light)
        .onAppear {
            let model = RankingBoardModel(ownClass: DeviceMemoryProfile.current.memoryClass) { [ranking] in
                ranking.signIn.state == .signedIn
            }
            self.model = model
            model.reload()
        }
        .onChange(of: ranking.signIn.state) { _, _ in
            model?.reload()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ランキング")
                .scaledFont(.mincho(22, .extraBold))
                .tracking(2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if ranking.signIn.state == .signedIn {
                TextLink(title: "Game Center で見る") {
                    GameCenterPresenter.showLeaderboards()
                }
            }
            TextLink(title: "閉じる", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
    }

    /// 自分の最高記録（端末の中だけ。サインインしていなくても見せる）
    private var personalBests: some View {
        let bests = ranking.personalBests
        return RankingPanel(title: "自分の最高記録") {
            bestRow("速達便", bests.express)
            DashedRule()
            bestRow("今日のデイリー", bests.daily(at: .now))
        }
    }

    private func bestRow(_ title: LocalizedStringKey, _ best: PersonalBests.Best?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .scaledFont(.mincho(15))
            Spacer()
            if let best {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(Formatters.integer(best.skillScore)) pt")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.red)
                    Text("献上量 \(Formatters.integer(best.donatedScore)) MB（\(best.memoryClass.title)）")
                        .scaledFont(.mincho(12, .medium))
                        .foregroundStyle(Theme.subText)
                }
            } else {
                Text("まだ記録がありません")
                    .scaledFont(.mincho(13, .medium))
                    .foregroundStyle(Theme.subText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var signInNotice: some View {
        RankingPanel(title: "Game Center") {
            Text(signInMessage)
                .scaledFont(.mincho(14, .medium))
                .fixedSize(horizontal: false, vertical: true)
            if ranking.signIn.state == .notStarted {
                PrimaryInkButton(title: "サインインする", fontSize: 16, verticalPadding: 12) {
                    ranking.startSignIn()
                }
            }
        }
    }

    private var signInMessage: LocalizedStringKey {
        switch ranking.signIn.state {
        case .notStarted, .needsSignInScreen:
            "Game Center にサインインすると、ランキングに参加できます。名前は Game Center のニックネームが出ます。"
        case .waiting:
            "Game Center に問い合わせています。"
        case .signedIn:
            ""
        case .signedOut:
            #if os(macOS)
            "Game Center にサインインしていないため、ランキングは見られません。システム設定の「Game Center」からサインインできます。遊ぶことはできます。"
            #else
            "Game Center にサインインしていないため、ランキングは見られません。設定アプリの「Game Center」からサインインできます。遊ぶことはできます。"
            #endif
        }
    }
}

/// 速達便・デイリー、腕前・献上量、クラス、全体・友だちを選び、順位を出す
private struct RankingBoard: View {
    @Bindable var model: RankingBoardModel
    let isSignedIn: Bool

    var body: some View {
        RankingPanel(title: "順位") {
            Picker("モード", selection: $model.mode) {
                Text("速達便").tag(RankingMode.express)
                Text("デイリー").tag(RankingMode.daily)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Picker("種類", selection: $model.category) {
                Text("腕前スコア").tag(RankingBoardModel.Category.skill)
                Text("献上量").tag(RankingBoardModel.Category.donated)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if model.category == .donated {
                Picker("クラス", selection: $model.memoryClass) {
                    ForEach(model.classChoices, id: \.self) { memoryClass in
                        Text(verbatim: memoryClass == model.ownClass ? "\(memoryClass.title)（この端末）" : memoryClass.title)
                            .tag(memoryClass)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Theme.navy)
            }
            Picker("範囲", selection: $model.scope) {
                Text("全体").tag(LeaderboardScope.global)
                Text("友だち").tag(LeaderboardScope.friends)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            DashedRule()
            rows
        }
    }

    @ViewBuilder private var rows: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        case .unavailable:
            Text(isSignedIn ? "ランキングを読めませんでした。少し待ってから、もう一度お試しください。" : "サインインすると、順位が見られます。")
                .scaledFont(.mincho(13, .medium))
                .foregroundStyle(Theme.subText)
                .fixedSize(horizontal: false, vertical: true)
        case let .loaded(page):
            if page.rows.isEmpty {
                Text("まだ誰も献上していません")
                    .scaledFont(.mincho(13, .medium))
                    .foregroundStyle(Theme.subText)
            }
            ForEach(page.rows) { row in
                RankingRowView(row: row, unit: unit)
            }
            if let local = page.localPlayer, !page.rows.contains(where: \.isLocalPlayer) {
                DashedRule()
                RankingRowView(row: local, unit: unit)
            }
        }
    }

    private var unit: String {
        model.category == .skill ? "pt" : "MB"
    }
}

/// 順位の 1 行（順位・ニックネーム・端末の種類とクラス・スコア）。自分の行は赤くする
private struct RankingRowView: View {
    let row: LeaderboardRow
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(row.rank)")
                .font(Theme.display(16))
                .frame(minWidth: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                // ニックネームは利用者が付けた文字なので、同梱の書体に無い文字は OS の書体で出る
                Text(verbatim: row.displayName)
                    .scaledFont(.mincho(14))
                    .lineLimit(1)
                if let label = row.deviceLabel {
                    Text(verbatim: label)
                        .scaledFont(.mincho(11, .medium))
                        .foregroundStyle(Theme.subText)
                }
            }
            Spacer()
            Text(verbatim: "\(Formatters.integer(row.score)) \(unit)")
                .scaledFont(.typewriter(14))
        }
        .foregroundStyle(row.isLocalPlayer ? Theme.red : Theme.navy)
        .accessibilityElement(children: .combine)
    }
}

/// 紙の札（設定と同じ二重の枠）
private struct RankingPanel<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .scaledFont(.mincho(12, .extraBold))
                .tracking(3)
                .foregroundStyle(Theme.red)
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleFrame()
    }
}
