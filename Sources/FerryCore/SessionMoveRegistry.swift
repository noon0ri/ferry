import Foundation

/// "이 세션은 다음에 재개할 때 다른 폴더에서 열자"는 예약을 기억한다.
///
/// 세션의 그룹은 로그에 기록된 `cwd`에서 나온다. 그 값은 Ferry가 바꿀 수 없고,
/// 실제로 그 폴더에서 `claude --resume`이 돌아야 Claude Code가 새 `cwd`를 기록한다.
/// 그때 비로소 그룹이 옮겨진다.
///
/// 그래서 예약은 예약으로만 표시한다. 목록에서 세션을 미리 옮겨 놓으면, 실제로는
/// 아직 옛 폴더에 있는데 새 그룹에 있는 것처럼 보이게 된다. 그룹이 실제 작업 폴더를
/// 뜻한다는 이 앱의 약속이 거기서 깨진다.
///
/// 상태는 둘이다.
///
/// - **예약(pending)**: 고르기만 한 상태. 아직 아무 일도 일어나지 않았으므로 세션은
///   원래 그룹에 남고 `→ 목적지` 표시만 붙는다.
/// - **실행(applied)**: 그 폴더에서 실제로 재개한 상태. 사용자가 결정을 실행했으므로
///   Ferry는 그 그룹으로 보여준다. 다만 로그의 `cwd`는 사용자가 첫 메시지를 보내기
///   전까지 갱신되지 않으므로, 그 사이를 이 상태가 메운다.
///
/// 로그의 `cwd`가 목표와 같아지면 기록은 소임을 다한 것이므로 스스로 지운다.
public struct SessionMoveRegistry: Sendable {

    private let store: KeyValueStore
    private static let prefix = "move.target."
    private static let separator = "\u{1F}"
    private static let appliedMark = "applied"

    public init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// 목표 폴더. 예약이든 실행이든 상관없이 돌려준다. 재개할 때 쓴다.
    public func target(for sessionId: String) -> String? {
        raw(sessionId)?.target
    }

    /// 아직 실행되지 않은 예약만. `→ 목적지` 표시에 쓴다.
    public func pendingTarget(for sessionId: String) -> String? {
        guard let entry = raw(sessionId), !entry.applied else { return nil }
        return entry.target
    }

    /// 실행된 이동의 목표. 그룹핑에 쓴다. 로그가 아직 옛 cwd여도 여기로 묶는다.
    public func appliedTarget(for sessionId: String) -> String? {
        guard let entry = raw(sessionId), entry.applied else { return nil }
        return entry.target
    }

    private func raw(_ sessionId: String) -> (target: String, applied: Bool)? {
        guard let stored = store.string(forKey: Self.prefix + sessionId) else { return nil }
        let parts = stored.components(separatedBy: Self.separator)
        guard let target = parts.first, !target.isEmpty else { return nil }
        return (target, parts.count > 1 && parts[1] == Self.appliedMark)
    }

    public func schedule(_ target: String, for sessionId: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.set(trimmed, forKey: Self.prefix + sessionId)
    }

    /// 그 폴더에서 실제로 재개했음을 표시한다.
    public func markApplied(_ sessionId: String) {
        guard let entry = raw(sessionId) else { return }
        store.set(entry.target + Self.separator + Self.appliedMark, forKey: Self.prefix + sessionId)
    }

    public func cancel(_ sessionId: String) {
        store.set(nil, forKey: Self.prefix + sessionId)
    }

    /// 이미 목표 폴더에 도착한 예약을 지운다.
    /// 새로고침마다 부르면 되고, 이동이 실현된 다음 스캔에서 자동으로 정리된다.
    public func reconcile(_ sessions: [Session]) {
        for session in sessions {
            guard let target = target(for: session.id) else { continue }
            if session.cwd == target {
                cancel(session.id)
            }
        }
    }
}
