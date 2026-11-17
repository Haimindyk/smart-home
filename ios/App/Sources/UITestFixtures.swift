#if DEBUG
import Foundation
import WellnessCore

// Only reachable with an explicit UI-test launch argument in a Debug build.
// AppStore disables Backend completely before loading these fixtures.
enum UITestFixtures {
    static let owner = "11111111-1111-4111-8111-111111111111"
    private static func row(id: String, data: String) -> [HealthRow] {
        let json = "[{\"id\":\"\(id)\",\"owner_user_id\":\"\(owner)\",\"version\":1,\"data\":\(data)}]"
        return (try? JSONDecoder().decode([HealthRow].self, from: Data(json.utf8))) ?? []
    }
    static func goals(date: String) -> [HealthRow] {
        row(id: "22222222-2222-4222-8222-222222222222", data: "{\"date\":\"\(date)\",\"kcal\":1800,\"protein\":120,\"carbs\":200,\"fat\":60,\"method\":\"manual\"}")
    }
    static func meals(date: String) -> [HealthRow] {
        row(id: "33333333-3333-4333-8333-333333333333", data: "{\"date\":\"\(date)\",\"kind\":\"lunch\",\"name\":\"ארוחת בדיקה\",\"imagePath\":null,\"items\":[{\"id\":\"44444444-4444-4444-8444-444444444444\",\"quantity\":100,\"food\":{\"id\":\"test-tuna\",\"name\":\"טונה\",\"basis\":\"g\",\"source\":\"manual\",\"per100\":{\"kcal\":150,\"protein\":25,\"carbs\":0,\"fat\":5}}}]}")
    }
    static func weights(zone: TimeZone) -> [HealthRow] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        let values = [82.4, 82.1, 82.3, 81.8, 81.5, 81.6, 81.2]
        return values.enumerated().flatMap { index, kg -> [HealthRow] in
            let day = calendar.date(byAdding: .day, value: index - values.count + 1, to: Date()) ?? Date()
            let id = String(format: "77777777-7777-4777-8777-%012d", index)
            return row(id: id, data: "{\"date\":\"\(f.string(from: day))\",\"weight\":\(kg)}")
        }
    }
    static var chatState: JSONValue {
        let json = """
        {"used":2,"limit":20,"available":true,"version":2,"generation":"g1","turns":[
          {"id":"t1","user_text":"כמה חלבון אני צריך ביום אם אני מתאמן שלוש פעמים בשבוע?","answer":{"reply":"בדרך כלל מומלץ בין 1.6 ל־2.2 גרם חלבון לכל קילוגרם משקל גוף למי שמתאמן באופן קבוע. אפשר לפזר אותו על פני 3–4 ארוחות. זה מידע כללי ולא תחליף לתזונאי.","exerciseIds":[],"followUps":["איך מגיעים לזה עם תזונה צמחונית?","מה לאכול אחרי אימון?"],"topic":"nutrition"},"shared_diary":false,"created_at":"2026-11-17T10:00:00Z"}
        ]}
        """
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null
    }
    static var trainerProposal: JSONValue {
        let json = """
        {"requestId":"req-1","kind":"program","message":"תוכנית ABC לשלושה ימים בשבוע, 45 דקות לאימון, עם דגש על חזה וגב.","reasons":["שלושה ימי אימון מאפשרים התאוששות בין האימונים","בחרתי תרגילים מהציוד שסימנת"],
         "changes":[{"id":"c1","expectedVersion":null,"data":{"name":"אימון A – חזה וכתפיים","days":[0],"archived":false,"notes":"","exercises":[
            {"id":"a1","name":"שכיבות סמיכה","sets":3,"reps":12,"weight":0,"rest":60,"muscle":"חזה","equipment":"משקל גוף"},
            {"id":"a2","name":"לחיצת חזה עם דאמבלים","sets":3,"reps":10,"weight":14,"rest":90,"muscle":"חזה","equipment":"דאמבלים"}]}}]}
        """
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null
    }
    static func plans() -> [HealthRow] {
        func ex(_ id: String, _ name: String, _ sets: Int, _ reps: Int, _ weight: Double, _ muscle: String) -> String {
            "{\"id\":\"\(id)\",\"name\":\"\(name)\",\"muscle\":\"\(muscle)\",\"equipment\":\"\",\"kind\":\"strength\",\"sets\":\(sets),\"reps\":\(reps),\"weight\":\(weight),\"rest\":60,\"duration\":0,\"distance\":0,\"notes\":\"\"}"
        }
        let exercises = [ex("88888888-8888-4888-8888-888888888881", "פרפר בכבלים", 3, 8, 40, "חזה"), ex("88888888-8888-4888-8888-888888888882", "פולי עליון לגב", 3, 10, 60, "גב")].joined(separator: ",")
        return row(id: "99999999-9999-4999-8999-999999999999", data: "{\"name\":\"פלג גוף עליון\",\"exercises\":[\(exercises)],\"days\":[1,3],\"archived\":false}")
    }
    static func workouts(date: String) -> [HealthRow] {
        row(id: "55555555-5555-8555-8555-555555555555", data: "{\"date\":\"\(date)\",\"name\":\"הליכה לבדיקה\",\"status\":\"completed\",\"quick\":true,\"startedAt\":\"\(date)T08:00:00Z\",\"exercises\":[],\"appleHealth\":{\"uuid\":\"66666666-6666-4666-8666-666666666666\",\"sourceName\":\"Test Watch\",\"durationSeconds\":1800,\"activityType\":52,\"energyKcal\":null,\"distanceMeters\":2500}}")
    }
}
#endif
