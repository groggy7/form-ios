import Foundation
import Combine

public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()
    
    private static let userDefaultsKey = "app_language"

    @Published public var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: Self.userDefaultsKey)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.userDefaultsKey), saved == "en" || saved == "tr" {
            self.currentLanguage = saved
        } else if Locale.current.language.languageCode?.identifier == "tr" || Locale.preferredLanguages.first?.starts(with: "tr") == true {
            self.currentLanguage = "tr"
        } else {
            self.currentLanguage = "en"
        }
    }
    
    public static var workoutDays: [String] {
        return shared.currentLanguage == "tr" ? [
            "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"
        ] : [
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
        ]
    }
    
    public static func t(_ key: String, _ params: [String: Any] = [:]) -> String {
        return shared.translate(key, params: params)
    }
    
    public static func content(_ text: String) -> String {
        return ContentDictionary.localize(text, lang: shared.currentLanguage)
    }

    public static func setLanguage(_ lang: String) {
        if lang == "en" || lang == "tr" {
            shared.currentLanguage = lang
        }
    }
    
    public static func turkishPossessiveNumber(_ n: Int) -> String {
        if n == 0 { return "0'ı" }
        let lastTwo = n % 100
        let lastOne = n % 10
        if lastTwo >= 10 && lastTwo <= 19 {
            let suffixes: [Int: String] = [
                0: "'u", 1: "'i", 2: "'si", 3: "'ü", 4: "'ü",
                5: "'i", 6: "'sı", 7: "'si", 8: "'i", 9: "'u"
            ]
            return "\(n)\(suffixes[lastOne] ?? "'i")"
        }
        if lastOne == 0 {
            let tens: [Int: String] = [
                20: "'si", 30: "'u", 40: "'ı", 50: "'si",
                60: "'ı", 70: "'i", 80: "'i", 90: "'ı"
            ]
            return "\(n)\(tens[lastTwo] ?? "'ü")"
        }
        let ones: [Int: String] = [
            1: "'i", 2: "'si", 3: "'ü", 4: "'ü",
            5: "'i", 6: "'sı", 7: "'si", 8: "'i", 9: "'u"
        ]
        return "\(n)\(ones[lastOne] ?? "'i")"
    }

    public static func formatSetsProgress(done: Int, total: Int) -> String {
        return t("history.setsProgress", ["done": done, "total": total])
    }

    public static func formatPercent(_ percent: Int) -> String {
        return shared.currentLanguage == "tr" ? "%\(percent)" : "\(percent)%"
    }

    public static func formatSetsLeft(_ count: Int) -> String {
        if shared.currentLanguage == "tr" {
            return "\(count) set kaldı"
        } else {
            return count == 1 ? "1 set left" : "\(count) sets left"
        }
    }

    public static func formatOtherExercises(_ count: Int) -> String {
        if shared.currentLanguage == "tr" {
            return "Diğer \(count) egzersiz"
        } else {
            return count == 1 ? "1 other exercise" : "\(count) other exercises"
        }
    }

    public static func formatUncompletedExercisesCount(_ count: Int) -> String {
        if shared.currentLanguage == "tr" {
            return "\(count) tamamlanmamış egzersiz"
        } else {
            return count == 1 ? "1 uncompleted exercise" : "\(count) uncompleted exercises"
        }
    }

    public static func formatCompletedExercisesCount(_ count: Int) -> String {
        if shared.currentLanguage == "tr" {
            return "\(count) tamamlanan egzersiz"
        } else {
            return count == 1 ? "1 completed exercise" : "\(count) completed exercises"
        }
    }

    public static func formatAllExercisesCount(_ count: Int) -> String {
        return formatUncompletedExercisesCount(count)
    }

    public static func formatSetsFraction(completed: Int, total: Int) -> String {
        if shared.currentLanguage == "tr" {
            return "\(completed) / \(total) set"
        } else {
            return total == 1 ? "\(completed) / 1 set" : "\(completed) / \(total) sets"
        }
    }

    public static func formatExerciseSetsCompleted(completed: Int, planned: Int) -> String {
        if shared.currentLanguage == "tr" {
            return "\(completed) / \(planned) set tamamlandı"
        } else {
            return planned == 1 ? "\(completed) / 1 set completed" : "\(completed) / \(planned) sets completed"
        }
    }

    public func translate(_ key: String, params: [String: Any] = [:]) -> String {
        let dict = currentLanguage == "tr" ? Translations.tr : Translations.en
        var template = dict[key] ?? Translations.en[key] ?? key
        for (k, v) in params {
            let strVal: String
            if currentLanguage == "tr" && key == "history.setsProgress" && k == "done", let n = v as? Int {
                strVal = LanguageManager.turkishPossessiveNumber(n)
            } else {
                strVal = "\(v)"
            }
            template = template.replacingOccurrences(of: "{" + k + "}", with: strVal)
        }
        return template
    }
}

public enum ContentDictionary {
    private static var _canonicalMap: [String: String]?

