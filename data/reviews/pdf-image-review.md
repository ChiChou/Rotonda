# Quiz image review against Patente AB.pdf

Reviewed 2026-11-03. Source: `Patente AB.pdf`, 590 pages; question IDs and one-based PDF page numbers below. `PatenteData/database/quiz.db` is the canonical data repository database. `Rotonda/Rotonda/Resources/patente.db` is the built app database inspected separately.

## PDF-to-question attachment comparison

A positional automated comparison matched all 7,106 PDF question-number rows against their question records. It associated the PDF image placed next to each question number, if any, and compared SHA-256 of its original JPEG stream to the referenced asset. Of these rows, 3,946 have PDF images: every one has the exact same JPEG bytes in both databases. The other 3,160 have no row image in the PDF. The canonical database nevertheless assigns an image to 295 of those rows, across multiple groups. The built app displays an image on 113 of those 295 rows. No source-image row was missing an image or had differing image bytes. These results are a source-fidelity check; an extra image is not automatically factually wrong, but it is not part of that question in the PDF.

The full list is `pdf-extra-question-images.csv`. For example, question 22863 on PDF page 510 concerns a one-way carriageway and has no image in the PDF. The built app attaches `637129125cd2.jpeg`, which depicts a two-way carriageway. The built app's construction uses `COALESCE(q.image, g.image)` (`Rotonda/Scripts/build_content_db.py`, line 164); consequently a null per-question image inherits an image from the group. This explains the 113 extra app images and can create misleading context in mixed-image groups. This review did not modify the database or build logic.

## Near-duplicate image candidates

- `8f0111b381f8.jpeg` and `b48111d338ed.jpeg` show the same no-entry sign with the same bus exception plate. The illustrations differ in size and positioning. Both appear on PDF page 487 in group 4373: the first is used by questions 22261 and 22266, the second by question 22267. They are a strong visual/semantic duplicate candidate; no merge was performed.

The search compared all 409 assets using resized pixel differences, with and without cropping white margins, and visually inspected the closest candidates and overview sheets. Similarity alone is not evidence of duplication: many illustrations differ only in a legally significant arrow, time plate, number, road marking, or vehicle letter. For example, `b44a1aa5ea99.jpeg` and `d768224469a1.jpeg` look almost identical but their plates indicate different day categories; `2a8cb20b2ed1.jpeg` and `baa788372c1b.jpeg` have different continuous/broken line placement and are tied to different questions. These must remain distinct. The single confirmed candidate above is not an exhaustive proof that no other visually equivalent assets exist; the automated similarity method can miss differences in scale, layout, or embedded whitespace.
