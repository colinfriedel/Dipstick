// Runs the app's record reader (text recognition or a PDF's text, then the
// on-device language model, then the checks against the page) on service
// record photos, screenshots, PDFs or plain text files, to tune accuracy on
// a Mac. Needs a Mac with Apple Intelligence on.
//
//   swiftc -O -parse-as-library tools/read_records.swift tools/read_records_stubs.swift \
//       Dipstick/Logic/RecordImport.swift Dipstick/Logic/RecordReader.swift \
//       Dipstick/Logic/ReceiptReader.swift Dipstick/Logic/ReceiptParser.swift \
//       Dipstick/Logic/CSV.swift Dipstick/Logic/Units.swift -o /tmp/read_records
//   /tmp/read_records [--rules] [--text] path/to/records/*
//
// --rules skips the language model (as on phones without it); --text prints
// the text read from each page.

import Foundation

@main
struct ReadRecords {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let rulesOnly = arguments.contains("--rules")
        let showText = arguments.contains("--text")
        arguments.removeAll { $0.hasPrefix("--") }

        for path in arguments {
            let url = URL(fileURLWithPath: path)
            print("=== \(url.lastPathComponent)")
            var pages: [RecordReader.Page] = []
            switch url.pathExtension.lowercased() {
            case "pdf": pages = RecordReader.pages(fromPDF: url)
            case "txt": pages = [.init(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "")]
            default:
                if let data = try? Data(contentsOf: url), let page = RecordReader.page(fromImage: data) { pages = [page] }
            }
            if showText { for page in pages { print(page.text); print("---") } }
            let start = Date()
            let visits: [RecordImport.Visit]
            if rulesOnly {
                visits = RecordImport.tidy(pages.enumerated().flatMap { i, page in
                    var found = RecordImport.visitsByRules(lines: page.text.components(separatedBy: .newlines), page: i)
                    for v in found.indices { RecordImport.check(&found[v], against: .init(page.text)) }
                    return found
                })
            } else {
                visits = await RecordReader.read(pages, known: ServiceTypeList.builtIn).visits
            }
            for v in visits {
                let flag = { (f: RecordImport.Visit.Field) in v.unsure.contains(f) ? " ⚠" : "" }
                print("\(v.date.map(FlexibleDate.key) ?? "no date")\(flag(.date))  "
                      + "\(v.odometer.map { "\($0) mi" } ?? "no mileage")\(flag(.odometer))  "
                      + "\(v.total.map { String(format: "$%.2f", $0) } ?? "")\(flag(.total))  "
                      + "\(v.shop ?? "") \(v.invoice.map { "#\($0)" } ?? "")")
                for s in v.services {
                    print("    \(s.name)\(s.price.map { String(format: "  $%.2f", $0) } ?? "")\(s.priceUnsure ? " ⚠" : "")"
                          + (s.parts.isEmpty ? "" : "  [" + s.parts.map { "\($0.name)\($0.partNumber.map { " #\($0)" } ?? "") x\($0.quantity)" }.joined(separator: "; ") + "]")
                          + (s.notes.map { "  — \($0)" } ?? ""))
                }
            }
            print(String(format: "(%.1fs)\n", Date().timeIntervalSince(start)))
        }
    }
}
