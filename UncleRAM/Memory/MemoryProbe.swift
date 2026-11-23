import Darwin
import Foundation
import os

/// 枠と残量を返す。OS ごとに量り方が違うので、プロトコルの向こうに置く（テストでは偽物を渡す）。
nonisolated protocol MemoryProbe: Sendable {
    /// ラウンド開始時の枠（このラウンドで献上できる量の基準）
    func budgetBytes() -> UInt64
    /// いま確保できる残り。安全ラインの 2 つ目の条件（残量 − 確保量 ≥ max(枠 × 15%, 200MB)）に使う
    /// - Parameter allocatedByRound: このラウンドで確保済みの量（Simulator の仮の枠だけが使う）
    func availableBytes(allocatedByRound: UInt64) -> UInt64
}

#if os(iOS)
/// iPhone・iPad の実機。`os_proc_available_memory()` は、このアプリが強制終了されずに使える残り
nonisolated struct ProcessMemoryProbe: MemoryProbe {
    func budgetBytes() -> UInt64 {
        UInt64(os_proc_available_memory())
    }

    func availableBytes(allocatedByRound _: UInt64) -> UInt64 {
        UInt64(os_proc_available_memory())
    }
}
#endif

/// Mac。アプリ単体の上限が無いので、端末全体の空き（free + inactive + purgeable）を見る（docs/SPEC.md「Mac 版の技術仕様」）
nonisolated struct HostMemoryProbe: MemoryProbe {
    /// 枠は使用可能メモリの 60%。搭載メモリの 50% と 32GB を上限にする
    static let budgetRatio = 0.60
    static let physicalMemoryRatioLimit = 0.50
    static let absoluteLimit: UInt64 = 32 * 1024 * 1024 * 1024

    /// 搭載メモリの 50% と 32GB のうち、小さい方の上限
    static var budgetCap: UInt64 {
        min(UInt64(Double(ProcessInfo.processInfo.physicalMemory) * physicalMemoryRatioLimit), absoluteLimit)
    }

    /// 枠が上限で頭打ちになっているか（画面の注記を「使用可能メモリの 60%」から変える）
    static func isCapped(budget: UInt64) -> Bool {
        budget + Allocator.chunkSize >= budgetCap
    }

    func budgetBytes() -> UInt64 {
        let usable = Double(HostMemory.statistics()?.usableBytes ?? 0) * Self.budgetRatio
        let physical = Double(ProcessInfo.processInfo.physicalMemory) * Self.physicalMemoryRatioLimit
        return min(UInt64(min(usable, physical)), Self.absoluteLimit)
    }

    func availableBytes(allocatedByRound _: UInt64) -> UInt64 {
        HostMemory.statistics()?.usableBytes ?? 0
    }
}

/// Simulator。`os_proc_available_memory()` が実際の値を返さないので、仮の枠で動かす（docs/SPEC.md「技術仕様」）
nonisolated struct SimulatedMemoryProbe: MemoryProbe {
    let totalBytes: UInt64
    /// 仮の残量に加えて、実際の Mac の空き（host_statistics64）でも残量を抑えるか。単体テストでは結果がぶれないよう抑えない
    var limitsByHost = false

    func budgetBytes() -> UInt64 {
        totalBytes
    }

    func availableBytes(allocatedByRound: UInt64) -> UInt64 {
        let simulated = totalBytes > allocatedByRound ? totalBytes - allocatedByRound : 0
        guard limitsByHost, let host = HostMemory.statistics()?.usableBytes else {
            return simulated
        }
        return min(simulated, host)
    }
}

nonisolated enum MemoryProbes {
    /// Simulator の仮の枠
    static let simulatorBudget: UInt64 = 2 * 1024 * 1024 * 1024

    /// 実行している環境の量り方
    static var current: any MemoryProbe {
        #if targetEnvironment(simulator)
        SimulatedMemoryProbe(totalBytes: simulatorBudget, limitsByHost: true)
        #elseif os(macOS)
        HostMemoryProbe()
        #else
        ProcessMemoryProbe()
        #endif
    }
}

/// Mac の端末全体のメモリの統計（host_statistics64）。iOS でも呼べるが、枠には使わない
nonisolated struct HostMemory: Sendable, Equatable {
    let pageSize: UInt64
    let freePages: UInt64
    let inactivePages: UInt64
    let purgeablePages: UInt64
    let compressorPages: UInt64
    let swapOuts: UInt64

    /// 使用可能メモリ（free + inactive + purgeable）
    var usableBytes: UInt64 {
        (freePages + inactivePages + purgeablePages) * pageSize
    }

    /// 圧縮メモリが占めている量
    var compressedBytes: UInt64 {
        compressorPages * pageSize
    }

    /// 取れなかった（App Sandbox などで拒まれた）ときは nil
    static func statistics() -> HostMemory? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        return HostMemory(
            pageSize: UInt64(pageSize),
            freePages: UInt64(info.free_count),
            inactivePages: UInt64(info.inactive_count),
            purgeablePages: UInt64(info.purgeable_count),
            compressorPages: UInt64(info.compressor_page_count),
            swapOuts: info.swapouts
        )
    }
}

/// 検証用の、このアプリの使用量など
nonisolated enum ProcessMemory {
    /// このアプリの使用量（`task_info(TASK_VM_INFO)` の phys_footprint）。OS が強制終了を決めるときに見る値
    static func footprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// このアプリのメモリのうち、圧縮されている量（phys_footprint に含まれる）
    static func compressedBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.compressed : nil
    }

    /// Mac のスワップの使用量（sysctl vm.swapusage）。取れなければ nil
    static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return nil
        }
        return usage.xsu_used
    }
}
