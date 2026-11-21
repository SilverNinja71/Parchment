# Contributing to BelloBook

Thanks for helping! BelloBook is a free iPad notes app, and it gets better every time someone points out something that was overlooked. You don't need to be an expert, and every kind of help counts:

- **Report a bug or suggest an idea:** [open an issue](../../issues/new/choose). Screenshots help a lot.
- **Draw:** icons, covers and the Personalization Kit always need love.
- **Improve the docs:** if something in the README confused you, it probably confuses others too.
- **Write code:** pick an open issue, or propose something new in an issue first.

## Getting the project running

You can work on BelloBook **with or without Xcode**.

### With Xcode (Mac)
1. Install Xcode 16 or newer.
2. Open `Parchment.xcodeproj`.
3. In **Signing & Capabilities**, choose your own team and change the bundle ID from `com.example.parchment`.
4. Run on an iPad or an iPad simulator.

### Without Xcode (Swift Playgrounds on iPad)
1. On a Mac, run `zsh Tools/make_playground.sh`. It builds `Playground/Parchment.swiftpm.zip` from the `Parchment/` folder.
2. AirDrop the zip to an iPad, unzip it in Files, and open it in **Swift Playgrounds** (free from Apple).

Always edit the code in `Parchment/`, never in `Playground/`, which is generated and rebuilt each time.

### Checking your code without Xcode
```bash
zsh Tools/typecheck.sh
```
This catches most compile errors using only the free Command Line Tools (`xcode-select --install`).

### Testing the Work Checker
The checker exists twice: in Swift for the iPad app and in JavaScript for the web version. Each has a test suite, and the two are meant to give the same verdicts, so a change to one usually needs the same change in the other.

```bash
swiftc -parse-as-library -o /tmp/work_checker_test Tools/test_work_checker.swift Parchment/Editor/WorkChecker.swift Parchment/Editor/InkTools.swift && /tmp/work_checker_test
```

```bash
node Tools/test_web_checker.js
```

When you fix a wrong verdict, add the line that was judged wrongly to both suites. A checker that flags correct work is worse than one that misses a slip, so when a line can't be judged for certain, leave it unjudged.

## Project layout

| Folder | What's in it |
| --- | --- |
| `Parchment/App` | App entry, sidebar, settings storage, design tokens (`Style.swift`) |
| `Parchment/Model` | Notebooks, pages, covers, storage, the `.parchment` file format |
| `Parchment/Editor` | The writing canvas (PencilKit), paper, toolbar, page list, welcome tour, Work Checker, Textbook view, Media Vault |
| `Parchment/Library` | Library grid, New Notebook, cover studio and Cover Library |
| `Parchment/PDF` | PDF import, export and page rendering |
| `Parchment/Study` | Recall practice, flashcards, spaced repetition, Anki export, audio deck |
| `Parchment/Sync` | iCloud Drive, OneDrive, Google Drive, Dropbox, WebDAV, self-hosted server, Obsidian vault, library backup |
| `Parchment/Personalization` | The hand-drawn Personalization Kit |
| `Tools` | Mac command-line helpers (kit generator, playground packager, type-check) and the Work Checker tests |
| `docs` | The web version (`index.html`, `parchment-web.js`, `parchment-web.css`), privacy policy, App Store listing |

## Guidelines

- **Keep it free.** BelloBook has no ads, subscriptions or paywalls, and won't add them.
- **Keep it private.** Handwriting recognition runs on the device. Don't add analytics or send notes to servers.
- **Keep old notebooks working.** New fields on `Notebook`, `Page` or `NotebookArchive` must be optional (or have defaults) so existing `.parchment` files still open.
- **Match the look.** Use the colors, corner radii, shadows and spring animation in `Parchment/App/Style.swift`.
- **Match the surrounding code.** Same naming, comment style and structure as the files around it.
- **No secrets in code.** Cloud client IDs in `CloudCredentials.swift` are public placeholders; never commit client secrets or personal tokens.
- **Small pull requests** are easier to review. One feature or fix per PR.

## Making a pull request

1. Fork the repo and create a branch: `git checkout -b fix-pdf-export`.
2. Make your change and run `zsh Tools/typecheck.sh`, plus the Work Checker tests if you touched the checker.
3. Commit with a clear message, push your branch, and open a pull request explaining what changed and how you tested it (screenshots for UI changes).

## License

By contributing, you agree that your contributions are licensed under the [Mozilla Public License 2.0](LICENSE).
