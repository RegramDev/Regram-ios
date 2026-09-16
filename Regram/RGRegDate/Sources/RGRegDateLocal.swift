import Foundation
import RGRegDateScheme

// MARK: Regram — local registration-date estimate
//
// Replaces the Swiftgram regdate web API, which cannot work in this fork: that endpoint authenticates
// with an Apple DeviceCheck token (`DCDevice.generateToken`), and a resigned sideloaded build has no
// DeviceCheck key registered under its team, so the token call always fails. The endpoint also
// answers 401 to anything but Swiftgram's own app.
//
// Nothing is lost by dropping it. That API returned a `RegDate` *range* and the profile row renders
// its midpoint, i.e. it was doing exactly this interpolation server-side. Doing it on-device is
// strictly better: no network, no wait, and the ids of every profile opened are no longer sent to a
// third party.
//
// How it works: Telegram hands out user ids in roughly increasing order over time, so a table of
// known (id, registration date) pairs can be binary-searched and linearly interpolated. Allocation is
// not strictly sequential — registration is sharded across servers, so two accounts created minutes
// apart can differ by millions — which is why this is an estimate and is surfaced as one.
//
// The table below is the merge of two public crowd-sourced datasets (jobians/telegram-id-age and the
// 44-point set shared by SantiiRepair/tdage and lastochkin-group/telegram-account-age-estimator),
// passed through isotonic regression (pool-adjacent-violators) to force it monotone — the raw merge
// has 79 id/date inversions. Measured against the raw observations, the cleaned table's own residual
// is 0 days median before 2021 and 37 days median after, which is the floor set by sharding.
//
// Expected accuracy, by era:
//   2013-2017  ~1 month   (anchors are dense)
//   2017-2021  several months — only three anchors span 2017-07 to 2021-10, leaving two ~2-year gaps
//   2021+      1-4 months (anchors dense, but sharding noise dominates)
// Because of that, callers should render month precision at best, never a day.

/// (user id, registration unix timestamp), strictly increasing in both columns.
private let rgRegDateAnchors: [(id: Int64, timestamp: Int64)] = [
    (2768409, 1383264000),  // 2013-11-01
    (7679610, 1388448000),  // 2013-12-31
    (11538514, 1391212800),  // 2014-02-01
    (15835244, 1392854400),  // 2014-02-20
    (23646077, 1393372800),  // 2014-02-26
    (38015510, 1393632000),  // 2014-03-01
    (44634663, 1399334400),  // 2014-05-06
    (46145305, 1400112000),  // 2014-05-15
    (54845238, 1411171200),  // 2014-09-20
    (63263518, 1414368000),  // 2014-10-27
    (101260938, 1425600000),  // 2015-03-06
    (101323197, 1426204800),  // 2015-03-13
    (103151531, 1432944000),  // 2015-05-30
    (109393468, 1434326400),  // 2015-06-15
    (112594714, 1438300800),  // 2015-07-31
    (124872445, 1439769600),  // 2015-08-17
    (125828524, 1442620800),  // 2015-09-19
    (133909606, 1444176000),  // 2015-10-07
    (143445125, 1448928000),  // 2015-12-01
    (148670295, 1450828800),  // 2015-12-23
    (171295414, 1457481600),  // 2016-03-09
    (181783990, 1460246400),  // 2016-04-10
    (222021233, 1465344000),  // 2016-06-08
    (225034354, 1466208000),  // 2016-06-18
    (278941742, 1473465600),  // 2016-09-10
    (285253072, 1476748800),  // 2016-10-18
    (294851037, 1479513600),  // 2016-11-19
    (297621225, 1481846400),  // 2016-12-16
    (328594461, 1482969600),  // 2016-12-29
    (337808429, 1487635200),  // 2017-02-21
    (341546272, 1487721600),  // 2017-02-22
    (352940995, 1487894400),  // 2017-02-24
    (369669043, 1490918400),  // 2017-03-31
    (400169472, 1501459200),  // 2017-07-31
    (805158066, 1563148800),  // 2019-07-15
    (1974255900, 1633996800),  // 2021-10-12
    (5022636255, 1638921600),  // 2021-12-08
    (5045293264, 1642032000),  // 2022-01-13
    (5047148663, 1645833600),  // 2022-02-26
    (5106451106, 1646006400),  // 2022-02-28
    (5153900870, 1647129600),  // 2022-03-13
    (5244529493, 1648425600),  // 2022-03-28
    (5308260177, 1650844800),  // 2022-04-25
    (5340744210, 1655683200),  // 2022-06-20
    (5434011049, 1656460800),  // 2022-06-29
    (5442755368, 1658448000),  // 2022-07-22
    (5515826405, 1662595200),  // 2022-09-08
    (5520018289, 1667520000),  // 2022-11-04
    (5738347976, 1670630400),  // 2022-12-10
    (5802659303, 1674518400),  // 2023-01-24
    (5869978651, 1676851200),  // 2023-02-20
    (5994561143, 1682812800),  // 2023-04-30
    (6326011828, 1688688000),  // 2023-07-07
    (6401027363, 1698969600),  // 2023-11-03
    (6536173556, 1703894400),  // 2023-12-30
    (6559717847, 1705881600),  // 2024-01-22
    (6854829938, 1706745600),  // 2024-02-01
    (6872061796, 1707696000),  // 2024-02-12
    (7002435197, 1712361600),  // 2024-04-06
    (7078066115, 1718150400),  // 2024-06-12
    (7224009547, 1719792000),  // 2024-07-01
    (7243375923, 1721260800),  // 2024-07-18
    (7273085448, 1723593600),  // 2024-08-14
    (7342300216, 1725926400),  // 2024-09-10
    (7450316621, 1727827200),  // 2024-10-02
    (7591351660, 1736380800),  // 2025-01-09
    (7817256746, 1738454400),  // 2025-02-02
    (7834356221, 1749686400),  // 2025-06-12
    (7912577935, 1750291200),  // 2025-06-19
    (8179125032, 1752019200),  // 2025-07-09
    (8200159552, 1757116800),  // 2025-09-06
    (8384648263, 1760054400),  // 2025-10-10
    (8480708838, 1762300800),  // 2025-11-05
    (8559682245, 1762819200),  // 2025-11-11
]

