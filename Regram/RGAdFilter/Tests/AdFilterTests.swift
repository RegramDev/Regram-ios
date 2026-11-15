import XCTest
@testable import RGAdFilter

final class AdFilterTests: XCTestCase {
    private func entity(_ text: String, _ token: String, kind: RGAdEntity.Kind = .mention, value: String? = nil) -> RGAdEntity {
        let range = (text as NSString).range(of: token)
        return RGAdEntity(range: RGAdRange(range.location, NSMaxRange(range)), kind: kind, value: value ?? token)
    }
    private func store() throws -> RGAdSampleStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RGAdSampleStore(accountDirectory: directory)
    }
    private let ad = "0充值，免费体验，中奖可提现 → @promotion_user"

    func testMixedCaptionAndButtons() throws {
        let text = "剧名：春日旅程\n简介：两人一起寻找答案。\n@search_helper\n================\n" + ad
        let input = RGAdInput(text: text, entities: [entity(text, "@search_helper"), entity(text, "@promotion_user")], buttons: [[RGAdButton(id: "0:0", title: "电影搜索", target: "https://t.me/search_helper"), RGAdButton(id: "0:1", title: "一元云购", target: "https://t.me/promotion_user")]], hasMedia: true)
        let result = try RGAdPolicy.project(input)
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertTrue(result.text.contains("剧名：春日旅程")); XCTAssertTrue(result.text.contains("@search_helper"))
        XCTAssertFalse(result.text.contains("中奖")); XCTAssertFalse(result.text.contains("===="))
        XCTAssertEqual(result.buttons.flatMap { $0 }.map(\.id), ["0:0"])
    }

    func testWarningAndQuotedPromotionArePreserved() throws {
        for text in ["警惕骗局：" + ad, "新闻报道：" + ad] {
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text, entities: [entity(text, "@promotion_user")])).disposition, .keep)
        }
        for kind in [RGAdEntity.Kind.code, .quote] {
            let input = RGAdInput(text: ad, entities: [entity(ad, "@promotion_user"), RGAdEntity(range: RGAdRange(0, ad.utf16.count), kind: kind)])
            XCTAssertEqual(try RGAdPolicy.project(input).disposition, .keep)
        }
    }

    func testRepeatedPromotionDoesNotEraseWarningInSameMessage() throws {
        let text = "警惕骗局：" + ad + "\n" + ad
        let last = (text as NSString).range(of: "@promotion_user", options: .backwards)
        let input = RGAdInput(text: text, entities: [entity(text, "@promotion_user"), RGAdEntity(range: RGAdRange(last.location, NSMaxRange(last)), kind: .mention, value: "@promotion_user")])
        XCTAssertEqual(try RGAdPolicy.project(input).text, "警惕骗局：" + ad + "\n")
    }

    func testRepeatedNormalOccurrencePreventsLearning() throws {
        let storage = try store(), snippet = "欢迎参与我们的优惠活动并领取专属奖励"
        var sample = try storage.draft(input: RGAdInput(text: snippet + "\n" + snippet, peerId: 9), messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 0, length: snippet.utf16.count), as: .ad)
        try storage.save(sample)
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: "新内容\n" + snippet, peerId: 9), samples: storage.load(), sourceGroup: sample.sourceGroup).disposition, .keep)
    }

    func testNoDestinationAndNormalResourceLinksArePreserved() throws {
        for text in ["中奖可提现", "本片包含广告行业与赌场相关情节。", "免费体验新功能 @search_helper", ad] {
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text)).disposition, .keep)
        }
        let input = RGAdInput(text: "影视介绍与资源", buttons: [[RGAdButton(id: "a", title: "电报资源", target: "https://t.me/search_helper")]])
        XCTAssertEqual(try RGAdPolicy.project(input).buttons, input.buttons)
    }

    func testPublicButtonRuleDoesNotRemoveBody() throws {
        let input = RGAdInput(text: "新闻：今天讨论广告合作招商。", buttons: [[RGAdButton(id: "a", title: "广告合作招商", target: "https://example.org/sponsor")]])
        let output = try RGAdPolicy.project(input)
        XCTAssertEqual(output.text, input.text); XCTAssertTrue(output.buttons.isEmpty)
    }

    func testEmojiBannerAndIndependentInviteButton() throws {
        // Synthetic body, destinations and emoji IDs; shape mirrors a mixed movie/ad footer.
        let banner = "🩷🩷🩷🩷 新人注册送38U"
        let text = "剧名：春日旅程\n简介：正常剧情。\n@search_helper\n================\n\n实力飞投｜超高限红｜大额无忧 ➜ @first_promo\n\n" + ad + "\n\n" + banner
        var entities = [entity(text, "@search_helper"), entity(text, "@first_promo"), entity(text, "@promotion_user"), entity(text, banner, kind: .link, value: "https://example.org/signup"), entity(text, "================", kind: .format, value: "bold")]
        let start = (text as NSString).range(of: "🩷🩷🩷🩷").location
        for i in 0..<4 { entities.append(RGAdEntity(range: RGAdRange(start + i * 2, start + i * 2 + 2), kind: .customEmoji, value: "synthetic-\(i)")) }
        let input = RGAdInput(text: text, entities: entities, buttons: [
            [RGAdButton(id: "cooperate", title: "广 告 合 作 招 商", target: "https://example.org/sponsor")],
            [RGAdButton(id: "search", title: "电影搜索", target: "https://t.me/search_helper"), RGAdButton(id: "resources", title: "电报资源", target: "https://t.me/resource_helper")],
            [RGAdButton(id: "invite", title: "白马庄园大额无忧", target: "https://t.me/+syntheticInvite"), RGAdButton(id: "lottery", title: "一元云购 0充值，免费体验，中奖可提现", target: "https://example.org/different-destination")]
        ], hasMedia: true)
        let result = try RGAdPolicy.project(input)
        XCTAssertEqual(result.text, "剧名：春日旅程\n简介：正常剧情。\n@search_helper\n")
        XCTAssertEqual(result.buttons.flatMap { $0 }.map(\.id), ["search", "resources"])
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertEqual(result.entities.map(\.kind), [.mention])
    }

    func testLinkedHiddenBrandAndObfuscatedPromotion() throws {
        let text = "正常正文👨‍👩‍👧‍👦\n🩷🩷🩷🩷 新人注册送38U"
        for target in ["https://8g.com/?campaign=synthetic", "https://8gtg.vip/synthetic"] {
            let link = entity(text, "🩷🩷🩷🩷 新人注册送38U", kind: .link, value: target)
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text, entities: [link])).text, "正常正文👨‍👩‍👧‍👦\n")
        }
        let spaced = "正常正文\n０ 充 值，免\u{200b}费 体 验，中 奖 可 提 现 → @promotion_user"
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: spaced, entities: [entity(spaced, "@promotion_user")])).text, "正常正文\n")
        let traditional = "正常正文\n實 力 飛 投｜超 高 限 紅｜大 額 無 憂 @promotion_user"
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: traditional, entities: [entity(traditional, "@promotion_user")])).text, "正常正文\n")
    }

    func testBannerEvidenceDoesNotConsumeNormalOrReportedContent() throws {
        let banner = "🩷🩷🩷🩷 新人注册送38U"
        for prefix in ["", "警惕骗局：" + ad + "\n", ad + "\n正常剧情介绍\n"] {
            let text = prefix + banner
            var entities = [entity(text, banner, kind: .link, value: "https://example.org/signup")]
            if prefix.contains("@promotion_user") { entities.append(entity(text, "@promotion_user")) }
            let start = (text as NSString).range(of: "🩷🩷🩷🩷").location
            for i in 0..<4 { entities.append(RGAdEntity(range: RGAdRange(start + i * 2, start + i * 2 + 2), kind: .customEmoji, value: "synthetic-\(i)")) }
            XCTAssertTrue(try RGAdPolicy.project(RGAdInput(text: text, entities: entities)).text.contains(banner))
        }
        for target in ["https://8g.com.example.org", "https://example.org/8g.com"] {
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: banner, entities: [entity(banner, banner, kind: .link, value: target)])).disposition, .keep)
        }
        let warning = "警 惕\u{200b}诈 骗：" + ad
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: warning, entities: [entity(warning, "@promotion_user")])).disposition, .keep)
        let normal = RGAdInput(text: "影视正文", buttons: [[RGAdButton(id: "normal", title: "白马庄园取景地介绍", target: "https://example.org/film"), RGAdButton(id: "warning", title: "警惕白马庄园大额无忧骗局", target: "https://example.org/report")]])
        XCTAssertEqual(try RGAdPolicy.project(normal).disposition, .keep)
    }

    func testDestinationIsExactAndNormalLinkVetoesInferredRemoval() throws {
        let text = "联系 @promotion_user\n" + ad
        let ranges = (text as NSString).range(of: "@promotion_user", options: .backwards)
        let input = RGAdInput(text: text, entities: [entity(text, "@promotion_user"), RGAdEntity(range: RGAdRange(ranges.location, NSMaxRange(ranges)), kind: .mention, value: "@promotion_user")], buttons: [[RGAdButton(id: "a", title: "联系", target: "https://t.me/promotion_user"), RGAdButton(id: "b", title: "别的频道", target: "https://t.me/search_helper")]])
        XCTAssertEqual(try RGAdPolicy.project(input).buttons, input.buttons)
        XCTAssertNotEqual(RGAdFilter.normalizedTarget("https://t.me/promotion_user/123"), RGAdFilter.normalizedTarget("@promotion_user"))
        XCTAssertEqual(RGAdFilter.normalizedTarget("@abcd"), RGAdFilter.normalizedTarget("https://t.me/abcd"))
    }

    func testUnicodeMarkSplitAndClear() throws {
        let storage = try store()
        var sample = try storage.draft(input: RGAdInput(text: "正常👨‍👩‍👧‍👦广告é尾部", peerId: 1), messageKey: "1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 3, length: 1), as: .ad)
        XCTAssertEqual((sample.input.text as NSString).substring(with: sample.spans[0].range.nsRange), "👨‍👩‍👧‍👦")
        try sample.mark(NSRange(location: 0, length: sample.input.text.utf16.count), as: .ad)
        try sample.mark(NSRange(location: 0, length: 2), as: .normal)
        XCTAssertEqual(sample.previewText, "正常")
        try sample.validate()
        XCTAssertThrowsError(try sample.mark(NSRange(location: Int.max, length: 3), as: .ad))
    }

    func testHumanSelectionExpandsAtomicLink() throws {
        let storage = try store(), text = "内容 链接文字 保留"
        var sample = try storage.draft(input: RGAdInput(text: text, peerId: 1, entities: [entity(text, "链接文字", kind: .link, value: "https://example.org")]), messageKey: "1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 4, length: 1), as: .ad)
        XCTAssertEqual((text as NSString).substring(with: sample.spans[0].range.nsRange), "链接文字")
        XCTAssertEqual(sample.previewText, "内容  保留")
    }

    func testFormattingRemapAfterRemovedParagraph() throws {
        let text = "广告片段\n正常👋文字"
        let output = try RGAdFilter.project(RGAdInput(text: text, entities: [RGAdEntity(range: RGAdRange(0, text.utf16.count), kind: .format, value: "bold")]), rules: [RGAdRule("广告片段")])
        XCTAssertEqual(output.text, "正常👋文字")
        XCTAssertEqual(output.entities.first?.range, RGAdRange(0, output.text.utf16.count))
    }

    func testReviewedNormalOverridesAutomaticAndSurvivesRestart() throws {
        let storage = try store(), input = RGAdInput(text: ad, peerId: 99, entities: [entity(ad, "@promotion_user")])
        let sample = try storage.draft(input: input, messageKey: "99:1", mediaKinds: [], mediaIdentity: "")
        XCTAssertTrue(try storage.load().isEmpty)
        try storage.save(sample)
        let reopened = RGAdSampleStore(accountDirectory: storage.directory.deletingLastPathComponent())
        let loaded = try reopened.load()
        XCTAssertEqual(try RGAdPolicy.project(input, samples: loaded, sourceGroup: sample.sourceGroup).disposition, .keep)
        XCTAssertEqual(try reopened.draft(input: input, messageKey: "99:1", mediaKinds: [], mediaIdentity: "").id, sample.id)
    }

    func testEditedMessageGetsNewUnreviewedSnapshot() throws {
        let storage = try store()
        let sample = try storage.draft(input: RGAdInput(text: "原文", peerId: 2), messageKey: "2:1", mediaKinds: [], mediaIdentity: "a")
        try storage.save(sample)
        let edited = try storage.draft(input: RGAdInput(text: "新原文", peerId: 2), messageKey: "2:1", mediaKinds: [], mediaIdentity: "a")
        let replaced = try storage.draft(input: RGAdInput(text: "原文", peerId: 2), messageKey: "2:1", mediaKinds: [], mediaIdentity: "b")
        XCTAssertNotEqual(edited.id, sample.id); XCTAssertNil(edited.reviewedAt); XCTAssertNotEqual(replaced.id, sample.id)
    }

    func testSameChannelLearnsExactAdSnippetButOtherChannelsDoNot() throws {
        let storage = try store(), snippet = "欢迎参与我们的优惠活动并领取专属奖励"
        var sample = try storage.draft(input: RGAdInput(text: "正常介绍\n" + snippet, peerId: 9), messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        try sample.mark((sample.input.text as NSString).range(of: snippet), as: .ad); try storage.save(sample)
        let later = RGAdInput(text: "另一个正常介绍\n" + snippet, peerId: 9)
        XCTAssertFalse(try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: sample.sourceGroup).text.contains(snippet))
        XCTAssertEqual(try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: "other").disposition, .keep)
        try storage.remove(sample)
        XCTAssertEqual(try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: sample.sourceGroup).disposition, .keep)
    }

    func testButtonCorrectionDoesNotRemoveNormalTextLink() throws {
        let storage = try store(), text = "正常链接 @search_helper"
        let button = RGAdButton(id: "0:0", title: "推广入口", target: "https://t.me/search_helper")
        let input = RGAdInput(text: text, peerId: 9, entities: [entity(text, "@search_helper")], buttons: [[button]])
        var sample = try storage.draft(input: input, messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        sample.buttonLabels[button.id] = .ad; try storage.save(sample)
        let later = RGAdInput(text: text + " 更多内容", peerId: 9, entities: input.entities, buttons: input.buttons)
        let projected = try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: sample.sourceGroup)
        XCTAssertEqual(projected.text, later.text); XCTAssertTrue(projected.buttons.isEmpty)
    }

    func testNormalButtonLabelVetoesAdTextInference() throws {
        let storage = try store()
        let input = RGAdInput(text: ad, peerId: 9, entities: [entity(ad, "@promotion_user")], buttons: [[RGAdButton(id: "a", title: "保留", target: "https://t.me/promotion_user")]])
        var sample = try storage.draft(input: input, messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 0, length: ad.utf16.count), as: .ad); sample.buttonLabels["a"] = .normal; try storage.save(sample)
        XCTAssertEqual(try RGAdPolicy.project(input, samples: storage.load(), sourceGroup: sample.sourceGroup).buttons, input.buttons)
    }

    func testRetainedButtonCorrectionAppliesToLaterMessagesInSameChannel() throws {
        for label in [RGAdLabel.normal, .uncertain] {
            let storage = try store()
            let button = RGAdButton(id: "a", title: "保留入口", target: "https://t.me/promotion_user")
            let input = RGAdInput(text: ad, peerId: 9, entities: [entity(ad, "@promotion_user")], buttons: [[button]])
            var sample = try storage.draft(input: input, messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
            try sample.mark(NSRange(location: 0, length: ad.utf16.count), as: .ad)
            sample.buttonLabels[button.id] = label; try storage.save(sample)
            let text = "新的正常介绍\n" + ad
            let later = RGAdInput(text: text, peerId: 9, entities: [entity(text, "@promotion_user")], buttons: [[RGAdButton(id: "1:1", title: button.title, target: button.target)]])
            let knowledge = try RGAdPolicy.Knowledge(samples: storage.load())
            let projected = try knowledge.project(later, sourceGroup: sample.sourceGroup)
            XCTAssertEqual(projected.text, "新的正常介绍\n")
            XCTAssertEqual(projected.buttons, later.buttons)
            XCTAssertTrue(projected.removedButtonIds.isEmpty)
            XCTAssertTrue(try knowledge.project(later, sourceGroup: "other").buttons.isEmpty)
        }
    }

    func testAccountIsolationExportAndCorruptionFailClosed() throws {
        let first = try store(), second = try store(), input = RGAdInput(text: "正常消息", peerId: 123456789)
        let a = try first.draft(input: input, messageKey: "m", mediaKinds: [], mediaIdentity: "")
        let b = try second.draft(input: input, messageKey: "m", mediaKinds: [], mediaIdentity: "")
        XCTAssertNotEqual(a.sourceGroup, b.sourceGroup); XCTAssertNotEqual(a.id, b.id)
        try first.save(a)
        let export = try first.export(), text = String(decoding: export, as: UTF8.self)
        XCTAssertFalse(text.contains("123456789")); XCTAssertTrue(text.contains("utf16")); XCTAssertTrue(try second.load().isEmpty)
        try Data("broken".utf8).write(to: first.directory.appendingPathComponent(a.id + ".json"))
        XCTAssertThrowsError(try first.load()); XCTAssertThrowsError(try first.export())
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.directory.appendingPathComponent(a.id + ".json").path))
    }

    func testDisabledSettingPersistsPerAccount() throws {
        let first = try store(), second = try store()
        XCTAssertTrue(try first.isEnabled()); try first.setEnabled(false)
        XCTAssertFalse(try first.isEnabled()); XCTAssertTrue(try second.isEnabled())
        try first.setEnabled(true); XCTAssertTrue(try first.isEnabled())
    }
}
