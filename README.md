# Parchment

Parchment is a free, privacy-first handwriting and note-taking app for iPad. It has document and freeform canvases, on-device handwriting-to-text conversion, scratch-out gestures, spaced-repetition active recall, PDF annotation, and a fully customizable hand-drawn personalization kit. It's completely free, with no ads or subscriptions.

Parchment is a community project, and contributions of every size are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

- **Write** with Apple Pencil on lined, grid, dotted, dotted-lined or blank paper.
  - **Document** pages grow downward as you write.
  - **Freeform** pages are an endless canvas.
- **Tools**: pen (ballpoint, pen, fountain), highlighter, eraser (whole stroke or pixel), lasso, ruler, undo/redo.
- **Type text**: pick the **Type** tool and tap anywhere to add a text box, using the on-screen keyboard or a hardware keyboard. On Document pages, text boxes span the page and wrap like paragraphs.
- **MyScript-style gestures**:
  - Scribble over ink to erase it (scratch-out).
  - Double-tap Apple Pencil to switch to the eraser.
  - Apple Pencil writes and your finger scrolls (turn on *Draw with Finger* to write with a finger).
- **Convert to text**: circle handwriting with the Convert tool and it becomes typed text. Recognition runs on the iPad with Apple's Vision framework, so it's free and private.
  - **Reflowing text**: on Document pages, converted text becomes a paragraph that spans the page and rewraps as it grows. Converting the line right below a paragraph continues that paragraph.
  - **Live Text**: while you write on a Document page, a chip at the bottom shows what Parchment reads from your current line. Tap **Convert** to turn it into text in one step. Turn it off in Settings.
- **Solve math**: circle a handwritten calculation with the **Solve** tool. It handles + − × ÷, powers, square roots, percent, π and parentheses. You can fix misread symbols before solving. **Add Answer** writes "= answer" beside your handwriting; **Convert** types the whole thing.
- **Clean up diagrams**: circle rough shapes with the **Shapes** tool and Parchment redraws them neatly in the same ink: straight lines (snapped level or upright when close), circles, ellipses, triangles, rectangles and polygons. Undo restores your original strokes.
- **Search inside handwriting**: the library search also finds words you wrote by hand and typed text. Tap a result to jump to that page. Parchment reads your pages in the background on the iPad; the search index never leaves your device.
- **Study, built on active recall**:
  - **Recall Practice**: pick a subject or notebook. Each page appears with a timer so you can memorize it. Tap **Hide & Rewrite**, the page turns white, and you rewrite everything from memory. Tap **Done** to see the original and your rewrite side by side, then rate yourself 1–5.
  - **Flashcards (like Anki)**: decks with New and Due counts. You see the front, flip it, write the answer from memory, and tap a 1–5 rating at the bottom. **Done** then shows the correct answer next to yours.
  - Both use spaced repetition: anything you rate 1–2 comes back in the same session, and things you know come back after longer and longer gaps. Each rating button shows when you'll see it next.
- **Covers**:
  - The two-pane **New Notebook** screen has the notebook details on the left and a live 3D cover you can tilt on the right.
  - Cover options: 8 named colors, 6 finishes (Smooth, Leather, Linen, Grid Emboss, Geometric, My Doodle), a **Cover Library** of 16 designs in 4 categories, or your own photo.
  - Change a cover any time: the palette button on a notebook card, **Customize Cover** when you long-press a notebook, or the palette button in the editor.
- **Paper**: Lined, Grid, Dotted, Blank and **Dotted-Lined**, a solid baseline with a dashed midline for neat handwriting. You pick paper from visual cards that show the real pattern.
- **Welcome to Parchment**: on first launch, a 4-page hands-on notebook walks you through scratch-out, convert to text, paper styles and covers, with a pulsing spotlight on each tool.
- **Subjects**: a Notability-style sidebar files notebooks into subjects, and lets you study a whole subject at once.
- **Import PDFs** and write on them. Export any notebook as a PDF or as a `.parchment` file you can AirDrop.
- **Sync** to iCloud Drive, OneDrive, Google Drive, Dropbox, WebDAV/Nextcloud, or any storage app in the Files app (Box, pCloud, Proton Drive…). You sign in, then save notes in any folder you choose. You can **sync to several places at once**, and each one keeps a full copy.
- **Personalization Kit**: a sheet you draw on to replace the app's name, logo, toolbar icons, notebook covers and title lettering with your own drawings.

