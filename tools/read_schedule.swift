// Runs the app's schedule reader (grid tables by position, lists by rules
// or the on-device language model) on owner's manual photos, screenshots
// or PDFs, to tune it on a Mac.
//
//   swiftc -O -parse-as-library tools/read_schedule.swift tools/read_records_stubs.swift \
//       Dipstick/Logic/ScheduleReader.swift Dipstick/Logic/RecordImport.swift Dipstick/Logic/RecordReader.swift \
//       Dipstick/Logic/ReceiptReader.swift Dipstick/Logic/ReceiptParser.swift \
//       Dipstick/Logic/CSV.swift Dipstick/Logic/Units.swift -o /tmp/read_schedule
//   /tmp/read_schedule [--text] path/to/manual-pages/*

import Foundation

@main
struct ReadSchedule {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let showText = arguments.contains("--text")
        arguments.removeAll { $0.hasPrefix("--") }
        for path in arguments {
            let url = URL(fileURLWithPath: path)
            print("=== \(url.lastPathComponent)")
            let pages = url.pathExtension.lowercased() == "pdf"
                ? RecordReader.schedulePages(fromPDF: url)
                : [(try? Data(contentsOf: url)).flatMap(RecordReader.schedulePage(fromImage:))].compactMap { $0 }
            if showText { for page in pages { print(page.text); print("---") } }
            for item in await ScheduleReader.read(pages, known: ServiceTypeList.builtIn) {
                var parts: [String] = []
                if let f = item.firstMiles ?? item.firstMonths.map({ _ in 0 }), item.firstMiles != nil || item.firstMonths != nil {
                    _ = f
                    parts.append("first \(item.firstMiles.map { "\($0) mi" } ?? "")\(item.firstMonths.map { " \($0) mo" } ?? "")")
                }
                parts.append("every \(item.everyMiles.map { "\($0) mi" } ?? "-")\(item.everyMonths.map { " \($0) mo" } ?? "")")
                print("\(item.unsure ? "⚠ " : "  ")\(item.name)  [\(item.serviceType)]  " + parts.joined(separator: ", "))
                if let note = item.note { print("      note: \(note)") }
            }
            print()
        }
    }
}
