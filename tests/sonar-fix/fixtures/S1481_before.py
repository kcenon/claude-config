def calculate(x, y):
    result = x + y   # noqa  ← S1481 warns here
    return x * y
