import CoreText
import Testing
@testable import UncleRAM

/// 同梱した書体が読み込まれているかを確かめる。
/// 文言の文字が書体に入っているかは、CI の `python3 Tools/fonts/subset.py --check` で見る
/// （テストからソースを読むと、リポジトリがデスクトップの下にある Mac では、ファイルへのアクセスの許可待ちで止まるため）
struct FontTests {
    nonisolated static let bundledFontNames = [Theme.FontName.archivoBlack, Theme.FontName.courierPrimeBold]
        + Theme.MinchoWeight.allCases.map(\.postScriptName)

    /// Info.plist の登録で、PostScript 名から書体を開ける（開けないと、OS の書体に黙って替わる）
    @Test(arguments: bundledFontNames)
    func bundledFontIsRegistered(name: String) {
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        #expect(CTFontCopyPostScriptName(font) as String == name)
    }

    /// 和文の書体は、文言の文字に絞ってある。絞りすぎて、よく使う文字まで落としていないか
    @Test(arguments: Theme.MinchoWeight.allCases)
    func minchoHasCommonCharacters(weight: Theme.MinchoWeight) {
        let font = CTFontCreateWithName(weight.postScriptName as CFString, 12, nil)
        let characters = CTFontCopyCharacterSet(font)
        for scalar in "献上納品回収ライン、。0123456789MB".unicodeScalars {
            #expect(CFCharacterSetIsLongCharacterMember(characters, UTF32Char(scalar.value)), "\(scalar) が無い")
        }
    }
}
