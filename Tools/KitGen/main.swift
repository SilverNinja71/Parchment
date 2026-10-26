import Foundation

// Generates the blank Parchment Personalization Kit on a Mac.
//
//   swiftc -O -o /tmp/kitgen Tools/KitGen/*.swift Parchment/Personalization/KitLayout.swift \
//       Parchment/Personalization/KitPDFRenderer.swift Parchment/Model/Notebook.swift
//   /tmp/kitgen Kit
//
// AirDrop the .parchmentkit file to your iPad and it opens straight into Parchment.
// The .pdf copy is the same file, handy for previewing, printing or importing.

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".", isDirectory: true)
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

let pdf = KitPDFRenderer.makePDF(ghosts: ghosts)
let kitURL = outputFolder.appendingPathComponent("Parchment Personalization Kit.\(KitLayout.fileExtension)")
let previewURL = outputFolder.appendingPathComponent("Parchment Personalization Kit (preview).pdf")
try pdf.write(to: kitURL)
try pdf.write(to: previewURL)

print("Wrote \(kitURL.path) (\(pdf.count / 1024) KB, \(KitLayout.pages.count) pages, \(KitLayout.slots.count) boxes)")
print("Wrote \(previewURL.path)")