---

## 1. Put it on your iPad

### Option A — no Xcode: Swift Playgrounds on the iPad

Swift Playgrounds is Apple's free app that builds and runs real apps right on an iPad. It uses no space on your Mac.

1. On the iPad, install **Swift Playgrounds** from the App Store. Parchment needs iPadOS 17 or later.
2. On a Mac, run `zsh Tools/make_playground.sh` to build `Playground/Parchment.swiftpm.zip`, then AirDrop the zip to the iPad. In Finder, right-click it → **Share** → **AirDrop**.
3. On the iPad, open the **Files** app → **Downloads**. Tap the zip to unzip it, then tap **Parchment**. It opens in Swift Playgrounds.
   - No AirDrop? Copy the zip into iCloud Drive on the Mac, then open it from Files on the iPad.
4. Tap **Run** (▶). The first build takes a minute. Tap the full-screen button to use it like a normal app.

Your notebooks are saved inside Parchment between runs.

**Differences from an Xcode build:**
- Parchment runs inside Swift Playgrounds, so it doesn't get its own Home Screen icon.
  - The fix is a paid Apple Developer account. Then, in Swift Playgrounds, tap **App Settings → Upload to App Store Connect** and install it from TestFlight.
- Files can't open in Parchment straight from AirDrop or other apps. Use the **Import** button in the library instead.

If you change the code on the Mac, rebuild the package and AirDrop the new zip:

```bash
zsh Tools/make_playground.sh
```

### Option B — Xcode on a Mac

You need **Xcode 16 or newer**. It needs about 40 GB of free space. Xcode can also live on an external SSD: download it from <https://developer.apple.com/download/applications/> and expand it onto the drive.

1. Open `Parchment.xcodeproj` in Xcode.
2. Click the **Parchment** project → **Parchment** target → **Signing & Capabilities**:
   - **Team**: choose your Apple Account. A free account works, but the app expires after 7 days. A paid developer account lasts a year.
   - **Bundle Identifier**: change `com.example.parchment` to something unique, e.g. `com.yourname.parchment`.
3. Plug in your iPad and trust the Mac. Turn on **Settings → Privacy & Security → Developer Mode** on the iPad.
4. Pick your iPad at the top of Xcode and press **Run** (⌘R).

The Xcode build gets its own Home Screen icon. AirDropped kits and `.parchment` files also open in it directly.

## 2. Personalize it (AirDrop the kit)

The kit is already generated in [`Kit/`](Kit/):

| File | What it's for |
| --- | --- |
| `Parchment Personalization Kit.parchmentkit` | AirDrop this to your iPad. It opens straight in Parchment. |
| `Parchment Personalization Kit (preview).pdf` | The same pages as a regular PDF, to preview or print. |

Every box shows Parchment's current look faintly — the standard icon, the "Parchment" title, the app logo, the cover colors and each letter — so you can see what you're replacing. Trace over it, change it, or ignore it; only your ink is used.

It has 5 pages and 107 boxes:

1. **Your mark & toolbar**: the app's name, a logo, and 18 icons (pen, highlighter, eraser, lasso, convert, ruler, undo, redo, add page, pages, share, more, library, new notebook, import PDF, sync, settings, delete).
2. **Covers & doodles**: 6 notebook covers and a doodle for the empty library.
3. **A–Z**: your capital letters.
4. **a–z, 0–9**: your lowercase letters and numbers. Parchment uses these to write notebook titles in your handwriting.
5. **Study & subjects**:
   - 12 more icons (study, flashcards, recall, timer, flip, hide, show answer, done, next, subjects, deck, all notes)
   - your own **1–5 rating buttons**
   - a doodle for **"All caught up!"**

**How to use it:**