    public static var canonicalMap: [String: String] {
        if let cached = _canonicalMap { return cached }
        var map: [String: String] = [:]
        let enDict = ContentLocalizer.shared.loadExercises(lang: "en")
        let trDict = ContentLocalizer.shared.loadExercises(lang: "tr")
        for (id, trDef) in trDict {
            guard let enDef = enDict[id] else { continue }
            for (en, tr) in zip(enDef.cues ?? [], trDef.cues ?? []) {
                let e = en.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let t = tr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !e.isEmpty && !t.isEmpty {
                    map[e] = t
                }
            }
            for (en, tr) in zip(enDef.avoid ?? [], trDef.avoid ?? []) {
                let e = en.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let t = tr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !e.isEmpty && !t.isEmpty {
                    map[e] = t
                }
            }
            let cuesEn = (enDef.cues ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let cuesTr = (trDef.cues ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !cuesEn.isEmpty && !cuesTr.isEmpty {
                map[cuesEn] = cuesTr
            }
            let avoidEn = (enDef.avoid ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let avoidTr = (trDef.avoid ?? []).joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !avoidEn.isEmpty && !avoidTr.isEmpty {
                map[avoidEn] = avoidTr
            }
        }
        _canonicalMap = map
        return map
    }

    public static func localize(_ text: String?, lang: String) -> String {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        if lang != "tr" {
            return text
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let direct = canonicalMap[trimmed] {
            return direct
        }
        if trimmed.hasPrefix("- ") {
            let clean = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if let tr = canonicalMap[clean] {
                return "- \(tr)"
            }
        }
        if text.contains("\n") {
            let lines = text.components(separatedBy: .newlines)
            let translated = lines.map { line -> String in
                let lTrim = line.trimmingCharacters(in: .whitespaces)
                if lTrim.isEmpty { return "" }
                let isDash = lTrim.hasPrefix("- ")
                let clean = isDash ? String(lTrim.dropFirst(2)).trimmingCharacters(in: .whitespaces) : lTrim
                let tr = canonicalMap[clean] ?? clean
                return isDash ? "- \(tr)" : tr
            }
            return translated.joined(separator: "\n")
        }
        return text
    }
}

public enum Translations {
    public static let en: [String: String] = [
        "targets.sets": "Sets",
        "targets.reps": "Reps",
        "targets.min": "Min reps",
        "targets.max": "Max reps",
        "targets.failure": "Technical failure",
        "targets.perSide": "Reps per side",
        "targets.structured": "Use sets and rep targets",
        "targets.custom": "Use a custom prescription",
        "targets.invalid": "Use 1–10 sets and 1–999 reps; minimum cannot exceed maximum.",
        "rest.alertSetup": "Enable locked-screen rest alerts",
        "rest.alertTitle": "Rest alerts",
        "rest.alertExplanation": "Allow notifications and Alarms & reminders to hear or feel the end of a rest with your phone locked. Some phones also require FORM in Background autostart. Without this access, background alerts may be silent or delayed. Your phone's notification and Do Not Disturb settings still apply.",
        "rest.alertContinue": "Continue",
        "rest.notNow": "Not now",
        "rest.dismissPrompt": "Don't ask again",
        "rest.backgroundSetup": "Allow FORM in Background autostart",
        "rest.backgroundExplanation": "Xiaomi and HyperOS can prevent FORM from delivering a finished timer until you reopen the app. Open Background autostart, enable FORM, then return.",
        "settings.title": "Settings",
        "settings.training": "Training programs",
        "settings.prefillNextSet": "Pre-fill next set",
        "settings.prefillNextSetSubtitle": "Copy weight and reps from previous set",
        "settings.timerAndAlerts": "Rest timer & alerts",
        "settings.defaultRest": "Default rest timer",
        "settings.lockedScreenAlerts": "Locked-screen rest alerts",
        "settings.alertsActive": "Enabled",
        "settings.alertsNeedsSetup": "Setup required",
        "settings.backgroundSetup": "Background autostart (Xiaomi / HyperOS)",
        "settings.backgroundActive": "Configured",
        "settings.backgroundNeedsReview": "Review required",
        "settings.language": "Language",
        "settings.dataManagement": "Data & backup",
        "settings.exportBackup": "Export backup JSON",
        "settings.restoreBackup": "Restore backup",
        "settings.about": "About FORM",
        "settings.aboutDescription": "FORM is a focused strength training companion designed to log your workouts, guide your exercise technique with visual movement animations and cues, and track your progressive overload — quiet, distraction-free, and always ready.",
        "settings.version": "v1.0",
        "video.openExternal": "Open in YouTube",
        "video.close": "Close video",
        "anatomy.title": "Muscles worked",
        "anatomy.primary": "Primary muscles",
        "anatomy.secondary": "Secondary muscles",
        "anatomy.front": "Front",
        "anatomy.back": "Back",
        "anatomy.unavailable": "Muscle information unavailable for this exercise.",
        "anatomy.note": "Main muscle groups shown. Highlights are illustrative, not activation measurements.",
        "video.back5": "Back 5 seconds",
        "video.forward5": "Forward 5 seconds",
        "video.play": "Play video",
        "video.pause": "Pause video",
        "video.resume": "Resume video",
        "video.replay": "Replay video",
        "video.loading": "Loading video…",
        "video.retry": "Try again",
        "video.invalid": "This YouTube link isn't valid.",
        "video.youtubeOnly": "Only YouTube videos and Shorts are supported right now.",
        "video.networkError": "Couldn't load the video. Check your connection and try again.",
        "video.embedError": "YouTube couldn't play this video here. Try again or open it in YouTube.",
        "video.linkTitle": "Link exercise videos",
        "video.linkSubtitle": "Attach technique and form demonstration video links",
        "video.urlInputLabel": "Video URL",
        "video.urlInputPlaceholder": "Paste YouTube video or Shorts link",
        "video.addUrlButton": "Add link",
        "video.paste": "Paste",
        "video.preview": "Preview",
        "video.linkedCount": "Linked videos ({count}/3)",
        "video.tapToPlay": "Tap to play",
        "video.maxReached": "Maximum 3 videos linked",
        "video.maxReachedHint": "Maximum of 3 videos linked. Remove an existing video to add another.",
        "video.alreadyAdded": "This video is already linked.",
        "video.noVideos": "No videos linked to this exercise yet. Add a YouTube link below.",
        "video.saveLinks": "Save video links",
        "notice.videosUpdated": "{name} videos updated",
        "nav.history": "History",
        "history.thisMonth": "This month",
        "history.previousMonth": "Previous month",
        "history.nextMonth": "Next month",
        "history.completed": "Completed",
        "history.unfinished": "Unfinished",
        "history.missed": "Missed",
        "history.future": "Upcoming day",
        "history.neutral": "Rest day or no record",
        "history.notStarted": "Not started",
        "history.setsProgress": "{done} of {total} sets",
        "history.setsDoneCount": "{count} sets done",
        "history.setsRemainingCount": "{count} sets remaining",
        "history.duration": "Duration",
        "history.sets": "Sets",
        "history.volume": "Volume",
        "history.close": "Close",
        "history.toContinue": "To continue",
        "history.setsFraction": "{completed} / {total} sets",
        "history.resumeWorkout": "Resume workout",
        "history.startWorkout": "Start workout",
        "history.scheduledWorkout": "Scheduled workout",
        "programs.title": "Programs",
        "programs.new": "New program",
        "header.newProgram": "New program",
        "programs.import": "Import JSON",
        "programs.apply": "Apply",
        "programs.export": "Export",
        "programs.edit": "Edit",
        "programs.active": "ACTIVE",
        "programs.counts": "{workouts} workouts · {exercises} exercises",
        "programs.empty": "No programs yet",
        "programs.emptyHint": "Create a program or import a FORM program JSON file.",
        "programs.deleteTitle": "Delete {name}?",
        "programs.deleteHint": "This deletes the program and its workouts. Past workout history is kept. Export it first if you want a copy.",
        "programs.defaultRestHint": "Used for new exercises and imports without restSeconds. Existing exercises keep their saved rest. 0 skips the timer.",
        "programs.seconds": "Seconds (0–900)",
        "programs.save": "Save",
        "programs.review": "Review import",
        "programs.updateHint": "The program ID matches an existing program. Confirming replaces that program's plan, including any removals below. Other programs and past workout history are kept.",
        "programs.addHint": "This adds a new program. Existing programs and past workout history are kept.",
        "programs.noChanges": "No changes to this program.",
        "programs.change.added": "ADD",
        "programs.change.updated": "UPDATE",
        "programs.change.removed": "REMOVE",
        "programs.idHint": "Keep IDs unchanged when editing an exported file. A different program ID creates a new program.",
        "programs.update": "Update program",
        "programs.add": "Add program",
        "programs.exported": "Program exported.",
        "programs.imported": "Program imported.",
        "programs.sessionBlocked": "Finish or discard the current workout before changing its program.",
        "programs.restoreTitle": "Replace everything from backup?",
        "programs.restoreHint": "This replaces all programs, completion records and workout history, and discards any active workout. To change one program, cancel and use Programs → Import JSON instead.",
        "programs.fileError": "File could not be applied",
        "programs.close": "Close",
        "programs.restSeconds": "Rest between sets (seconds)",
        "programs.restHint": "0–900 seconds. 0 skips the timer.",
        "programs.movement": "Movement illustration",
        "programs.videoHint": "Use up to 3 YouTube video or Shorts links, one per line.",
        "programs.dayTaken": "This weekday already has a workout. Choose a free day.",
        "category.other": "OTHER",
        "common.back": "Back",
        "today.thisWeek": "This week",
        "today.weekProgress": "Week progress",
        "today.weeklyGoalProgress": "Weekly Goal Progress",
        "today.totalVolume": "TOTAL VOLUME",
        "today.activeTime": "ACTIVE TIME",
        "today.prsHit": "PRS HIT",
        "library.title": "Exercise library",
        "library.viewCards": "Cards view",
        "library.viewList": "List view",
        "library.search": "Search exercises",
        "library.clearSearch": "Clear search",
        "library.filters": "Filters",
        "library.scope": "Catalogue",
        "library.allExercises": "All exercises",
        "library.currentProgram": "Current program",
        "library.currentWorkout": "Current workout",
        "library.resultCount": "{count} exercises",
        "library.movement": "Movement",
        "library.equipment": "Equipment",
        "library.any": "Any",
        "library.resetFilters": "Reset filters",
        "library.clearFilter": "Remove filter",
        "library.clearAll": "Clear all",
        "library.noResults": "No exercises found.",
        "library.details": "Exercise details",
        "library.addNotes": "Add technique notes",
        "library.videos": "Technique videos",
        "library.videoUnavailable": "Video unavailable",
        "library.remove": "Remove",
        "library.videoError": "Could not open this video link.",
        "session.technique": "Technique & things to avoid",
        "session.review": "Review workout",
        "table.reps": "REPS",
        "table.removeSet": "Remove last",
        "table.undo": "Undo completed set",
        "rest.title": "Rest timer",
        "rest.finished": "READY",
        "rest.resting": "RESTING",
        "rest.paused": "PAUSED",
        "rest.target": "Target: {time}",
        "rest.skip": "Skip rest",
        "rest.expand": "Expand rest timer",
        "rest.minimize": "Minimize rest timer",
        "rest.mute": "Mute timer sound",
        "rest.unmute": "Enable timer sound",
        "summary.back": "Back to workout",
        "editor.deleteTitle": "Delete this item?",
        "editor.deleteConfirm": "This removes the item and its contents. This cannot be undone.",
        "nav.today": "Today",
        "nav.plan": "Plan",
        "nav.library": "Library",
        "plan.progressComplete": "COMPLETE",
        "plan.recover": "Recover",
        "plan.startWorkout": "Start workout",
        "plan.resumeWorkout": "Resume workout",
        "plan.editWorkout": "Edit workout",
        "today.todayWorkout": "Today's workout",
        "today.completed": "Completed",
        "today.workoutMeta": "{exercises} exercises · about {minutes} min",
        "today.exercises": "Exercises",
        "today.restDay": "Rest day",
        "today.restDescription": "No workout is scheduled for today. You can still open any workout above.",
        "today.emptyTitle": "No workouts yet",
        "today.emptyDescription": "Add a workout to this program from your weekly plan.",
        "today.openPlan": "Open weekly plan",
        "today.availableOn": "Available {day}",
        "weekly.title": "Weekly plan",
        "weekly.currentProgram": "Current program",
        "weekly.changeProgram": "Change program",
        "weekly.exerciseCount": "{count} exercises",
        "weekly.restDay": "Recovery day",
        "library.editWorkout": "Edit workout",
        "library.addExercise": "Add exercise",
        "library.videoItem": "Video {num}",
        "library.attachVideoCta": "Add video",
        "category.press": "PRESS",
        "category.pull-up": "PULL-UP",
        "category.row": "ROW",
        "category.shoulder-raise": "SHOULDER RAISE",
        "category.curl": "CURL",
        "category.triceps": "TRICEPS",
        "category.squat": "SQUAT",
        "category.hinge": "HINGE",
        "category.lunge": "LUNGE",
        "category.calf": "CALF",
        "category.core": "CORE",
        "category.conditioning": "CONDITIONING",
        "category.boxing": "BOXING",
        "modal.cancel": "Cancel",
        "modal.delete": "Delete",
        "modal.program.titleAdd": "New program",
        "modal.program.titleEdit": "Edit program",
        "modal.program.name": "Program name",
        "modal.program.namePlaceholder": "e.g. Summer strength",
        "modal.program.desc": "Description",
        "modal.program.notes": "Program-wide safety notes",
        "modal.program.save": "Save program",
        "builder.details": "Program details",
        "builder.detailsHint": "Name and guidance",
        "builder.optionalDetails": "Description & safety notes",
        "builder.optional": "Optional",
        "builder.showOptionalDetails": "Show optional program details",
        "builder.hideOptionalDetails": "Hide optional program details",
        "builder.trainingDays": "Training days",
        "builder.dayCount": "{count} of 7 days",
        "builder.addTrainingDay": "Add training day",
        "builder.noDays": "Choose your training days",
        "builder.noDaysHint": "Add a day, set its focus, then choose exercises from the library.",
        "builder.exerciseCount": "{count} exercises",
        "builder.exerciseCountOne": "1 exercise",
        "builder.addExercises": "Add exercises",
        "builder.editDay": "Edit training day",
        "builder.expandDay": "Show exercises",
        "builder.collapseDay": "Hide exercises",
        "builder.incompleteDays": "{count} training days have no exercises and cannot be started yet.",
        "builder.chooseExercises": "Choose exercises",
        "builder.searchExercises": "Search the exercise library",
        "builder.allMovements": "All",
        "builder.alreadyAdded": "Already in this day",
        "builder.addSelected": "Add selected · {count}",
        "builder.exerciseActions": "Exercise actions",
        "builder.editExercise": "Edit targets and details",
        "builder.moveEarlier": "Move up",
        "builder.moveLater": "Move down",
        "builder.removeExercise": "Remove from this day",
        "builder.saveFailed": "The program could not be saved. Check its days and exercises.",
        "modal.workout.titleAdd": "Add workout",
        "modal.workout.titleEdit": "Edit workout",
        "modal.workout.name": "Workout name",
        "modal.workout.namePlaceholder": "e.g. Upper A",
        "modal.workout.focus": "Focus",
        "modal.workout.day": "Day of week",
        "modal.workout.save": "Save workout",
        "muscles.title": "Target muscles",
        "muscles.hint": "Optional. The first selection sets the opening body view. Leave empty for an unhighlighted image.",
        "muscles.view.back": "Back",
        "muscles.view.front": "Front",
        "muscles.view.legs-front": "Legs · front",
        "muscles.view.legs-back": "Legs · back",
        "muscle.chest": "Chest",
        "muscle.abs": "Abs",
        "muscle.obliques": "Obliques",
        "muscle.biceps": "Biceps",
        "muscle.triceps": "Triceps",
        "muscle.shoulders": "Shoulders",
        "muscle.trapezius": "Trapezius",
        "muscle.lats": "Lats",
        "muscle.lower-back": "Lower back",
        "muscle.forearms": "Forearms",
        "muscle.quadriceps": "Quads",
        "muscle.hamstrings": "Hamstrings",
        "muscle.calves": "Calves",
        "muscle.glutes": "Glutes",
        "modal.exercise.titleAdd": "Add exercise",
        "modal.exercise.titleEdit": "Edit exercise",
        "modal.exercise.name": "Exercise name",
        "modal.exercise.prescription": "Sets × reps",
        "modal.exercise.cues": "Technique cues",
        "modal.exercise.avoid": "What to avoid",
        "modal.exercise.videos": "Video links",
        "modal.exercise.save": "Save exercise",
        "session.exit": "Exit workout",
        "session.exitConfirm": "Exit current workout session? Active set progress will be discarded.",
        "session.finish": "Finish",
        "session.finishBtn": "Finish",
        "session.prevExercise": "Previous exercise",
        "session.nextExercise": "Next exercise",
        "common.done": "Done",
        "history.workoutDetail": "Workout Details",
        "library.clearFilters": "Clear filters",
        "library.filterMovement": "Movement",
        "summary.saveAndClose": "Save workout",
        "table.deleteSet": "Delete set",
        "table.set": "SET",
        "table.weightKg": "WEIGHT (KG)",
        "table.actualReps": "ACTUAL REPS",
        "table.done": "Done",
        "table.doneHeading": "DONE",
        "table.currentSet": "Set {current} of {total}",
        "table.allSetsDone": "All {total} sets done",
        "table.complete": "Complete set",
        "table.addSet": "Add set",
        "rest.pause": "Pause",
        "rest.resume": "Resume",
        "summary.badge": "Workout summary",
        "summary.totalDuration": "Duration",
        "summary.estimatedVolume": "Volume",
        "summary.setsCompleted": "Sets completed",
        "summary.exerciseRecap": "Exercise recap",
        "summary.setsDone": "{count} sets done",
        "summary.saveBtn": "Save workout",
        "notice.backupRestored": "Backup restored successfully.",
        "notice.backupDownloaded": "Backup downloaded.",
        "notice.needOneExercise": "Please add at least one exercise before starting workout.",
        "notice.upcomingWorkout": "This workout is available on {day}.",
        "notice.workoutRecorded": "Workout recorded: {sets} sets, {volume}kg volume.",
        "notice.workoutAdded": "Workout added.",
        "notice.workoutUpdated": "Workout updated.",
        "notice.workoutDeleted": "Workout deleted.",
        "notice.exerciseAdded": "Exercise added.",
        "notice.exerciseUpdated": "Exercise updated.",
        "notice.exerciseDeleted": "Exercise deleted.",
        "notice.programCreated": "Program created.",
        "notice.programUpdated": "Program updated.",
        "notice.programDeleted": "Program deleted.",
        "notice.programApplied": "Switched to {name}.",
        "notice.emptySetWarning": "Weight and rep info cannot be left empty.",
        "notice.restActiveWarning": "Cannot log a set while the rest timer is running.",
    ]
    
    public static let tr: [String: String] = [
        "targets.sets": "Set",
        "targets.reps": "Tekrar",
        "targets.min": "Min tekrar",
        "targets.max": "Maks tekrar",
        "targets.failure": "Teknik tükeniş",
        "targets.perSide": "Her taraf için tekrar",
        "targets.structured": "Set ve tekrar hedeflerini kullan",
        "targets.custom": "Özel hedef metni kullan",
        "targets.invalid": "1–10 set, 1–999 tekrar kullan; minimum maksimumu aşamaz.",
        "rest.alertSetup": "Kilitli ekran dinlenme uyarılarını aç",
        "rest.alertTitle": "Dinlenme uyarıları",
        "rest.alertExplanation": "Telefon kilitliyken dinlenme bittiğinde ses veya titreşim almak için bildirimlere ve Alarmlar ve hatırlatıcılar iznine izin ver. Bazı telefonlarda FORM için Arka planda otomatik başlatma da gerekir. Bu erişim olmadan arka plan uyarıları sessiz kalabilir veya gecikebilir. Telefonun bildirim ve Rahatsız Etmeyin ayarları geçerlidir.",
        "rest.alertContinue": "Devam et",
        "rest.notNow": "Şimdi değil",
        "rest.dismissPrompt": "Bir daha sorma",
        "rest.backgroundSetup": "FORM'u arka planda otomatik başlat",
        "rest.backgroundExplanation": "Xiaomi ve HyperOS, uygulamayı yeniden açana kadar FORM'un biten süre uyarısını göndermesini engelleyebilir. Arka planda otomatik başlatma ekranını aç, FORM'u etkinleştir ve geri dön.",
        "settings.title": "Ayarlar",
        "settings.training": "Antrenman programları",
        "settings.prefillNextSet": "Sonraki seti doldur",
        "settings.prefillNextSetSubtitle": "Önceki setin ağırlık ve tekrarını kopyala",
        "settings.timerAndAlerts": "Dinlenme süresi ve uyarılar",
        "settings.defaultRest": "Varsayılan dinlenme süresi",
        "settings.lockedScreenAlerts": "Kilitli ekran dinlenme uyarıları",
        "settings.alertsActive": "Açık",
        "settings.alertsNeedsSetup": "Kurulum gerekli",
        "settings.backgroundSetup": "Arka planda otomatik başlatma (Xiaomi / HyperOS)",
        "settings.backgroundActive": "Yapılandırıldı",
        "settings.backgroundNeedsReview": "İnceleme gerekli",
        "settings.language": "Dil",
        "settings.dataManagement": "Veri ve depolama",
        "settings.exportBackup": "Yedeği dışa aktar (JSON)",
        "settings.restoreBackup": "Yedekten geri yükle",
        "settings.about": "FORM hakkında",
        "settings.aboutDescription": "FORM; antrenmanlarınızı kaydetmek, hareket animasyonları ve teknik ipuçlarıyla formunuzu geliştirmek ve güç gelişiminizi sürdürmek için tasarlanmış, sade ve temiz bir güç antrenmanı yardımcısıdır.",
        "settings.version": "v1.0",
        "video.openExternal": "YouTube'da aç",
        "video.close": "Videoyu kapat",
        "anatomy.title": "Çalışan kaslar",
        "anatomy.primary": "Birincil kaslar",
        "anatomy.secondary": "İkincil kaslar",
        "anatomy.front": "Ön",
        "anatomy.back": "Arka",
        "anatomy.unavailable": "Bu egzersiz için kas bilgisi henüz mevcut değil.",
        "anatomy.note": "Başlıca kas grupları gösterilir. Vurgular temsilidir; aktivasyon ölçümü değildir.",
        "video.back5": "5 saniye geri",
        "video.forward5": "5 saniye ileri",
        "video.play": "Videoyu oynat",
        "video.pause": "Videoyu duraklat",
        "video.resume": "Videoya devam et",
        "video.replay": "Videoyu yeniden oynat",
        "video.loading": "Video yükleniyor…",
        "video.retry": "Tekrar dene",
        "video.invalid": "Bu YouTube bağlantısı geçerli değil.",
        "video.youtubeOnly": "Şu anda yalnızca YouTube videoları ve Shorts destekleniyor.",
        "video.networkError": "Video yüklenemedi. Bağlantını kontrol edip tekrar dene.",
        "video.embedError": "YouTube bu videoyu burada oynatamadı. Tekrar dene veya YouTube'da aç.",
        "video.linkTitle": "Egzersiz videolarını bağla",
        "video.linkSubtitle": "Teknik ve form gösterim video bağlantılarını yönet",
        "video.urlInputLabel": "Video bağlantısı",
        "video.urlInputPlaceholder": "YouTube videosu veya Shorts bağlantısını yapıştır",
        "video.addUrlButton": "Bağlantı ekle",
        "video.paste": "Yapıştır",
        "video.preview": "Önizle",
        "video.linkedCount": "Bağlı videolar ({count}/3)",
        "video.tapToPlay": "Oynatmak için dokun",
        "video.maxReached": "En fazla 3 video bağlanabilir",
        "video.maxReachedHint": "En fazla 3 video bağlanabilir. Yeni eklemek için mevcut bir videoyu kaldırın.",
        "video.alreadyAdded": "Bu video zaten ekli.",
        "video.noVideos": "Bu egzersize henüz video bağlanmadı. Aşağıdan bir YouTube bağlantısı ekleyin.",
        "video.saveLinks": "Video bağlantılarını kaydet",
        "notice.videosUpdated": "{name} videoları güncellendi",
        "nav.history": "Geçmiş",
        "history.thisMonth": "Bu ay",
        "history.previousMonth": "Önceki ay",
        "history.nextMonth": "Sonraki ay",
        "history.completed": "Tamamlandı",
        "history.unfinished": "Yarım kaldı",
        "history.missed": "Kaçırıldı",
        "history.future": "Gelecek gün",
        "history.neutral": "Dinlenme günü veya kayıt yok",
        "history.notStarted": "Başlanmadı",
        "history.setsProgress": "{total} setten {done} tamamlandı",
        "history.setsDoneCount": "{count} set yapıldı",
        "history.setsRemainingCount": "{count} set kaldı",
        "history.duration": "Süre",
        "history.sets": "Setler",
        "history.volume": "Hacim",
        "history.close": "Kapat",
        "history.toContinue": "Devam etmek için",
        "history.setsFraction": "{completed} / {total} set",
        "history.resumeWorkout": "Antrenmana devam et",
        "history.startWorkout": "Antrenmana başla",
        "history.scheduledWorkout": "Planlanan antrenman",
        "programs.title": "Programlar",
        "programs.new": "Yeni program",
        "header.newProgram": "Yeni program",
        "programs.import": "JSON içe aktar",
        "programs.apply": "Uygula",
        "programs.export": "Dışa aktar",
        "programs.edit": "Düzenle",
        "programs.active": "AKTİF",
        "programs.counts": "{workouts} antrenman · {exercises} egzersiz",
        "programs.empty": "Henüz program yok",
        "programs.emptyHint": "Bir program oluştur veya FORM program JSON dosyası içe aktar.",
        "programs.deleteTitle": "{name} silinsin mi?",
        "programs.deleteHint": "Program ve antrenmanları silinir. Geçmiş antrenman kayıtları korunur. Bir kopya istersen önce dışa aktar.",
        "programs.defaultRestHint": "Yeni egzersizlerde ve restSeconds içermeyen dosyalarda kullanılır. Mevcut egzersizlerin süresi değişmez. 0, sayacı atlar.",
        "programs.seconds": "Saniye (0–900)",
        "programs.save": "Kaydet",
        "programs.review": "İçe aktarmayı incele",
        "programs.updateHint": "Program kimliği mevcut bir programla eşleşiyor. Onaylandığında aşağıdaki silmeler dahil bu programın planı değiştirilir. Diğer programlar ve antrenman geçmişi korunur.",
        "programs.addHint": "Yeni bir program eklenir. Mevcut programlar ve antrenman geçmişi korunur.",
        "programs.noChanges": "Bu programda değişiklik yok.",
        "programs.change.added": "EKLE",
        "programs.change.updated": "GÜNCELLE",
        "programs.change.removed": "KALDIR",
        "programs.idHint": "Dosyayı düzenlerken kimlikleri değiştirme. Farklı program kimliği yeni bir program oluşturur.",
        "programs.update": "Programı güncelle",
        "programs.add": "Programı ekle",
        "programs.exported": "Program dışa aktarıldı.",
        "programs.imported": "Program içe aktarıldı.",
        "programs.sessionBlocked": "Programını değiştirmeden önce mevcut antrenmanı bitir veya iptal et.",
        "programs.restoreTitle": "Her şey yedekten değiştirilsin mi?",
        "programs.restoreHint": "Tüm programlar, tamamlanma kayıtları ve antrenman geçmişi değiştirilir, aktif antrenman iptal edilir. Tek programı değiştirmek için iptal et ve Programlar → JSON içe aktar seçeneğini kullan.",
        "programs.fileError": "Dosya uygulanamadı",
        "programs.close": "Kapat",
        "programs.restSeconds": "Setler arası dinlenme (saniye)",
        "programs.restHint": "0–900 saniye. 0, sayacı atlar.",
        "programs.movement": "Hareket görseli",
        "programs.videoHint": "Her satıra bir tane olmak üzere en fazla 3 YouTube videosu veya Shorts bağlantısı kullan.",
        "programs.dayTaken": "Bu günde zaten bir antrenman var. Boş bir gün seç.",
        "category.other": "DİĞER",
        "common.back": "Geri",
        "today.thisWeek": "Bu hafta",
        "today.weekProgress": "Haftalık ilerleme",
        "today.weeklyGoalProgress": "Haftalık Hedef İlerlemesi",
        "today.totalVolume": "TOPLAM HACİM",
        "today.activeTime": "AKTİF SÜRE",
        "today.prsHit": "KIRILAN PR'LAR",
        "library.title": "Egzersiz kütüphanesi",
        "library.viewCards": "Kart görünümü",
        "library.viewList": "Liste görünümü",
        "library.search": "Egzersiz ara",
        "library.clearSearch": "Aramayı temizle",
        "library.filters": "Filtreler",
        "library.scope": "Katalog",
        "library.allExercises": "Tüm egzersizler",
        "library.currentProgram": "Mevcut program",
        "library.currentWorkout": "Mevcut antrenman",
        "library.resultCount": "{count} egzersiz",
        "library.movement": "Hareket",
        "library.equipment": "Ekipman",
        "library.any": "Tümü",
        "library.resetFilters": "Filtreleri sıfırla",
        "library.clearFilter": "Filtreyi kaldır",
        "library.clearAll": "Tümünü temizle",
        "library.noResults": "Egzersiz bulunamadı.",
        "library.details": "Egzersiz detayları",
        "library.addNotes": "Teknik notları ekle",
        "library.videos": "Teknik videolar",
        "library.videoUnavailable": "Video kullanılamıyor",
        "library.remove": "Kaldır",
        "library.videoError": "Video bağlantısı açılamadı.",
        "session.technique": "Teknik ve dikkat edilecekler",
        "session.review": "Antrenmanı incele",
        "table.reps": "TEKRAR",
        "table.removeSet": "Son seti sil",
        "table.undo": "Set tamamlanmasını geri al",
        "rest.title": "Dinlenme sayacı",
        "rest.finished": "HAZIR",
        "rest.resting": "DİNLENME",
        "rest.paused": "DURAKLATILDI",
        "rest.target": "Hedef: {time}",
        "rest.skip": "Dinlenmeyi atla",
        "rest.expand": "Sayacı genişlet",
        "rest.minimize": "Sayacı küçült",
        "rest.mute": "Sayaç sesini kapat",
        "rest.unmute": "Sayaç sesini aç",
        "summary.back": "Antrenmana dön",
        "editor.deleteTitle": "Bu öğe silinsin mi?",
        "editor.deleteConfirm": "Bu öğe ve içeriği silinir. Bu işlem geri alınamaz.",
        "nav.today": "Bugün",
        "nav.plan": "Program",
        "nav.library": "Kütüphane",
        "plan.progressComplete": "TAMAMLANDI",
        "plan.recover": "Dinlenme",
        "plan.startWorkout": "Antrenmanı başlat",
        "plan.resumeWorkout": "Antrenmana devam et",
        "plan.editWorkout": "Antrenmanı düzenle",
        "today.todayWorkout": "Bugünün antrenmanı",
        "today.completed": "Tamamlandı",
        "today.workoutMeta": "{exercises} egzersiz · yaklaşık {minutes} dk",
        "today.exercises": "Egzersizler",
        "today.restDay": "Dinlenme günü",
        "today.restDescription": "Bugün için planlanmış antrenman yok. Yukarıdan bir antrenman seçebilirsin.",
        "today.emptyTitle": "Henüz antrenman yok",
        "today.emptyDescription": "Haftalık planından bu programa bir antrenman ekleyebilirsin.",
        "today.openPlan": "Haftalık programı aç",
        "today.availableOn": "{day} günü açılır",
        "weekly.title": "Haftalık program",
        "weekly.currentProgram": "Mevcut program",
        "weekly.changeProgram": "Programı değiştir",
        "weekly.exerciseCount": "{count} egzersiz",
        "weekly.restDay": "Toparlanma günü",
        "library.editWorkout": "Antrenmanı düzenle",
        "library.addExercise": "Egzersiz ekle",
        "library.videoItem": "Video {num}",
        "library.attachVideoCta": "Video ekle",
        "category.press": "İTİŞ",
        "category.pull-up": "BARFİKS",
        "category.row": "ÇEKİŞ",
        "category.shoulder-raise": "OMUZ AÇIŞ",
        "category.curl": "BİSEPS",
        "category.triceps": "TRİSEPS",
        "category.squat": "SQUAT",
        "category.hinge": "DEADLIFT / HINGE",
        "category.lunge": "LUNGE",
        "category.calf": "KALF",
        "category.core": "KARIN / CORE",
        "category.conditioning": "KONDİSYON",
        "category.boxing": "BOKS",
        "modal.cancel": "İptal",
        "modal.delete": "Sil",
        "modal.program.titleAdd": "Yeni program",
        "modal.program.titleEdit": "Programı düzenle",
        "modal.program.name": "Program adı",
        "modal.program.namePlaceholder": "Örn: Yaz kuvvet dönemi",
        "modal.program.desc": "Açıklama",
        "modal.program.notes": "Program geneli güvenlik notları",
        "modal.program.save": "Programı kaydet",
        "builder.details": "Program detayları",
        "builder.detailsHint": "Ad ve genel bilgiler",
        "builder.optionalDetails": "Açıklama ve güvenlik notları",
        "builder.optional": "İsteğe bağlı",
        "builder.showOptionalDetails": "İsteğe bağlı program detaylarını göster",
        "builder.hideOptionalDetails": "İsteğe bağlı program detaylarını gizle",
        "builder.trainingDays": "Antrenman günleri",
        "builder.dayCount": "7 günün {count} günü",
        "builder.addTrainingDay": "Antrenman günü ekle",
        "builder.noDays": "Antrenman günlerini seç",
        "builder.noDaysHint": "Bir gün ekle, odağını belirle ve kütüphaneden egzersizleri seç.",
        "builder.exerciseCount": "{count} egzersiz",
        "builder.exerciseCountOne": "1 egzersiz",
        "builder.addExercises": "Egzersiz ekle",
        "builder.editDay": "Antrenman gününü düzenle",
        "builder.expandDay": "Egzersizleri göster",
        "builder.collapseDay": "Egzersizleri gizle",
        "builder.incompleteDays": "{count} antrenman gününde egzersiz yok; bu günler henüz başlatılamaz.",
        "builder.chooseExercises": "Egzersiz seç",
        "builder.searchExercises": "Egzersiz kütüphanesinde ara",
        "builder.allMovements": "Tümü",
        "builder.alreadyAdded": "Bu günde zaten var",
        "builder.addSelected": "Seçilenleri ekle · {count}",
        "builder.exerciseActions": "Egzersiz işlemleri",
        "builder.editExercise": "Hedefleri ve detayları düzenle",
        "builder.moveEarlier": "Yukarı taşı",
        "builder.moveLater": "Aşağı taşı",
        "builder.removeExercise": "Bu günden kaldır",
        "builder.saveFailed": "Program kaydedilemedi. Günleri ve egzersizleri kontrol et.",
        "modal.workout.titleAdd": "Antrenman ekle",
        "modal.workout.titleEdit": "Antrenmanı düzenle",
        "modal.workout.name": "Antrenman adı",
        "modal.workout.namePlaceholder": "Örn: Üst Vücut A",
        "modal.workout.focus": "Odak noktası",
        "modal.workout.day": "Haftanın günü",
        "modal.workout.save": "Antrenmanı kaydet",
        "muscles.title": "Hedef kaslar",
        "muscles.hint": "İsteğe bağlı. İlk seçim başlangıç görünümünü belirler. Vurgusuz görsel için boş bırakın.",
        "muscles.view.back": "Sırt",
        "muscles.view.front": "Ön",
        "muscles.view.legs-front": "Bacak · ön",
        "muscles.view.legs-back": "Bacak · arka",
        "muscle.chest": "Göğüs",
        "muscle.abs": "Karın",
        "muscle.obliques": "Yan karın",
        "muscle.biceps": "Biseps",
        "muscle.triceps": "Triseps",
        "muscle.shoulders": "Omuz",
        "muscle.trapezius": "Trapez",
        "muscle.lats": "Kanat",
        "muscle.lower-back": "Bel",
        "muscle.forearms": "Ön kol",
        "muscle.quadriceps": "Ön bacak",
        "muscle.hamstrings": "Arka bacak",
        "muscle.calves": "Baldır",
        "muscle.glutes": "Kalça",
        "modal.exercise.titleAdd": "Egzersiz ekle",
        "modal.exercise.titleEdit": "Egzersizi düzenle",
        "modal.exercise.name": "Egzersiz adı",
        "modal.exercise.prescription": "Set × tekrar",
        "modal.exercise.cues": "Teknik ipuçları",
        "modal.exercise.avoid": "Kaçınılması gerekenler",
        "modal.exercise.videos": "Video bağlantıları",
        "modal.exercise.save": "Egzersizi kaydet",
        "session.exit": "Antrenmandan çık",
        "session.exitConfirm": "Mevcut antrenman seansından çıkılsın mı? Kaydedilmemiş set ilerlemesi sıfırlanacaktır.",
        "session.finish": "Bitir",
        "session.finishBtn": "Bitir",
        "session.prevExercise": "Önceki egzersiz",
        "session.nextExercise": "Sonraki egzersiz",
        "common.done": "Tamam",
        "history.workoutDetail": "Antrenman Detayları",
        "library.clearFilters": "Filtreleri temizle",
        "library.filterMovement": "Hareket",
        "summary.saveAndClose": "Antrenmanı kaydet",
        "table.deleteSet": "Seti sil",
        "table.set": "SET",
        "table.weightKg": "AĞIRLIK (KG)",
        "table.actualReps": "GERÇEKLEŞEN TEKRAR",
        "table.done": "Tamam",
        "table.doneHeading": "BİTTİ",
        "table.currentSet": "Set {current} / {total}",
        "table.allSetsDone": "{total} set tamamlandı",
        "table.complete": "Seti tamamla",
        "table.addSet": "Set ekle",
        "rest.pause": "Duraklat",
        "rest.resume": "Devam",
        "summary.badge": "Antrenman özeti",
        "summary.totalDuration": "Süre",
        "summary.estimatedVolume": "Hacim",
        "summary.setsCompleted": "Tamamlanan set",
        "summary.exerciseRecap": "Egzersiz özeti",
        "summary.setsDone": "{count} set tamamlandı",
        "summary.saveBtn": "Antrenmanı kaydet",
        "notice.backupRestored": "Yedek başarıyla geri yüklendi.",
        "notice.backupDownloaded": "Yedek indirildi.",
        "notice.needOneExercise": "Antrenmanı başlatmadan önce lütfen en az bir egzersiz ekleyin.",
        "notice.upcomingWorkout": "Bu antrenman {day} günü açılır.",
        "notice.workoutRecorded": "Antrenman kaydedildi: {sets} set, {volume}kg hacim.",
        "notice.workoutAdded": "Antrenman eklendi.",
        "notice.workoutUpdated": "Antrenman güncellendi.",
        "notice.workoutDeleted": "Antrenman silindi.",
        "notice.exerciseAdded": "Egzersiz eklendi.",
        "notice.exerciseUpdated": "Egzersiz güncellendi.",
        "notice.exerciseDeleted": "Egzersiz silindi.",
        "notice.programCreated": "Program oluşturuldu.",
        "notice.programUpdated": "Program güncellendi.",
        "notice.programDeleted": "Program silindi.",
        "notice.programApplied": "{name} programına geçildi.",
        "notice.emptySetWarning": "Tekrar ve ağırlık bilgisi boş bırakılamaz.",
        "notice.restActiveWarning": "Dinlenme sayacı devredeyken set tamamlanamaz.",
    ]
}
