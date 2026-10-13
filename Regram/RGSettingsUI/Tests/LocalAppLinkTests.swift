import Foundation

@main struct LocalAppLinkTests {
    static func main() {
        for text in ["tg://rg/debug", "tg://rg/debug/", "tg://rg/debug?source=test", "tg://sg/debug", "tg://regram/debug", "rg://debug", "regram://debug", "TG://RG/DEBUG", "fixture-app://rg/debug"] {
            assert(rgLocalAppLinkPath(URL(string: text)!, appSpecificScheme: "fixture-app") == "debug", text)
        }
        for route in ["settings", "ios_settings", "contacts", "restart"] {
            assert(rgLocalAppLinkPath(URL(string: "tg://rg/" + route)!, appSpecificScheme: "fixture-app") == route)
        }
        assert(rgLocalAppLinkPath(URL(string: "tg://rg/sg_debug")!, appSpecificScheme: "fixture-app") == "rgdebug")
        assert(rgLocalAppLinkPath(URL(string: "tg://sg/restore_purchases")!, appSpecificScheme: "fixture-app") == "pro")
        for text in ["https://rg/debug", "tg://resolve?domain=rg", "tg://rg/nested/debug", "tg://rg/unknown", "tg://user:password@rg/debug", "tg://rg:80/debug", "other://rg/debug", "tg://settings"] {
            assert(rgLocalAppLinkPath(URL(string: text)!, appSpecificScheme: "fixture-app") == nil, text)
        }
        print("Local app links passed: RG/legacy aliases, queries, trailing slash, custom schemes and Telegram-route isolation.")
    }
}
