# sonarcloud[bot] PR Comment Format

## Summary comment (one per PR)
Posted by `sonarcloud[bot]`. Contains the Quality Gate verdict in a
heading or bolded line such as `Quality Gate passed` or `Quality Gate failed`.

Parser must extract: `verdict in {PASS, FAIL}`.

## Inline review comments (one per finding)
Posted on the diff line of the finding. Body shape:

> <severity> <rule-name> <message>
> See more on [SonarQube Cloud](URL with `rule=<rule_id>` query)

Parser must extract: `rule_id`, `severity`, `file:line`, `message`.

## `rule_id` regex
`\b(S\d{1,4})\b` (matches `S1481`, `S125`, etc.)

## Sample Archive
(populated by P2+ as real sonarcloud[bot] comments arrive — keep this
section as a chronological list of `(date, comment_url, verdict, rules[])`
tuples so future parser tweaks have a regression corpus)

### TODO entries from P2
- (date) `<url>` — verdict, rule_ids encountered
