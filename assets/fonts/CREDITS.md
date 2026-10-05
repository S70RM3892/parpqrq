# 画面の文字（フォント）

どちらも SIL Open Font License 1.1（OFL）。ライセンス全文は同じフォルダの `OFL-*.txt`。再配布・同梱してよい（フォント単体での販売は不可）。
Google Fonts のリポジトリ（`ofl/` 以下）から落とした。使い方は `scripts/ui/ui_theme.gd`。

| ファイル | フォント | 作者 | 使う所 |
| --- | --- | --- | --- |
| `Oswald.ttf` | [Oswald](https://fonts.google.com/specimen/Oswald)（可変、太さ 200〜700） | The Oswald Project Authors（Copyright 2016） | 見出し・ボタン・数字・ロゴ。太さ 700（見出し）と 600（数字）で使う。日本語の字は無いので Zen Kaku Gothic New の太字に落ちる |
| `ZenKakuGothicNew-Regular.ttf` | [Zen Kaku Gothic New](https://fonts.google.com/specimen/Zen+Kaku+Gothic+New) | The Zen Kaku Gothic Project Authors（Copyright 2022） | 本文（日本語の字を含む） |
| `ZenKakuGothicNew-Bold.ttf` | 同上 | 同上 | 強調・ボタンの日本語・見出しの日本語の代わり |

- 数字は Oswald の幅がまちまち（OpenType の `tnum` が無い）なので、タイムは `scripts/ui/tabular_text.gd` が数字を同じ幅の升目に置いて数え上げでも揺れないようにする。
- 取り直し：`https://raw.githubusercontent.com/google/fonts/main/ofl/oswald/Oswald%5Bwght%5D.ttf`、`.../ofl/zenkakugothicnew/ZenKakuGothicNew-{Regular,Bold}.ttf`（`OFL.txt` も同じフォルダ）。
