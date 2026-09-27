ObjC.import("Foundation");

function run(argv) {
    var allowed = $.NSCharacterSet.characterSetWithCharactersInString("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%");
    var encoded = $(argv[0]).stringByAddingPercentEncodingWithAllowedCharacters(allowed);
    var parsed = $.NSURL.URLWithString(encoded);
    return JSON.stringify({encoded: ObjC.unwrap(encoded), parsed: !parsed.isNil()});
}
