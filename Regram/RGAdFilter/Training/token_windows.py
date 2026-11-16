"""Token-ID windows matching RGAdTokenizer (including final-window anchoring)."""


def native_windows(tokens, sequence_length=128):
    if not tokens or len(tokens) > 1024:
        return None
    capacity = sequence_length - 2
    assert capacity > 16
    windows, start = [], 0
    while start < len(tokens):
        end = min(start + capacity, len(tokens))
        ids = [101] + tokens[start:end] + [102]
        windows.append(ids + [0] * (sequence_length - len(ids)))
        if end == len(tokens):
            break
        start = min(end - 16, max(0, len(tokens) - capacity))
    return windows
