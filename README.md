# MacRecode 🎙️

MacOS用のシステム音声・マイク録音アプリケーション

## 📱 概要

MacRecodeは、macOS上でシステム音声とマイク音声を録音できるSwiftUIアプリケーションです。ScreenCaptureKitとAVFoundationを使用して、高品質な音声録音を実現しています。

## ✨ 機能

### 🎯 録音モード
- **システム音声のみ録音**: macOS全体のシステム音声を録音
- **マイクのみ録音**: マイクからの音声のみを録音  
- **ミックス録音**: システム音声とマイクを同時録音（開発中）

### 💾 ファイル機能
- CAF/PCM形式での高品質録音
- ファイル保存ダイアログによる任意の場所への保存
- ファイル名のカスタマイズ対応

### 🔒 セキュリティ
- macOS App Sandbox対応
- 画面録画権限の自動管理
- マイクアクセス権限の自動管理
- セキュアな録音プロセス

## 🛠️ 技術要件

### システム要件
- **macOS**: 13.0 (Ventura) 以降
- **Xcode**: 15.0 以降
- **Swift**: 5.0 以降

### 使用技術
- **SwiftUI**: ユーザーインターフェース
- **ScreenCaptureKit**: システム音声キャプチャ (macOS 13.0+)
- **AVFoundation**: マイク音声録音とファイル処理
- **AVAudioEngine**: 音声データ処理
- **UniformTypeIdentifiers**: ファイルタイプ管理

## 🚀 セットアップ

### 1. リポジトリのクローン
```bash
git clone https://github.com/Riti0208/MacRecode.git
cd MacRecode
```

### 2. Xcodeでプロジェクトを開く
```bash
open MacRecode.xcodeproj
```

### 3. ビルドと実行
1. Xcodeでターゲットを「MacRecode」に設定
2. ⌘+R でビルド・実行

## 🔧 開発環境での設定

### 権限の設定
初回実行時に以下の権限が必要です：

1. **画面録画権限** (システム音声録音用)
   - システム環境設定 > プライバシーとセキュリティ > 画面録画
   
2. **マイクアクセス権限** (マイク録音用)
   - システム環境設定 > プライバシーとセキュリティ > マイク

### テストの実行
```bash
# Swift Package Manager
swift test

# または Xcode内で ⌘+U
```

## 📁 プロジェクト構造

```
MacRecode/
├── MacRecode/
│   ├── MacRecodeApp.swift          # アプリエントリーポイント
│   ├── ContentView.swift           # メインUI
│   ├── SystemAudioRecorder.swift   # 録音機能の中核
│   ├── Info.plist                  # アプリ情報・権限設定
│   └── MacRecode.entitlements      # App Sandbox設定
├── MacRecodeTests/
│   └── SystemAudioRecorderTests.swift  # ユニットテスト
└── .github/
    ├── workflows/ci.yml            # CI/CD設定
    └── ISSUE_TEMPLATE/             # Issue テンプレート
```

## 🎨 使用方法

### 基本的な録音手順
1. アプリを起動
2. 録音モードを選択（システム音声のみ/マイクのみ/ミックス）
3. 「録音開始」ボタンをクリック
4. 録音中は赤い●が表示される
5. 「録音停止」ボタンで録音終了
6. ファイル保存ダイアログでファイル名と保存場所を指定

### 注意事項
- **ミックス録音使用時**: ヘッドフォン/イヤホンの使用を推奨（音響フィードバック回避のため）
- **システム音声録音**: 初回利用時に画面録画権限の許可が必要
- **マイク録音**: 初回利用時にマイクアクセス権限の許可が必要

## 🧪 テスト

### ユニットテスト
```bash
# 全テスト実行
swift test

# 特定のテストクラス実行
swift test --filter SystemAudioRecorderTests
```

### 手動テスト項目
- [ ] システム音声のみ録音が正常に動作する
- [ ] マイクのみ録音が正常に動作する
- [ ] ファイル保存が正常に動作する
- [ ] 権限エラーが適切に処理される
- [ ] UIが適切に状態を反映する

## 🤝 コントリビューション

### 開発フロー
1. Issueを作成して機能提案・バグ報告
2. フィーチャーブランチを作成
3. TDD方式で開発
4. Pull Requestを作成
5. コードレビュー
6. mainブランチにマージ

### コーディング規約
- SwiftLintに準拠
- 日本語コメント推奨
- テストカバレッジの維持
- セキュリティベストプラクティスの遵守

## 🔒 セキュリティ

### プライバシー保護
- 録音データはローカルに保存
- 外部への自動送信なし
- 適切な権限管理
- App Sandboxによる制限

### 脆弱性報告
セキュリティに関する問題を発見した場合は、公開のIssueではなく、プライベートな方法で報告してください。

## 📄 ライセンス

このプロジェクトは [MIT License](LICENSE) のもとで公開されています。

## 👨‍💻 作者

- **Riti** - [@Riti0208](https://github.com/Riti0208)

## 🙏 謝辞

- Apple ScreenCaptureKit フレームワーク
- macOS開発コミュニティ
- SwiftUI開発者の皆様

---

**MacRecode** - シンプルで高品質なmacOS音声録音アプリ 🎙️✨