1. Install Parchment on the iPad first (step 1).
2. AirDrop a kit file to the iPad:
   - **Swift Playgrounds (Option A):** AirDrop the **preview PDF**. Save it to Files, then in Parchment tap **Import** and choose it. Parchment recognizes it as a kit.
   - **Xcode build (Option B):** AirDrop the `.parchmentkit` file. It opens straight into Parchment.
3. It opens as a notebook with a **Kit** badge. Draw inside each dashed box. Ink outside a box is ignored.
4. Tap **Apply to Parchment**. Your drawings replace the standard look right away. You can edit the kit and apply again any time.

No AirDrop handy? Go to **Settings → Personalize Parchment → Start a Personalization Kit** on the iPad.

**Drew it in Procreate (or another app)?**
1. Export each finished page as a PNG, JPEG or PDF. Export the whole page at its full size, with your drawing on top of the kit.
2. In Parchment, go to **Settings → Personalize → Import Pages Drawn in Procreate or Other Apps** and pick the files.
3. Parchment works out which page each one is and keeps only your ink. Boxes you left empty keep Parchment's standard look.

Darker ink works best. Very pale colors can get filtered out along with the faint guides.

If you leave the logo box empty, Parchment uses its standard logo in its own colors.

Under Settings → Personalize you can also:
- turn your icons or handwritten titles on and off
- keep your ink colors on icons
- reset to the standard look

To regenerate the kit after changing its layout (`Parchment/Personalization/KitLayout.swift`):

```bash
swiftc -O -o /tmp/kitgen Tools/KitGen/*.swift Parchment/Personalization/KitLayout.swift Parchment/Personalization/KitPDFRenderer.swift Parchment/Model/Notebook.swift && /tmp/kitgen Kit
```

## 3. Turn on sync

On the iPad: **Settings → Sync**, then tap a service.

| Service | Sign-in | Developer setup |
| --- | --- | --- |
| **iCloud Drive** | The Apple Account already on the iPad. Pick any folder. | None |
| **Other Apps** (Box, pCloud, Proton Drive, Synology…) | Inside that provider's own app. Then pick any of its folders in the Files picker. | None |
| **WebDAV / Nextcloud** | Server address, username, app password | None |
| **OneDrive** | Microsoft sign-in page | Free app ID, see below |
| **Google Drive** | Google sign-in page | Free app ID, see below |
| **Dropbox** | Dropbox sign-in page | Free app key, see below |

After signing in you can browse your folders, make a new one, and tap **Save Notes in "…"**.

Each notebook is saved as one `.parchment` file in that folder.

**How sync works:**
- Notebooks you change on the iPad are uploaded.
- Files changed somewhere else (like another iPad) are downloaded.
- If a notebook changed in both places, the cloud copy is kept as "(conflict)" so nothing is lost.
- Deleting a notebook on the iPad never deletes the cloud copy.
- When *Sync Automatically* is on, Parchment syncs 15 seconds after you stop writing, and again when you open or leave the app.
- Turn on *Also Save PDF Copies* to save a readable PDF next to each notebook.

OneDrive, Google and Dropbox each need you to register Parchment once with them, for free. Each one gives you an ID to paste into [`Parchment/Sync/CloudCredentials.swift`](Parchment/Sync/CloudCredentials.swift). These are public IDs and Parchment never uses client secrets. Until you add an ID, tapping that service explains what's missing.

### OneDrive (Microsoft)

1. Go to <https://entra.microsoft.com> → **App registrations** → **New registration**.
2. **Name**: Parchment. **Supported account types**: *Accounts in any organizational directory and personal Microsoft accounts*.
3. Leave the Redirect URI blank and click **Register**. Then go to **Authentication → Add a platform → Mobile and desktop applications** and tick the redirect URI that looks like `msal<your client ID>://auth`.
4. **API permissions** → Add → Microsoft Graph → *Delegated* → `Files.ReadWrite`, `User.Read`, `offline_access`.
5. Copy the **Application (client) ID** into `oneDriveClientID`.

### Google Drive

