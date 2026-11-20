# Quiz translation review

Reviewed against the A/B database (now `database/ab/quiz.db`) and the Italian text in `../Patente AB.pdf`. The PDF page numbers below are physical, one-based pages. Question IDs are stable legacy A/B identifiers. The false statements in the source must remain false in translation; the suggested corrections preserve the statements, not the rules of the road.

## Findings

### English: parking translated as stopping

The distinction between *sosta* (parking) and *fermata* (a temporary stop) is material in this quiz; compare question 18350, which explicitly contrasts them. These translations broaden the source statement from parking to stopping and should be corrected individually:

| ID | PDF page | Italian source | Current English | Suggested English |
|---|---:|---|---|---|
| 20370 | 373 | Il segnale raffigurato indica un divieto di sosta per le biciclette | The sign shown indicates a no-stopping prohibition for bicycles | The sign shown indicates a no-parking prohibition for bicycles |
| 21608 | 63 | Il segnale raffigurato vieta la sosta | The sign shown prohibits stopping | The sign shown prohibits parking |
| 21959 | 414 | Il delineatore raffigurato indica un divieto di sosta | The delineator shown indicates a no-stopping prohibition | The delineator shown indicates a no-parking prohibition |
| 20754 | 429 | Le frecce direzionali in figura sono di colore giallo nelle strade dove è vietata la sosta | The directional arrows shown in the figure are yellow on roads where stopping is prohibited | The directional arrows shown in the figure are yellow on roads where parking is prohibited |
| 20939 | 466 | La striscia bianca laterale discontinua in figura significa che la sosta non è possibile | The broken white lateral line in the figure means that stopping is not possible | The broken white lateral line in the figure means that parking is not possible |
| 21263 | 21 | Il segnale raffigurato si trova su strade dove la sosta è consentita dopo le ore 19.00 | The sign shown is located on roads where stopping is permitted after 19.00 | The sign shown is located on roads where parking is permitted after 19.00 |
| 21300 | 26 | Il segnale raffigurato indica che svoltando nel senso della freccia la sosta è consentita solo a sinistra | The sign shown indicates that turning in the direction of the arrow, stopping is permitted only on the left | The sign shown indicates that, after turning in the direction of the arrow, parking is permitted only on the left |
| 18829 | 462 | Il conducente di un veicolo diverso dai taxi può sostare nei posteggi riservati ai taxi dalle ore 20.00 alle ore 8.00 | The driver of a vehicle other than a taxi may stop in parking areas reserved for taxis from 20:00 to 8:00 | The driver of a vehicle other than a taxi may park in parking areas reserved for taxis from 20:00 to 8:00 |

Additional potential examples found by searching `sosta`/`sostare` alongside English `stop`/`stopping`: 18693, 20756, 20760, 20761, 20928, 21883 and 22673. Review their context before changing them. Emergency stopping (*sosta di emergenza*) is a separate context and is not counted as a finding merely because it says “stopping”. This list is not an exhaustive count of mistranslations.

### Chinese: direction of damage ambiguous or reversed

- **25064, PDF page 574.** Italian: `L'assicurazione per la responsabilità civile auto (R.C.A.), obbligatoria per legge, comprende il risarcimento dei danni provocati dal veicolo, purché guidato dal proprietario`. English correctly says `damage caused by the vehicle`. Chinese: `法律强制的机动车第三者责任险（R.C.A.）包括对车辆造成损失的赔偿，但须由车主本人驾驶`. `对车辆造成损失` can be read as damage caused **to** the vehicle, rather than damage caused **by** it. Suggested wording: `法律强制的机动车第三者责任险（R.C.A.）包括对该车辆造成的损失的赔偿，但须由车主本人驾驶`.

### Chinese: preceding road section rendered ambiguously

- **19901, PDF page 307.** Italian: `Il segnale raffigurato consente la sosta nel tratto precedente`. English: `The sign shown allows parking in the preceding stretch`. Chinese: `图中所示标志允许在前方之前的停车路段内停车`. `前方之前` is contradictory or unclear about which stretch is meant, and `停车路段` introduces a parking-designated section that is not specified in the source. Suggested wording: `图中所示标志允许在其前面的路段停车` (the stretch before the sign in the direction of travel).

## Method and limits

The canonical database contains 7,106 questions; all have nonempty English and Chinese fields. A programmatic scan covered all 7,106 rows for numerical token discrepancies and selected negation, direction and vehicle-term cues. Differences from formatting, translation of number words, or idiom were not treated as errors automatically. The findings above were checked against the cited PDF pages; the Italian source wording was extracted with PDFKit. Translation batch files are the build inputs, so fixes should be made there and the database rebuilt using the documented build procedure.

This was a targeted review and heuristic scan, **not a complete semantic verification of all 14,212 translations**. Matching numbers, cue words or nonempty fields does not establish correctness. The additional candidates require contextual review, and further translation errors may remain. No database or translation entries were changed in this review.
