def pick(items):
    chosen = items[0]   # ← S1854 warns here: chosen is overwritten before any read
    chosen = items[-1]
    return chosen
