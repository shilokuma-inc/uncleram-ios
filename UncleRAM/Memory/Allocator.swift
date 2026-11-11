import Darwin
import Foundation
import Synchronization

/// 献上するメモリの確保と全解放。**メモリの確保はこの型からしか行わない。**
///
/// - 16MB ごとに確保し、書き込む。書き込まないと使用量に計上されず、ゼロ埋めだと圧縮されて数字が動かない
/// - 確保の前に毎回、安全ラインの 2 つの条件を確かめる（`SafetyLine`）。満たさなければ確保しない
/// - 画面の献上量は、実際に確保して書き込んだ量（`allocatedBytes`）
nonisolated final class Allocator: Sendable {
    static let chunkSize: UInt64 = 16 * 1024 * 1024

    /// 書き込み方。どちらが使用量に正しく計上されるか（圧縮されないか）は、試作の計測で確かめる
    enum FillMode: String, Sendable, CaseIterable, Codable {
        /// 全体を乱数で埋める（重いが、圧縮されない）
        case full
        /// ページごとに少しだけ乱数を書く（軽いが、残りがゼロなので圧縮されるおそれがある）
        case sparse
    }

    /// 1 回の確保の結果
    struct Batch: Sendable, Equatable {
        /// 確保できたチャンクの数
        var allocated = 0
        /// 安全ラインに当たって止めたか
        var blockedBySafetyLine = false
    }

    /// 確保したチャンクの先頭アドレス
    private let chunks = Mutex<[UInt]>([])
    private let allocated = Atomic<UInt64>(0)
    private let mode: Mutex<FillMode>

    init(fillMode: FillMode = .full) {
        mode = Mutex(fillMode)
    }

    /// 書き込み方（計測で切り替える。次に確保する分から効く）
    var fillMode: FillMode {
        get { mode.withLock { $0 } }
        set { mode.withLock { $0 = newValue } }
    }

    /// 確保して書き込み済みの量
    var allocatedBytes: UInt64 {
        allocated.load(ordering: .acquiring)
    }

    /// 16MB を最大 count 個確保する。1 個ごとに安全ラインを確かめ、当たったらそこで止める
    func allocate(count: Int, safety: SafetyLine, probe: any MemoryProbe) -> Batch {
        var batch = Batch()
        guard count > 0 else {
            return batch
        }
        let chunkSize = Self.chunkSize
        var fresh: [UInt] = []
        fresh.reserveCapacity(count)
        for _ in 0..<count {
            let touched = allocatedBytes
            let pending = UInt64(fresh.count) * chunkSize
            // 確保しただけでまだ書き込んでいない分は、OS の残量にまだ表れていないので差し引いて確かめる
            let reported = probe.availableBytes(allocatedByRound: touched)
            let available = reported > pending ? reported - pending : 0
            guard safety.allows(donated: touched + pending, adding: chunkSize, available: available) else {
                batch.blockedBySafetyLine = true
                break
            }
            let address = mmap(nil, Int(chunkSize), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)
            guard let address, address != MAP_FAILED else {
                // 確保そのものに失敗したら、安全のためにそこで止める（納品扱い）
                batch.blockedBySafetyLine = true
                break
            }
            fresh.append(UInt(bitPattern: address))
        }
        Self.fill(fresh, mode: fillMode)
        chunks.withLock { $0.append(contentsOf: fresh) }
        allocated.add(UInt64(fresh.count) * chunkSize, ordering: .releasing)
        batch.allocated = fresh.count
        return batch
    }

    /// 確保したメモリをすべて解放する。かかった秒数を返す
    @discardableResult
    func releaseAll() -> TimeInterval {
        let start = ContinuousClock.now
        let addresses = chunks.withLock { list -> [UInt] in
            let taken = list
            list.removeAll(keepingCapacity: false)
            return taken
        }
        for address in addresses {
            if let pointer = UnsafeMutableRawPointer(bitPattern: address) {
                munmap(pointer, Int(Self.chunkSize))
            }
        }
        allocated.store(0, ordering: .releasing)
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// チャンクを書き込む。CPU のコアに分けて並列に書く（Mac は 0.1 秒で数百 MB を書くため）
    private static func fill(_ addresses: [UInt], mode: FillMode) {
        guard !addresses.isEmpty else {
            return
        }
        let slicesPerChunk = 4
        let sliceSize = Int(chunkSize) / slicesPerChunk
        let pageSize = Int(getpagesize())
        DispatchQueue.concurrentPerform(iterations: addresses.count * slicesPerChunk) { index in
            guard let base = UnsafeMutableRawPointer(bitPattern: addresses[index / slicesPerChunk]) else {
                return
            }
            let slice = base + (index % slicesPerChunk) * sliceSize
            switch mode {
            case .full:
                arc4random_buf(slice, sliceSize)
            case .sparse:
                var offset = 0
                while offset < sliceSize {
                    arc4random_buf(slice + offset, 16)
                    offset += pageSize
                }
            }
        }
    }

    deinit {
        releaseAll()
    }
}
