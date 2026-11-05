import Foundation

public extension Error {
    /// Текст ошибки для человека: своё описание ошибки, иначе системное (ревизия WF247, С5б — одна копия идиомы).
    var humanText: String { (self as? LocalizedError)?.errorDescription ?? localizedDescription }
}
