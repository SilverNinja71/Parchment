# App Store listing (ready to paste)

Everything App Store Connect asks for, written for BelloBook. Character limits are Apple's.

## App information

| Field | Value |
| --- | --- |
| **Name** (30) | BelloBook — Handwritten Notes *(backup if taken: "BelloBook Notes")* |
| **Subtitle** (30) | Write, convert, study by hand |
| **Category** | Productivity *(secondary: Education)* |
| **Price** | Free |
| **Age rating** | 4+ (answer "None" to every question) |
| **Privacy policy URL** | https://silverninja71.github.io/Parchment/privacy.html |
| **Support URL** | https://github.com/SilverNinja71/Parchment/issues |
| **Marketing URL** | https://silverninja71.github.io/Parchment/ |
| **Copyright** | 2026 BelloBook contributors |

## App Privacy ("nutrition label")

Choose **Data Not Collected**. BelloBook has no analytics, ads or servers; sync goes straight from the iPad to the user's own cloud account.

## Promotional text (170)

Handwriting notes that work for you: scratch out mistakes, turn ink into text, solve math, and study with active recall. Free forever, private by design.

## Description (4000)

BelloBook is a free handwriting notes app for iPad and Apple Pencil, with no ads and no subscriptions.

WRITE NATURALLY
• Document pages that grow as you write, or an endless freeform canvas
• Lined, grid, dotted, dotted-lined and blank paper
• Pen, highlighter, eraser, lasso and ruler
• Scribble over ink to erase it: no eraser needed
• Type anywhere with the text tool

INK THAT WORKS FOR YOU
• Circle handwriting to turn it into typed text that flows as paragraphs
• Live Text shows what you're writing, ready to convert in one tap
• Circle a calculation to solve it, and keep your handwriting or type it out
• Circle rough shapes to turn them into clean lines, circles, triangles and rectangles
• Search inside your handwriting

WORK THAT CHECKS ITSELF
• BelloBook follows each line of a calculation or derivation and flags the step where it goes wrong
• Catches arithmetic, sign and expansion slips, and offers the corrected line
• Checks units, percentages and chained equalities, and accepts sensibly rounded answers

STUDY WITH ACTIVE RECALL
• Recall practice: memorize a page, hide it, rewrite it from memory, then compare side by side
• Flashcards you write by hand, with spaced repetition
• Rate yourself 1 to 5 and see each card again at just the right time
• Export decks for Anki, or send them to Anki on your computer

TEXTBOOK VIEW, MEDIA AND LINKS
• See typed notes as a formatted page with Markdown, callouts and LaTeX math
• Link notebooks with [[wiki-links]] and see what links back
• Attach photos, audio, videos and documents to any page

PDFs, COVERS AND SYNC
• Import PDFs and write on them, then export as PDF
• Beautiful covers: colors, finishes, a cover library, or your own photo
• Sync to iCloud Drive, a WebDAV server, your own server, an Obsidian vault or other storage apps, and to several places at once

MAKE IT YOURS
• Draw your own icons, covers and alphabet in the Personalization Kit, and BelloBook uses them everywhere

PRIVATE BY DESIGN
• Handwriting recognition runs on your iPad
• No accounts, no tracking, no ads
• Open source: github.com/SilverNinja71/Parchment

## Keywords (100, comma-separated, no spaces)

handwriting,notes,notebook,pencil,study,flashcards,recall,pdf,annotate,math,convert,anki,latex

## Screenshots

Required: **13-inch iPad** screenshots (2064 × 2752 portrait or 2752 × 2064 landscape). Up to 10. Suggested set:
1. The library with colorful covers and the subjects sidebar
2. A handwritten document page with the floating toolbar
3. Converting handwriting to text (the Convert sheet)
4. Solving math (the Solve sheet with the answer)
5. Recall practice side-by-side comparison
6. A flashcard with the 1–5 rating bar
7. The two-pane New Notebook screen with the 3D cover
8. A PDF being annotated

Take them on an iPad (top button + volume up) or in the Xcode iPad simulator.

## Notes for the App Review team

> BelloBook is a free, offline handwriting notes app. No account is needed. On first launch it opens a "Welcome to BelloBook" notebook with a guided tour. Handwriting conversion, math solving and search run on-device with Apple's Vision framework. Cloud sync is optional; iCloud Drive and WebDAV work without sign-in to our servers (we have none). There are no in-app purchases.
>
> The app asks for local network access only if the user syncs with a server on their own network, or sends flashcards to Anki on their computer (the AnkiConnect add-on). Nothing on the local network is contacted otherwise.

## Before you submit (checklist)

- [ ] Change the bundle ID from `com.example.parchment` to your own (e.g. `com.silverninja.parchment`) in Xcode or Swift Playgrounds App Settings
- [ ] Turn on GitHub Pages (repo Settings → Pages → Branch: `main`, folder: `/docs`) so the privacy URL works
- [ ] Test on a real iPad (TestFlight) and fix anything that crashes
- [ ] Only add OneDrive / Google Drive / Dropbox app IDs if you've registered them (until then they're hidden in the app)
- [ ] Take screenshots and fill in this listing in App Store Connect
