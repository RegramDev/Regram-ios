ObjC.import("Foundation");

function run(argv) {
    var pattern = argv[0], input = argv[1];
    var error = Ref();
    var regex = $.NSRegularExpression.regularExpressionWithPatternOptionsError(pattern, 1, error);
    var paused = false;
    function evaluate(cancelled) {
        var start = Date.now(), callbacks = 0, matched = false;
        if (paused || cancelled) return {ms: 0, callbacks: 0, matched: false, skipped: true};
        regex.enumerateMatchesInStringOptionsRangeUsingBlock(input, 1, $.NSMakeRange(0, input.length), function(result, flags, stop) {
            callbacks++;
            if (Date.now() - start >= 3) { paused = true; stop[0] = true; }
            else if (!result.isNil()) { matched = true; stop[0] = true; }
        });
        return {ms: Date.now() - start, callbacks: callbacks, matched: matched, skipped: false};
    }
    var first = evaluate(false), second = evaluate(false), cancelled = evaluate(true);
    return JSON.stringify({first: first, second: second, paused: paused, cancelled: cancelled});
}
