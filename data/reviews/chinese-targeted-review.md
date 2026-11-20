# Targeted Chinese translation review

Reviewed `Rotonda/Data/quiz.db` against its Italian question text on 2026-11-03. All 7,106 Italian question texts were separately compared to `Patente AB.pdf`. The checks below are targeted and do not establish that all 7,106 Chinese translations are correct. No database values were changed.

## Findings

- **21947 — road divided into lanes.** Italian: “Il delineatore raffigurato divide la carreggiata in corsie.” Chinese: “图中所示轮廓诱导标将车道划分为若干行车道”. The Italian distinguishes the whole carriageway (`carreggiata`) from its constituent lanes (`corsie`). Chinese says a lane is divided into lanes. Suggested: “图中所示轮廓诱导标将车行道划分为若干车道。”
- **23460 — same carriageway.** Italian specifies the driver following on the *same carriageway*; Chinese “同一车道后方” specifies the *same lane*. This narrows the statement: a following vehicle in another lane of the same carriageway is excluded in Chinese. Suggested replacement: “同一车行道上后方跟随的驾驶员”.
- **18686 — center of the carriageway.** Italian “al centro della carreggiata” is translated as “车道中央”, the center of a lane. Suggested: “移到车行道中央”. The difference matters on a multi-lane carriageway.
- **22779 and 22784 — edge of the carriageway.** Both translate “margine ... della carreggiata” as an edge of “车道” (lane), rather than “车行道” (carriageway). This can misplace the reference edge. Suggested respectively “车行道右侧边缘” and “车行道左侧边缘”. The latter question is a false statement; preserve its left/right wording and answer when correcting the translation.
- **31054 — position on the carriageway.** Italian “posizione sulla carreggiata” is rendered “在车道上的正确位置”, which narrows carriageway to lane and adds “correct”. Suggested “在车行道上的位置”.
- **23820 — optional placement changed to mandatory central placement.** Italian says to signal with a warning triangle, which may also be placed in the middle of the carriageway (“posto anche in mezzo alla carreggiata”). Chinese “并将其放置在行车道中央” requires placement in the center. Suggested “必要时也可将其放置在车行道中央”. Preserve the original answer key.

The term `carreggiata` appears in a further set of rows translated using “车道” or “行车道” without the unambiguous “车行道”. The term “行车道” can be used for a carriageway, so this is a consistency-review queue, not a claim that all such rows are wrong.

## Coverage and screening

- Read all 54 Chinese/Italian pairs for IDs 31011–31064. Apart from the carriageway issue above, this pass did not establish another clear meaning-changing error.
- Searched all questions for Italian `non` with no common Chinese negative marker: five candidates, all inspected and explained by idiomatic phrasing (three are `non vedente`, one uses 避开, one uses 受阻). This lexical screening cannot detect every negation error.
- Searched all questions for `sinistra`, `destra`, `superiore`, `inferiore`, `sempre`, `mai`, `tutti`, and `solo` without corresponding common Chinese markers. Inspected the 14 candidates; most are idiomatic equivalents. This does not check whether both directions or quantities are assigned to the correct subject.
- Screened 76 occurrences of `carreggiata` where the Chinese lacks `车行道` but contains `车道`; “行车道” was included by this broad search and requires context. The concrete examples above were inspected individually; this is not an exhaustive manual review of those 76 rows.
- Numeric strings were screened for differences; Italian decimal commas, Chinese decimal points, written Chinese numerals, units, reordered clauses, and times produce many false positives. No exhaustive numeric semantic validation is claimed.
