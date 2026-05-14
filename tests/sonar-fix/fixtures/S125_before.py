def parse(payload):
    data = json.loads(payload)
    # result = legacy_parser(payload)
    # if result is None:
    #     result = data
    return data
