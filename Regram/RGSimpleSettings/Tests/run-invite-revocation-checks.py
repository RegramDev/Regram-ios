#!/usr/bin/env python3
"""Exercise the production bulk-revocation boundary with synthetic invitations."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[3]
source = (ROOT/'submodules/InviteLinksUI/Sources/InviteLinkListController.swift').read_text()
def block(marker):
    begin=source.index(marker); pos=source.index('{',begin)+1;depth=1
    while depth:
        depth+=(source[pos]=='{')-(source[pos]=='}');pos+=1
    return source[begin:pos]
fixture=r'''
import Foundation
enum EnginePeer { typealias Id = Int64 }
enum ExportedInvitation {
    case link(String, String?, Bool, Bool, Bool, Int64, Int32, Int32?, Int32?, Int32?, Int32?, Int32?, String?)
    case publicJoinRequests
    var value: String { if case let .link(value, _, _, _, _, _, _, _, _, _, _, _, _) = self { return value }; return "public" }
}
'''
tests=r'''
@main enum Checks {
    static func main() {
        func invitation(_ name: String, permanent: Bool = false, revoked: Bool = false, admin: Int64 = 1, expires: Int32? = nil, limit: Int32? = nil, count: Int32? = nil) -> ExportedInvitation {
            .link(name, nil, permanent, false, revoked, admin, 0, nil, expires, limit, count, nil, nil)
        }
        let values: [ExportedInvitation] = [
            invitation("current-main"), invitation("permanent", permanent: true), invitation("revoked", revoked: true),
            invitation("other-admin", admin: 2), invitation("active", expires: 2000), invitation("expired", expires: 1000),
            invitation("used-up", limit: 3, count: 3), invitation("unlimited", expires: 0, limit: 0, count: 100), .publicJoinRequests
        ]
        let all = inviteLinksBulkRevokeCandidates(invitations: values, accountPeerId: 1, protectedMainLink: "current-main", scope: .all, now: 1000).map(\.value)
        precondition(all == ["active", "expired", "used-up", "unlimited"])
        let unavailable = inviteLinksBulkRevokeCandidates(invitations: values, accountPeerId: 1, protectedMainLink: "current-main", scope: .unavailable, now: 1000).map(\.value)
        precondition(unavailable == ["expired", "used-up"])
        precondition(inviteLinksBulkRevokeCandidates(invitations: [], accountPeerId: 1, protectedMainLink: nil, scope: .all, now: 1000).isEmpty)
        print("Invite revocation checks passed: main-link identity, permanent/revoked links, admin ownership, expiry and usage-limit boundaries.")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='regram-invite-checks-') as temporary:
    work=Path(temporary);swift=work/'Checks.swift'
    swift.write_text(fixture+block('private enum InviteLinksBulkRevokeScope')+'\n'+block('private func inviteLinksBulkRevokeCandidates(')+'\n'+tests)
    subprocess.run(['xcrun','swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors',str(swift),'-o',str(work/'checks')],check=True)
    subprocess.run([str(work/'checks')],check=True)
