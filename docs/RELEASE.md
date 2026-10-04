# リリース手順（Android APK）

## 1.0.0-rc1（M3 見た目と音 + M4 コンテンツ）

- versionCode 7 / versionName `1.0.0-rc1`、同じ鍵で署名。実機で60fps（docs/M3.md）を確かめたら `1.0.0` にする
- 起動するとタイトル（初回は「酔いやすい方向け」の選択）。Play を押せばすぐ走れる
- 16コース（朝の屋上・工事中の高層・夕方の繁華街・夜の駅前）＋フリーラン。メダル・自己ベスト・ゴースト（人形、遠いと矢印）
- 一時停止（リトライ／チェックポイント／設定／終了）、ゴールの結果、リプレイ（1人称／3人称）
- 見た目：白い街とルートカラー（遠くは強く、近くは淡く。設定でOFF）、時間帯ごとの空・霧・影、スピードライン・ビネット・塵、照準点
- 音：風切り・素材別の足音・息づかい・手の音・着地3段階・Perfect、勢い値で重なるBGM
- 設定画面：酔い対策の全項目、感度、振動、ルートカラー、画質、解像度、フレームレート、音量
- ローリングの後半にしゃがむとスライドへつながる

## 0.6.0-beta（M2 技の完成）

- versionCode 6 / versionName `0.6.0-beta`、同じ鍵で署名
- リトライを押して離すとスタートへ、0.3秒押し続けるとチェックポイントへ（計測は続く）。戻る瞬間に白から素早く戻す
- 縦ウォールランから縁を登った後に止まっていたのを修正（駆け込んだ速さで登りきる）
- スモークテストにM2ゲート（技のつながりで減速しない）、リトライの時間の確認を追加

## 0.5.0-beta

- versionCode 5 / versionName `0.5.0-beta`、同じ鍵で署名
- ローリング成功で速度+10%
- Perfect判定（着地ジャンプ・ローリング・ヴォルト・壁ジャンプ・スライドジャンプ）：速度+3%、勢い値、縁の光、0.04 sのスロー
- 勢い値：技を繋ぐほど速度の上限が上がる（11.5→15 m/s）。画面の縁の光で見える
- 慣性の制御：逆に倒すとブレーキ（地上・スライド・空中）、空中で入力なしなら勢いを保つ、クイックターン（X / Q）
- ゴールの結果（メダル・次のメダルまで・最高速度・Perfect数）、区間タイム差、自己ベストのゴースト

## 0.4.0-beta

- versionCode 4 / versionName `0.4.0-beta`、同じ鍵で署名
- 高所から落ちた時の硬直と減速を廃止（揺れ・振動・着地の沈み込みは残す）

## 0.3.0-beta

- versionCode 3 / versionName `0.3.0-beta`、同じ鍵で署名（上書き更新できる）
- 速度を全体で+33%（走り 7.5→10 m/s、上限 12→15 m/s）。コースの間隔も1.33倍
- 階段を見えない坂で滑らかにした（段ごとに体が0.4 m跳ねて詰まっていた）。上りきった所で一瞬空中扱いになるのも修正
- 単発の段差を乗り越えた時、目線が一度沈んでから跳ねていたのを修正
- 縦ウォールランを遠くからでも出せるようにした（判定距離を速度に比例、ジャンプ後0.5 s以内に壁に着けば空中からも可）
- ウォールランに張り付いた時、跳んだ勢いを上向き5 m/sまで残す（以前は4 m/sで頭打ち）

## 0.2.0-beta

- versionCode 2 / versionName `0.2.0-beta`、署名は 0.1.0-beta と同じ鍵（上書き更新できる）
- 追加: クライム、レッジグラブ（ぶら下がり・横移動）、ウォールラン（横・縦）、壁ジャンプ、スライド、スライドジャンプ、チェックポイント、コース後半
- 修正: 階段で数段おきに段の縁へ激突していた（揺れ・振動・減速が出ていた）

## 0.1.0-beta（M1 手触り検証版）

- パッケージ: `com.parpqrq.parkour` / versionCode 1 / versionName `0.1.0-beta`
- arm64-v8a のみ、Vulkan必須、Godot 4.7.2 / Mobileレンダラー
- 署名証明書 SHA-256: `5cfc9a363f5b3814899bd53bd4f048964bcd5521e1d2953056bd43a19e7ec3d7`
- 中身: M1（走り・ジャンプ・ヴォルト・ローリング・ハードランディング、手触り4層、調整パネル、計測コース）

## 署名鍵

`parkour-release.keystore`（alias `parkour`）は**リポジトリに入れない**。持ち主が保管する。
鍵を失くすと、同じアプリとして更新できなくなる（入れ直しが必要になる）。

## ビルド

1. エディタの「エクスポートテンプレートの管理」で 4.7.2 のテンプレートを入れる。エディタ設定で Android SDK と Java SDK のパスを指定する（docs/M0.md）。
2. `export_presets.cfg` の `version/code` を1つ上げ、`version/name` を更新する。
3. 鍵を環境変数で渡して書き出す（パスワードをファイルに残さない）:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/parkour-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=parkour
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
godot --headless --path . --export-release "Android" build/android/parkour-<version>.apk
```

4. 確認: `apksigner verify --print-certs build/android/parkour-<version>.apk` の SHA-256 が上と一致すること。
5. 書き出す前にテストを通す:
   - `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn`（技の数値）
   - `godot --headless --path . --fixed-fps 60 res://tests/course_test.tscn`（全コースを走りきれるか）
   - `godot --headless --path . --fixed-fps 60 res://tests/flow_test.tscn`（画面の流れ）

## インストール

端末で「提供元不明のアプリ」を許可してAPKを開く。またはPCから `adb install -r parkour-<version>.apk`。