/// Ids issued per day, estimated from the last twelve anchors with a Theil-Sen (median-of-pairwise-
/// slopes) fit so a single bad anchor cannot skew it. Used only to extrapolate past the newest anchor.
private let rgRegDateIdsPerDay: Double = 2_739_174.0

/// Telegram's public launch. Accounts below the first anchor can only be placed in this window.
private let rgTelegramLaunchTimestamp: Int64 = 1_376_438_400 // 2013-08-14

/// Estimated registration window for `userId`, or nil if the id cannot belong to a user account.
///
/// The returned `from`/`to` bracket the uncertainty and the midpoint is the estimate, matching what
/// the old web API returned, so every consumer downstream keeps working unchanged. `validUntil` is 0
/// (never stale): the table is baked in, so re-deriving it later would only produce the same answer.
public func rgEstimateRegDate(userId: Int64) -> RegDate? {
    guard userId > 0, !rgRegDateAnchors.isEmpty else {
        return nil
    }

    let first = rgRegDateAnchors[0]
    let last = rgRegDateAnchors[rgRegDateAnchors.count - 1]

    if userId <= first.id {
        // Pre-dates every anchor: somewhere between launch and the first known account.
        return RegDate(from: rgTelegramLaunchTimestamp, to: first.timestamp, validUntil: 0)
    }

    if userId >= last.id {
        // Newer than the table — extrapolate along the recent issue rate. An id cannot have been
        // issued in the future, so the estimate saturates at now. Only the estimate is clamped, never
        // the bounds: clamping those asymmetrically would drag the midpoint that callers read
        // backwards, and a far-future id would then report an *earlier* date than a nearer one.
        let days = Double(userId - last.id) / rgRegDateIdsPerDay
        let now = Int64(Date().timeIntervalSince1970)
        let estimate = min(last.timestamp + Int64(days * 86_400.0), now)
        // Widens with distance past the last anchor, because the issue rate itself drifts. Far beyond
        // the table this grows past the caller's month/year threshold on its own, which is the
        // intended answer there: recent, but the year is all that can be claimed.
        let margin = max(Int64(30 * 86_400), Int64(days * 86_400.0 * 0.25))
        return RegDate(from: estimate - margin, to: estimate + margin, validUntil: 0)
    }

    // Binary search for the bracketing pair, then interpolate inside it.
    var lowIndex = 0
    var highIndex = rgRegDateAnchors.count - 1
    while lowIndex + 1 < highIndex {
        let mid = (lowIndex + highIndex) / 2
        if rgRegDateAnchors[mid].id <= userId {
            lowIndex = mid
        } else {
            highIndex = mid
        }
    }

    let low = rgRegDateAnchors[lowIndex]
    let high = rgRegDateAnchors[highIndex]
    guard high.id > low.id else {
        return RegDate(from: low.timestamp, to: low.timestamp, validUntil: 0)
    }

    let ratio = Double(userId - low.id) / Double(high.id - low.id)
    let estimate = low.timestamp + Int64(ratio * Double(high.timestamp - low.timestamp))

    // Half the bracket is the honest uncertainty: inside a wide gap the curve is unconstrained. The
    // 15-day floor covers sharding noise where anchors are dense.
    let margin = max(Int64(15 * 86_400), (high.timestamp - low.timestamp) / 2)
    return RegDate(from: estimate - margin, to: estimate + margin, validUntil: 0)
}