1. Go to <https://console.cloud.google.com> and create a project.
2. **APIs & Services → Library** → enable **Google Drive API**.
3. **OAuth consent screen**:
   - choose **External** and fill in the app name
   - add the scope `https://www.googleapis.com/auth/drive`
   - add your own Google account under **Test users**
4. **Credentials → Create credentials → OAuth client ID** → type **iOS** → enter `com.example.parchment` (or your own bundle ID).
5. Copy the **Client ID** (ends in `.apps.googleusercontent.com`) into `googleClientID`.

> Google treats full-Drive access as a "restricted" scope. It works right away for up to 100 test users. To publish publicly, Google requires a verification review.
>
> To avoid that, you can switch the scope in `GoogleDriveProvider.swift` to `drive.file`. The catch: Parchment could then only see folders it created itself.

### Dropbox

1. Go to <https://www.dropbox.com/developers/apps> → **Create app** → *Scoped access* → **Full Dropbox** → name it.
2. On the **Permissions** tab, tick these and click **Submit**:
   - `account_info.read`
   - `files.metadata.read`
   - `files.content.read`
   - `files.content.write`
3. On the **Settings** tab, copy the **App key** into `dropboxAppKey`.
4. If Dropbox reports an invalid redirect URI when you sign in, add `db-<APP KEY>://2/token` under **OAuth 2 → Redirect URIs**.

Development apps work for up to 500 users. Apply for production in the console when you're ready to share it widely.

---

## How it's built

SwiftUI and PencilKit, iPadOS 17+, with no third-party dependencies.

The project uses Xcode's synced folders, so any new `.swift` file you add under `Parchment/` is compiled automatically.

```
Parchment/
  App/              App entry, settings, opening AirDropped/imported files
  Model/            Notebook & page model, on-device storage, .parchment archive format
  Library/          Library grid, new notebook sheet, covers
  Editor/           Canvas (PencilKit), paper, toolbar, page list, scratch-out, convert-to-text
  PDF/              PDF import, PDF rendering, PDF export
  Sync/             Sync engine + iCloud/Files, OneDrive, Google Drive, Dropbox, WebDAV providers, OAuth
  Settings/         Settings, Sync settings, folder browser, Personalize settings
  Study/            Recall practice, Anki-style flashcards, spaced-repetition scheduling
  Personalization/  Kit layout (shared with the Mac tool), kit PDF, extracting drawings, themed icons/text
Tools/              Mac command-line tools: kit generator, app icon generator, Swift Playgrounds packager
Kit/                The ready-to-AirDrop Personalization Kit
Playground/         Generated Swift Playgrounds package (Parchment.swiftpm + zip); don't edit, re-run the packager
```

**Storage**:
- On the iPad, each notebook is a folder: a manifest plus one PencilKit drawing per page, so saving a stroke only rewrites one small file.
- For sharing and sync, a notebook is packed into a single `.parchment` file. It's a binary property list holding the drawings and any PDF.

## What's different from MyScript (for now)

MyScript's recognition engine is proprietary and paid. Parchment uses Apple's built-in Vision recognition instead, which runs free and offline on the iPad. That affects a few things:
- **Math** covers arithmetic written on one line. Fractions written as stacked numbers, equations with unknowns (solving for x), and calculus aren't supported yet.
- **Diagrams** are cleaned up shape by shape. Arrows, connectors and text inside shapes aren't recognized yet.
- **Live Text** reads one line at a time and works best with clear, medium-sized handwriting.

Ideas and pull requests to improve any of these are very welcome.

## Publishing to the App Store

[docs/AppStore.md](docs/AppStore.md) has the full listing (name, description, keywords, screenshots, review notes) and a checklist. The privacy policy is [docs/privacy.html](docs/privacy.html); turn on GitHub Pages (Settings → Pages → `main` branch, `/docs` folder) to publish it at a public link.

Until OneDrive, Google Drive and Dropbox app IDs are added to `CloudCredentials.swift`, those three services are hidden in the app, so there are no buttons that don't work.

## Contributing

Bug reports, ideas, code, icons and docs are all welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Parchment is licensed under the [Mozilla Public License 2.0](LICENSE).
