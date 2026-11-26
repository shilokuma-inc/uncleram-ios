import Foundation

/// 機種 ID（iOS は utsname の machine、Mac は hw.model）に対応する機種名。`DeviceModels.json` の 1 行
nonisolated struct DeviceModel: Sendable, Equatable, Decodable {
    /// 機種名（「iPhone 17 Pro」「MacBook Air」など。Apple の表記のまま）
    let name: String
    /// 画面の大きさ（iPad Air・iPad Pro の「11」「12.9」など）。同じ名前の機種を分けるときだけ書く
    var inches: String?
    /// チップ（「M4」「A17 Pro」など）。Apple がチップで呼び分けている機種と、Mac に書く
    var chip: String?
    /// 世代（iPhone SE の第 3 世代など）。Apple が世代で呼び分けている機種に書く
    var generation: Int?
}

/// 機種名の対応表（docs/SPEC.md「共有機能」の「機種名の対応表」）。アプリに同梱した `DeviceModels.json` から読む。
///
/// 表の形（`models` の中身）は、紹介ページから配る価格表（prices.json）に同じ形で入れて、新しい機種を足せるようにしてある。
/// 価格表の配信を入れるとき（段取り 4）に、配った表を同梱の表の上に重ねる
nonisolated struct DeviceModelCatalog: Sendable, Equatable, Decodable {
    /// 表を確かめた日（YYYY-MM-DD）
    let checkedOn: String
    /// 機種 ID → 機種名
    let models: [String: DeviceModel]

    static let resourceName = "DeviceModels"

    /// 同梱した表。読めなければ空にして、どの端末も「iPhone（12GB 級）」のように級だけで出す
    static let bundled: DeviceModelCatalog = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(DeviceModelCatalog.self, from: data) else {
            return DeviceModelCatalog(checkedOn: "", models: [:])
        }
        return catalog
    }()

    func model(for identifier: String) -> DeviceModel? {
        models[identifier]
    }
}

/// シェアに載せる端末の表示（docs/SPEC.md「共有機能」の「端末の表示」）。
///
/// 標準は「iPhone 17 Pro（12GB）」「MacBook Air（M5・24GB）」のような機種名＋搭載メモリ。「機種名を隠す」と、
/// 機種名の対応表に無い機種は「iPhone（12GB 級）」のように、端末の種類と搭載メモリの級だけにする。
/// 搭載メモリは `DeviceMemoryProfile` の正式な容量（ランキングのクラスと同じ丸め方）。端末の ID は載せない
nonisolated struct ShareDeviceLabel: Sendable, Equatable {
    let kind: DeviceKind
    /// 正式な容量に丸めた搭載メモリ（GB）
    let nominalGigabytes: Int
    /// 対応表で見つかった機種。見つからなければ nil
    let model: DeviceModel?
    /// 表のチップより優先するチップ（Mac の `machdep.cpu.brand_string` から取った「M4 Max」など）
    var chipOverride: String?

    /// 機種を隠すかどうかに合わせた表示
    func text(hidesModel: Bool) -> String {
        guard !hidesModel, let model else {
            return Self.classText(kind: kind, gigabytes: nominalGigabytes)
        }
        let memory = String(localized: "\(nominalGigabytes)GB")
        let detail: String? = if let chip = chipOverride ?? model.chip {
            chip
        } else if let generation = model.generation {
            String(localized: "第\(generation)世代")
        } else {
            nil
        }
        let details = detail.map { String(localized: "\($0)・\(memory)") } ?? memory
        return String(localized: "\(Self.displayName(of: model))（\(details)）")
    }

    /// 文面の「○○ で献上しました」に入れる短い名前（機種名だけ。隠すときと表に無いときは iPhone・iPad・Mac）
    func shortName(hidesModel: Bool) -> String {
        guard !hidesModel, let model else {
            return Self.kindName(kind)
        }
        return Self.displayName(of: model)
    }

    /// 機種名に画面の大きさを添えたもの（「iPad Pro 13インチ」）
    static func displayName(of model: DeviceModel) -> String {
        guard let inches = model.inches else {
            return model.name
        }
        return String(localized: "\(model.name) \(inches)インチ")
    }

    /// 機種名を出さないときの「iPhone（12GB 級）」
    static func classText(kind: DeviceKind, gigabytes: Int) -> String {
        String(localized: "\(kindName(kind))（\(gigabytes)GB 級）")
    }

    static func kindName(_ kind: DeviceKind) -> String {
        switch kind {
        case .iPhone:
            "iPhone"
        case .iPad:
            "iPad"
        case .mac:
            "Mac"
        }
    }
}

extension ShareDeviceLabel {
    /// 今の端末
    @MainActor static var current: ShareDeviceLabel {
        let memory = DeviceMemoryProfile.current
        let identifier = DeviceIdentifier.current
        return ShareDeviceLabel(
            kind: memory.kind,
            nominalGigabytes: memory.nominalGigabytes,
            model: identifier.flatMap { DeviceModelCatalog.bundled.model(for: $0) },
            chipOverride: DeviceIdentifier.appleSiliconChip
        )
    }
}

/// 端末の機種 ID とチップ。機種名を引くためだけに読み、シェアにもランキングにも載せない
nonisolated enum DeviceIdentifier {
    /// iOS は utsname の machine（「iPhone18,1」）、Mac は hw.model（「Mac16,12」）。
    /// Simulator の machine は Mac の CPU（arm64）になるので、Simulator が渡す機種 ID を使う
    static var current: String? {
        #if os(macOS)
        return sysctlString("hw.model")
        #else
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
        }
        return machine?.isEmpty == false ? machine : nil
        #endif
    }

    /// Mac の Apple シリコンのチップ（「Apple M4 Max」の「M4 Max」）。同じ機種 ID に Pro と Max があるため、表より先に使う。
    /// Intel の Mac と iPhone・iPad は nil
    static var appleSiliconChip: String? {
        #if os(macOS)
        chip(fromBrand: sysctlString("machdep.cpu.brand_string"))
        #else
        nil
        #endif
    }

    /// 「Apple M4 Max」→「M4 Max」。Apple シリコンでなければ nil
    static func chip(fromBrand brand: String?) -> String? {
        let prefix = "Apple "
        guard let brand, brand.hasPrefix(prefix) else {
            return nil
        }
        let chip = brand.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return chip.isEmpty ? nil : chip
    }

    #if os(macOS)
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let value = String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
        return value?.isEmpty == false ? value : nil
    }
    #endif
}
