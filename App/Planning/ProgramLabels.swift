import Planning

// Nazivi gotovih programa na jeziku sučelja. U GymKitu su hrvatski nazivi; ovdje idu kroz String Catalog.

extension Program {
    var title: String {
        switch id {
        case "full-body-3": String(localized: "Full Body (3 dana)")
        case "upper-lower-4": String(localized: "Upper/Lower (4 dana)")
        default:
            id.hasPrefix("ppl-") ? String(localized: "Push/Pull/Legs (\(daysPerWeek) dana)") : name
        }
    }

    var details: String {
        switch id {
        case "full-body-3": String(localized: "Tri treninga cijelog tijela tjedno s danom odmora između.")
        case "upper-lower-4": String(localized: "Dva dana gornjeg i dva dana donjeg dijela tijela tjedno.")
        default:
            id.hasPrefix("ppl-")
                ? String(localized: "Guranje, povlačenje i noge u zasebnim danima, \(daysPerWeek) treninga u nizu pa jedan dan odmora.")
                : summary
        }
    }
}

extension ProgramWorkout {
    var title: String {
        switch key {
        case "push": String(localized: "Push")
        case "pull": String(localized: "Pull")
        case "legs": String(localized: "Noge")
        case "upper": String(localized: "Gornji dio tijela")
        case "lower": String(localized: "Donji dio tijela")
        case "fullA": String(localized: "Cijelo tijelo A")
        case "fullB": String(localized: "Cijelo tijelo B")
        case "fullC": String(localized: "Cijelo tijelo C")
        default: name
        }
    }
}
