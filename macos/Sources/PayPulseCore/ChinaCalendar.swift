import Foundation

public enum ChinaCalendar {
    public struct Day: Decodable {
        public var name: String
        public var kind: String
    }
    private struct Year: Decodable { var days: [String: Day] }
    private struct Dataset: Decodable { var years: [String: Year] }
    private static let data = try! JSONDecoder().decode(Dataset.self, from: Data(ChinaCalendarData.json.utf8))
    public static var years: [Int] { data.years.keys.compactMap(Int.init).sorted() }
    public static func contains(_ day: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        data.years[String(LocalDay.key(for: day, calendar: calendar).prefix(4))] != nil
    }
    public static func day(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> Day? {
        let key = LocalDay.key(for: date, calendar: calendar)
        return data.years[String(key.prefix(4))]?.days[key]
    }
    public static func status(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let year = String(LocalDay.key(for: date, calendar: calendar).prefix(4))
        return contains(date, calendar: calendar)
            ? "已载入 \(year) 年日历 · Timor 数据已核对，离线可用"
            : "\(year) 年日历尚未收录，请切换为实际排班或固定折算天数。"
    }
}
