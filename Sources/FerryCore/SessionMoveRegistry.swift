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
/// 재개가 끝나 로그의 `cwd`가 목표와 같아지면 예약은 소임을 다한 것이므로 스스로 지운다.
public struct SessionMoveRegistry: Sendable {

    private let store: KeyValueStore
    private static let prefix = "move.target."

    public init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// 예약된 목표 폴더. 없으면 nil.
    public func target(for sessionId: String) -> String? {
        store.string(forKey: Self.prefix + sessionId)
    }

    public func schedule(_ target: String, for sessionId: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.set(trimmed, forKey: Self.prefix + sessionId)
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
