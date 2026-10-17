# Reference transcription rules

The expected answer for each fixture follows the Worker's own instructions (`INSTRUCTIONS` in
`src/label.ts`), plus these rules for cases the Worker's prompt doesn't spell out yet. The
reference script sends both to Claude, and people checking fixtures by eye use the same list.

1. **Several value columns** (`100g当たり` next to `大さじ1杯18g当たり`, or `1食分50g` next to
   `牛乳200mlをかけた場合`): transcribe the **first** column, the food as sold. Natto panels that
   give the set with たれ first and `( )内は納豆のみ` second: the first values, without the brackets.
2. **Breakdowns of one value** (`食塩相当量 4.7g (めん・かやく 2.2g)(スープ 2.5g)`, or
   `参考値` energy splits printed under the panel): only the total. Don't add the parts as lines.
3. **Anything printed in the panel that isn't one of the named nutrients** (コレステロール, カルシウム,
   カリウム, vitamins, イソフラボン, n-3系脂肪酸, 純アルコール量 …): a line with nutrient `other`. These are
   shown in the report but don't count towards the score.
4. **Panels that aren't Japanese** (a Canadian "Nutrition Facts", an EU multilingual table, a
   Taiwanese 營養標示): `panelFound: false`. So is a photo where no panel can be read.
5. **Values that can't be read** with confidence: leave the line out and say so in the fixture's
   `notes`. A reference must never guess.
6. **Ranges**: `0〜1.6g` is `minValue 0, maxValue 1.6`. `0.1~1.4mg` likewise.
7. **`basisText`** is copied as printed, without `栄養成分表示` and the outer brackets, keeping
   full-width brackets and the original wording (`1袋（標準58g）当たり`, `1缶当り・液汁含む`).
8. **`netContentsUnit`** is `none` whenever `netContentsAmount` is 0.
9. **`productName`** is what the photo shows, or empty. It isn't scored.
