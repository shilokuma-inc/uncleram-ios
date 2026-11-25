import Foundation
#if os(iOS)
import UIKit
#endif

/// 端末の種類。ランキングの context に入れ、献上量のクラスの分け方を決める（機種名は送らない）
nonisolated enum DeviceKind: Int, Sendable, Codable, CaseIterable {
    case iPhone = 1
    case iPad = 2
    case mac = 3

    /// 今の端末の種類
    @MainActor static var current: DeviceKind {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }
}

/// 献上量のランキングのクラス。変わらない搭載メモリで分ける（docs/SPEC.md「ランキング」）。
///
/// raw value はランキングの ID の後ろ（`mb_<raw value>`）。
nonisolated enum MemoryClass: String, Sendable, Codable, CaseIterable {
    /// iPhone・iPad の 8GB 以下
    case iosSmall = "ios_s"
    /// iPhone・iPad の 12GB（8GB より大きく 16GB 未満）
    case iosMedium = "ios_m"
    /// iPhone・iPad の 16GB 以上
    case iosLarge = "ios_l"
    /// Mac の 18GB 以下
    case macSmall = "mac_s"
    /// Mac の 24〜36GB
    case macMedium = "mac_m"
    /// Mac の 48GB 以上
    case macLarge = "mac_l"

    /// クラスの大きさ（小 1・中 2・大 3）。context に入れる
    var tier: Int {
        switch self {
        case .iosSmall, .macSmall:
            1
        case .iosMedium, .macMedium:
            2
        case .iosLarge, .macLarge:
            3
        }
    }

    /// 端末の種類とクラスの大きさから決める。context を読み戻すときに使う
    init?(kind: DeviceKind, tier: Int) {
        let candidates: [MemoryClass] = kind == .mac ? [.macSmall, .macMedium, .macLarge] : [.iosSmall, .iosMedium, .iosLarge]
        guard let found = candidates.first(where: { $0.tier == tier }) else {
            return nil
        }
        self = found
    }
}

/// 端末の種類と、正式な容量に丸めた搭載メモリ。献上量のクラスはここから決まる
nonisolated struct DeviceMemoryProfile: Sendable, Equatable {
    /// 正式な容量（GB）。physicalMemory は公称より少し少ない（OS や GPU が先に取る分がある）ので、
    /// これ以上でいちばん小さい値に切り上げる。18GB と 36GB は Mac の M3 Pro・M3 Max
    static let nominalGigabytes = [1, 2, 3, 4, 6, 8, 12, 16, 18, 24, 32, 36, 48, 64, 96, 128, 192, 256, 384, 512]
    static let bytesPerGigabyte: UInt64 = 1 << 30

    let kind: DeviceKind
    /// 正式な容量に丸めた搭載メモリ（GB。1GB = 2^30 バイト）
    let nominalGigabytes: Int

    init(kind: DeviceKind, nominalGigabytes: Int) {
        self.kind = kind
        self.nominalGigabytes = nominalGigabytes
    }

    /// - Parameter physicalMemory: `ProcessInfo.physicalMemory`（バイト）。同じ端末なら毎回同じ値なので、クラスも毎回同じになる
    init(kind: DeviceKind, physicalMemory: UInt64) {
        let gigabytes = Double(physicalMemory) / Double(Self.bytesPerGigabyte)
        // 表より大きい端末は、GB の整数に切り上げる
        let nominal = Self.nominalGigabytes.first { Double($0) >= gigabytes } ?? Int(gigabytes.rounded(.up))
        self.init(kind: kind, nominalGigabytes: nominal)
    }

    /// 今の端末
    @MainActor static var current: DeviceMemoryProfile {
        DeviceMemoryProfile(kind: .current, physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    /// 献上量のクラス。iPhone・iPad は 8GB 以下 / 12GB / 16GB 以上、Mac は 18GB 以下 / 24–36GB / 48GB 以上。
    ///
    /// Mac の 18GB と 36GB は、枠の上限（搭載メモリの 50%）が近い下のクラスに入れる（18GB は 18GB 以下、36GB は 24–36GB。
    /// 2026-11-26 にユーザーが決め、ランキングの名前も「16GB 以下」「24〜32GB」から広げた）
    var memoryClass: MemoryClass {
        switch kind {
        case .iPhone, .iPad:
            if nominalGigabytes <= 8 {
                return .iosSmall
            }
            return nominalGigabytes < 16 ? .iosMedium : .iosLarge
        case .mac:
            if nominalGigabytes < 24 {
                return .macSmall
            }
            return nominalGigabytes < 48 ? .macMedium : .macLarge
        }
    }

    /// 丸めた搭載メモリ（バイト）。献上量がこれを超える記録は送らない
    var memoryBytes: UInt64 {
        UInt64(nominalGigabytes) * Self.bytesPerGigabyte
    }
}
