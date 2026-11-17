// Generated from supabase/functions/_shared/exercise-catalog.ts (curated IDs shared with the web app).
import Foundation

struct CatalogExercise: Identifiable, Hashable {
    let id: String, he: String, en: String, muscle: String, equipment: String
    var muscleHe: String { ExerciseCatalog.muscleLabels[muscle] ?? muscle }
    var equipmentHe: String { ExerciseCatalog.equipmentLabels[equipment] ?? equipment }
}

enum ExerciseCatalog {
    static let muscleLabels = ["legs": "רגליים", "hamstrings": "ירך אחורית", "glutes": "ישבן", "chest": "חזה", "back": "גב", "shoulders": "כתפיים", "biceps": "יד קדמית", "triceps": "יד אחורית", "calves": "שוקיים", "core": "ליבה"]
    static let muscleOrder = ["chest", "back", "shoulders", "biceps", "triceps", "legs", "hamstrings", "glutes", "calves", "core"]
    static let equipmentLabels = ["bodyweight": "משקל גוף", "dumbbell": "דאמבלים", "machine": "מכונה", "cable": "כבל", "barbell": "מוט", "pullup": "מתח"]
    static let all: [CatalogExercise] = [
        .init(id: "Goblet_Squat", he: "גובלט סקוואט", en: "Goblet squat", muscle: "legs", equipment: "dumbbell"),
        .init(id: "Leg_Press", he: "לחיצת רגליים", en: "Leg press", muscle: "legs", equipment: "machine"),
        .init(id: "Hack_Squat", he: "האק סקוואט", en: "Hack squat", muscle: "legs", equipment: "machine"),
        .init(id: "Barbell_Squat", he: "סקוואט עם מוט", en: "Barbell squat", muscle: "legs", equipment: "barbell"),
        .init(id: "Bodyweight_Squat", he: "סקוואט במשקל גוף", en: "Bodyweight squat", muscle: "legs", equipment: "bodyweight"),
        .init(id: "Dumbbell_Lunge", he: "מכרעים עם דאמבלים", en: "Dumbbell lunge", muscle: "legs", equipment: "dumbbell"),
        .init(id: "Bodyweight_Lunge", he: "מכרעים במשקל גוף", en: "Bodyweight lunge", muscle: "legs", equipment: "bodyweight"),
        .init(id: "Romanian_Deadlift", he: "דדליפט רומני", en: "Romanian deadlift", muscle: "hamstrings", equipment: "barbell"),
        .init(id: "Barbell_Hip_Thrust", he: "היפ טראסט", en: "Barbell hip thrust", muscle: "glutes", equipment: "barbell"),
        .init(id: "Glute_Bridge", he: "גשר ישבן", en: "Glute bridge", muscle: "glutes", equipment: "bodyweight"),
        .init(id: "Lying_Leg_Curls", he: "כפיפת ברכיים במכונה", en: "Lying leg curls", muscle: "hamstrings", equipment: "machine"),
        .init(id: "Seated_Leg_Curl", he: "כפיפת ברכיים בישיבה", en: "Seated leg curl", muscle: "hamstrings", equipment: "machine"),
        .init(id: "Leg_Extensions", he: "פשיטת ברכיים במכונה", en: "Leg extensions", muscle: "legs", equipment: "machine"),
        .init(id: "Dumbbell_Bench_Press", he: "לחיצת חזה עם דאמבלים", en: "Dumbbell bench press", muscle: "chest", equipment: "dumbbell"),
        .init(id: "Incline_Dumbbell_Press", he: "לחיצת חזה בשיפוע חיובי עם דאמבלים", en: "Incline dumbbell press", muscle: "chest", equipment: "dumbbell"),
        .init(id: "Machine_Bench_Press", he: "לחיצת חזה במכונה", en: "Machine bench press", muscle: "chest", equipment: "machine"),
        .init(id: "Leverage_Incline_Chest_Press", he: "לחיצת חזה בשיפוע במכונה", en: "Leverage incline chest press", muscle: "chest", equipment: "machine"),
        .init(id: "Push_Up", he: "שכיבות סמיכה", en: "Push-up", muscle: "chest", equipment: "bodyweight"),
        .init(id: "Cable_Crossover", he: "פרפר בכבלים", en: "Cable crossover", muscle: "chest", equipment: "cable"),
        .init(id: "Low_Cable_Crossover", he: "פרפר בכבלים מלמטה", en: "Low cable crossover", muscle: "chest", equipment: "cable"),
        .init(id: "Wide-Grip_Lat_Pulldown", he: "פולי עליון לגב", en: "Wide-grip lat pulldown", muscle: "back", equipment: "cable"),
        .init(id: "V-Bar_Pulldown", he: "פולי עליון באחיזה צרה", en: "V-bar pulldown", muscle: "back", equipment: "cable"),
        .init(id: "Seated_Cable_Rows", he: "חתירה בישיבה", en: "Seated cable rows", muscle: "back", equipment: "cable"),
        .init(id: "Lying_T-Bar_Row", he: "חתירת טי בר בתמיכת חזה", en: "Lying T-bar row", muscle: "back", equipment: "machine"),
        .init(id: "Dumbbell_Row", he: "חתירה עם דאמבל", en: "Dumbbell row", muscle: "back", equipment: "dumbbell"),
        .init(id: "Pull_Up", he: "מתח", en: "Pull-up", muscle: "back", equipment: "pullup"),
        .init(id: "Dumbbell_Shoulder_Press", he: "לחיצת כתפיים עם דאמבלים", en: "Dumbbell shoulder press", muscle: "shoulders", equipment: "dumbbell"),
        .init(id: "Side_Lateral_Raise", he: "הרחקת כתפיים לצדדים", en: "Side lateral raise", muscle: "shoulders", equipment: "dumbbell"),
        .init(id: "Barbell_Curl", he: "כפיפת מרפקים עם מוט", en: "Barbell curl", muscle: "biceps", equipment: "barbell"),
        .init(id: "Dumbbell_Curl", he: "כפיפת מרפקים עם דאמבלים", en: "Dumbbell curl", muscle: "biceps", equipment: "dumbbell"),
        .init(id: "Triceps_Pushdown", he: "פשיטת מרפקים בכבל", en: "Triceps pushdown", muscle: "triceps", equipment: "cable"),
        .init(id: "Standing_Calf_Raises", he: "הרמת עקבים בעמידה", en: "Standing calf raises", muscle: "calves", equipment: "bodyweight"),
        .init(id: "Seated_Calf_Raise", he: "הרמת עקבים בישיבה", en: "Seated calf raise", muscle: "calves", equipment: "machine"),
        .init(id: "Plank", he: "פלאנק", en: "Plank", muscle: "core", equipment: "bodyweight"),
        .init(id: "Cable_Crunch", he: "כפיפות בטן בכבל", en: "Cable crunch", muscle: "core", equipment: "cable"),
    ]
}
