import Foundation
import Darwin

/// tty가 아직 살아 있는지, 그리고 그것이 **같은** 터미널 세션인지 판별한다.
///
/// 창이 닫히면 `/dev/ttysNNN` 파일이 사라진다. 그래서 존재 여부만으로 생사는 알 수 있다.
/// 문제는 번호가 재사용된다는 점이다. 닫은 뒤 다른 창이 같은 번호를 받으면
/// 존재 여부만 보고는 남의 창을 내 세션으로 착각한다.
///
/// 지문으로는 그 tty를 제어 터미널로 갖는 프로세스 중 **가장 먼저 뜬 것(login)의
/// pid와 시작 시각**을 쓴다. 창이 사는 동안 바뀌지 않고, 재할당되면 새 프로세스가
/// 뜨므로 값이 달라진다.
///
/// 파일의 ctime은 지문이 될 수 없다. 창이 열린 직후 셸이 tty 권한을 바꾸면서
/// ctime이 갱신되기 때문에, 기록한 값과 몇 초 뒤의 값이 서로 다르다.
public enum TTYProbe {

    /// tty를 제어 터미널로 쓰는 프로세스가 없거나 장치가 사라졌으면 nil.
    public static func fingerprint(of ttyPath: String) -> String? {
        var info = stat()
        guard stat(ttyPath, &info) == 0 else { return nil }   // 창이 닫혔다
        let device = info.st_rdev

        guard let processes = allProcesses() else { return nil }

        var leaderPID: Int32 = .max
        var leaderStart = timeval()
        for proc in processes where proc.kp_eproc.e_tdev == device {
            let pid = proc.kp_proc.p_pid
            if pid < leaderPID {
                leaderPID = pid
                leaderStart = proc.kp_proc.p_starttime
            }
        }
        guard leaderPID != .max else { return nil }
        return "\(leaderPID).\(leaderStart.tv_sec).\(leaderStart.tv_usec)"
    }

    private static func allProcesses() -> [kinfo_proc]? {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&name, u_int(name.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count)
        let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
            var bytes = raw.count
            return sysctl(&name, u_int(name.count), raw.baseAddress, &bytes, nil, 0)
        }
        guard result == 0 else { return nil }
        return buffer
    }
}
