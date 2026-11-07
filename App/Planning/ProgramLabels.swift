import Planning

// Nazivi gotovih programa na jeziku sučelja. U GymKitu su hrvatski nazivi; ovdje idu kroz String Catalog.

extension Program {
    var title: String {
        switch id {
        case "basic-full-body-2": String(localized: "Osnovni full body (2 dana)")
        case "beginner-full-body-3": String(localized: "Početnički full body (3 dana)")
        case "full-body-3": String(localized: "Full body (3 dana)")
        case "upper-lower-4": String(localized: "Upper/Lower (4 dana)")
        case "upper-lower-ppl-5": String(localized: "Upper/Lower + PPL (5 dana)")
        case "ppl-6": String(localized: "Push/Pull/Legs (6 dana)")
        default: name
        }
    }

    var details: String {
        switch id {
        case "basic-full-body-2":
            String(localized: "Dva kratka treninga cijelog tijela tjedno. Dovoljno za zdravlje i napredak kad nema više vremena.")
        case "beginner-full-body-3":
            String(localized: "Treninzi A i B naizmjence, tri puta tjedno. Malo vježbi, svaki mišić tri puta tjedno.")
        case "full-body-3":
            String(localized: "Tri različita treninga cijelog tijela tjedno, svaki mišić dva do tri puta.")
        case "upper-lower-4":
            String(localized: "Dva dana gornjeg i dva dana donjeg dijela tijela tjedno, svaki mišić dvaput.")
        case "upper-lower-ppl-5":
            String(localized: "Gornji i donji dio tijela, dan odmora, pa guranje, povlačenje i noge. Svaki mišić dvaput tjedno.")
        case "ppl-6":
            String(localized: "Guranje, povlačenje i noge dvaput tjedno, s dvije varijante svakog treninga.")
        default: summary
        }
    }
}

extension ProgramWorkout {
    var title: String {
        switch key {
        case "basicA", "beginnerA", "fullA": String(localized: "Cijelo tijelo A")
        case "basicB", "beginnerB", "fullB": String(localized: "Cijelo tijelo B")
        case "fullC": String(localized: "Cijelo tijelo C")
        case "upperA": String(localized: "Gornji dio tijela A")
        case "upperB": String(localized: "Gornji dio tijela B")
        case "lowerA": String(localized: "Donji dio tijela A")
        case "lowerB": String(localized: "Donji dio tijela B")
        case "pushA": String(localized: "Push A")
        case "pushB": String(localized: "Push B")
        case "pullA": String(localized: "Pull A")
        case "pullB": String(localized: "Pull B")
        case "legsA": String(localized: "Noge A")
        case "legsB": String(localized: "Noge B")
        default: name
        }
    }
}
