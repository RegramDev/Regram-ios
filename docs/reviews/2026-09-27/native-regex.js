ObjC.import("Foundation");

function run(argv) {
    var pattern = argv[0];
    var input = argv[1];
    var error = Ref();
    var start = Date.now();
    var regex = $.NSRegularExpression.regularExpressionWithPatternOptionsError(pattern, 1, error);
    var compiledAt = Date.now();
    var match = regex.firstMatchInStringOptionsRange(input, 0, $.NSMakeRange(0, input.length));
    return JSON.stringify({matched: !match.isNil(), compile_ms: compiledAt - start, match_ms: Date.now() - compiledAt});
}
