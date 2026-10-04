# リリース手順（Android APK）

## 1.1.0-beta（M5 新しい技と隠れた近道：docs/M5.md）

- versionCode 8 / versionName `1.1.0-beta`。新しい技とコースは持ち主がまだ走っていないので beta
- **署名鍵をまた新しくした**（1.0.0-rc1 の鍵がこの環境に無かったため）。1.0.0-rc1 から上書き更新できない。**一度アンインストールしてから入れる**（自己ベスト・ゴースト・設定は消える）。
  鍵とパスワードは持ち主に渡した。次からは下の「次の版を同じ鍵で出す」のとおり環境変数に入れておけば、上書き更新できる
- APK 33.5 MB（arm64-v8a、targetSdk 36）。署名 v2 + v3
- 新しい技：ウォールキック（壁に触れた瞬間にジャンプ。壁へ倒すと上へ伸びる）、縦ウォールランの頂点での蹴り上がり、ヴォルトジャンプ、スイングバー、ジップライン、ぶら下がりからの後ろ跳び。どれもPerfectあり
- 縦ウォールラン中に壁の方へ倒してジャンプすると、後ろへではなく上へ蹴る（後ろへはスティックを倒さずにジャンプ、またはクイックターン）
- 全16コースに色の付いていない近道を2〜6本（足場・室外機・塔屋と電線・高い壁）。見つけると記録され、結果とコース選択に「shortcuts n / m」
- ゴールド以上を取ると、まだ見つけていない近道の入口に金色の目印が1つ出る
- メダルを付け直した：開発者は近道が必要、ゴールドは主ルートで取れる
- フリーランにジップラインとスイングバー
- 操作説明に新しい技を追加（2列）。調整パネルが整数の値にも対応

## 1.0.0-rc1（M3 見た目と音 + M4 コンテンツ）

- versionCode 7 / versionName `1.0.0-rc1`。実機で60fps（docs/M3.md）を確かめたら `1.0.0` にする
- **署名鍵を新しくした**（下の「署名鍵」）。0.5.0-beta 以前の鍵とは別なので上書き更新できない。**一度アンインストールしてから入れる**（自己ベスト・ゴースト・設定は消える）
- APK 33.5 MB（arm64-v8a、targetSdk 36）。署名 v2 + v3
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

`parkour-release.keystore`（alias `parkour`、PKCS12、RSA 4096）は**リポジトリに入れない**。持ち主が保管する。パスワードも同じく。
鍵を失くすと、同じアプリとして更新できなくなる（入れ直しが必要になる）。

| 使った版 | 証明書 SHA-256 |
| --- | --- |
| 1.1.0-beta から（今の鍵。DN `CN=Parkour, O=parpqrq`、2054年まで有効） | `008eebfe0d64e09434d7ff151cef4a4ae0fcda7a05daa4dd29e4fa78ce154825` |
| 1.0.0-rc1（手元に無く、作り直した） | `904d7ff87217625dc1405028edb0a7df7349199f55eb05bb5325a1843252ce6f` |
| 0.1.0-beta〜0.5.0-beta（手元に無く、作り直した） | `5cfc9a363f5b3814899bd53bd4f048964bcd5521e1d2953056bd43a19e7ec3d7` |

### 次の版を同じ鍵で出す（クラウドのセッションから）

クラウドのセッションは毎回まっさらな環境なので、鍵を置いておかないと毎回作り直しになる（＝毎回アンインストールが必要になる）。
**クラウド環境の設定（セッションのタイトルバーの環境メニュー → Edit）の環境変数**に次の2つを入れておく。チャットには貼らない。

| 変数 | 中身 |
| --- | --- |
| `PARKOUR_KEYSTORE_B64` | `parkour-release.keystore.b64` の中身（鍵ファイルを base64 にした1行） |
| `PARKOUR_KEYSTORE_PASSWORD` | `password.txt` の中身 |

セッション側はこう使う（鍵はリポジトリの外に戻す）:

```sh
echo "$PARKOUR_KEYSTORE_B64" | base64 -d > /tmp/parkour-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/tmp/parkour-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=parkour
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PARKOUR_KEYSTORE_PASSWORD"
```

## ビルド

1. エディタの「エクスポートテンプレートの管理」で 4.7.2 のテンプレートを入れる。エディタ設定で Android SDK と Java SDK のパスを指定する（docs/M0.md）。
   クラウドのセッションでは:
   - テンプレート：`Godot_v4.7.2-stable_export_templates.tpz`（GitHub の 4.7.2-stable リリース）から `templates/android_*` と `templates/version.txt` だけを `~/.local/share/godot/export_templates/4.7.2.stable/` に展開する
   - Android SDK：command-line tools を `/opt/android-sdk/cmdline-tools/latest` に置き、`sdkmanager --sdk_root=/opt/android-sdk "platform-tools" "build-tools;36.1.0" "platforms;android-36"`（先に `--licenses`）
   - `~/.config/godot/editor_settings-4.7.tres` の `export/android/android_sdk_path` を `/opt/android-sdk`、`export/android/java_sdk_path` を入っている JDK（21で書き出せた）にする
2. `export_presets.cfg` の `version/code` を1つ上げ、`version/name` を更新する。
3. 鍵を環境変数で渡して書き出す（パスワードをファイルに残さない）:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/parkour-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=parkour
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
godot --headless --path . --export-release "Android" build/android/parkour-<version>.apk
```

4. 確認: `apksigner verify --print-certs build/android/parkour-<version>.apk` の SHA-256 が上の表（今の鍵）と一致すること。
   `aapt2 dump badging` で versionCode・versionName・`native-code: 'arm64-v8a'` を見る。
   書き出した中身で動くか：`godot --headless --path . --export-pack "Linux" build/check/parkour.pck` を作り、`xvfb-run -a godot --main-pack build/check/parkour.pck --audio-driver Dummy --quit-after 300`（タイトル）と、末尾に `res://scenes/levels/course.tscn` を付けた実行（コース）でスクリプトエラーが出ないこと
5. 書き出す前にテストを通す:
   - `godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn`（技の数値）
   - `godot --headless --path . --fixed-fps 60 res://tests/course_test.tscn`（全コースを走りきれるか）
   - `godot --headless --path . --fixed-fps 60 res://tests/flow_test.tscn`（画面の流れ）

## インストール

端末で「提供元不明のアプリ」を許可してAPKを開く。またはPCから `adb install -r parkour-<version>.apk`。
