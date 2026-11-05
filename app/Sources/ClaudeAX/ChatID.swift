import Foundation

/// id чата Claude (`local_…`) одним правилом (ревизия WF247, С5а): страница, канал «Пимп», окно файла и адрес
/// страницы пускают одно и то же.
enum ChatID {
    static let prefix = "local_"
    /// Потолок длины: id приходит из чужих файлов и адресов.
    static let limit = 128

    /// `local_` и дальше только латинские буквы, цифры, дефис и подчёркивание (иначе страница показала бы путь
    /// percent-кодировкой, и сверка `match` не сошлась бы), не длиннее `limit`; пробелы по краям срезаются.
    /// Не id — nil.
    static func parse(_ raw: String?) -> String? {
        guard let id = raw?.trimmingCharacters(in: .whitespaces),
              id.hasPrefix(prefix), id.count > prefix.count, id.count <= limit,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        return id
    }

    /// Строже — для CLI (`renew-window`, `send`, `main`): `local_` и uuid строчными (36 знаков из 0-9a-f и «-»).
    static func isUUID(_ raw: String) -> Bool {
        guard raw.hasPrefix(prefix) else { return false }
        let tail = raw.dropFirst(prefix.count)
        return tail.count == 36 && tail.allSatisfy { "0123456789abcdef-".contains($0) }
    }
}
