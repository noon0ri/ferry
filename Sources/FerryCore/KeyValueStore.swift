import Foundation

/// Ferry가 자기 상태를 남기는 최소 인터페이스.
/// 실제로는 UserDefaults를 쓰고, 테스트는 메모리 구현을 끼워 넣는다.
public protocol KeyValueStore: AnyObject, Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    public func set(_ value: String?, forKey key: String) {
        if let value {
            setValue(value, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
