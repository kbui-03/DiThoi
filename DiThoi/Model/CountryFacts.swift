import Foundation

/// The few things about a country that are worth knowing at 2am and that are
/// still true in five years.
///
/// Emergency numbers come from here so the screens never print one country's
/// under another country's name.
///
/// Two rules hold this together:
///
/// 1. **An unknown country returns `nil`, and `nil` draws nothing.**
///    `Leg.country` is free text, so most countries somebody types will not be
///    in here, and silence is the right output for those. The rule runs per
///    column as well as per country: a country can be known and still say
///    nothing about its language, its sockets or its phrases.
/// 2. **Only what stays true lives here.** The test is staleness, not
///    usefulness. Emergency numbers, socket standards, mains voltage and a
///    sentence in a fixed script don't move, so they are in.
///
///    Asked for and left out:
///
///    - **Airport taxi fares.** Wrong within a year, and "the airport" isn't
///      one place in most of these countries.
///    - **The nearest consulate.** Addresses and duty numbers move, and it
///      needs a nationality the app has never asked for. Papers holds the
///      passport scans, which is the part the app can keep.
///    - Tipping, opening hours, visa rules, anything seasonal.
struct CountryFacts: Equatable {

    /// One number and what it reaches.
    struct Service: Equatable {
        var number: String
        /// Lowercase, because it renders inline: "191 police · 1669 medical".
        var label: String
    }

    /// What comes out of the wall.
    ///
    /// Here because a country does not re-wire itself. Socket standards outlast
    /// governments, which is the only test this file applies.
    struct Power: Equatable {
        /// IEC letter types, in the order somebody would meet them.
        var sockets: [String]
        /// Written out rather than held as two numbers, because it is not
        /// always two numbers: Japan runs 100 V at 50 Hz in the east and 60 Hz
        /// in the west, and Brazil runs 127 V and 220 V in different states.
        /// A struct with `volts: Int` would have forced a wrong answer for
        /// both, and this string is only ever rendered.
        var mains: String

        /// "Type C, F"
        var socketLine: String {
            "Type " + sockets.joined(separator: ", ")
        }
    }

    /// The two sentences worth having in the local script, for the night
    /// nothing else is working.
    ///
    /// This is not the translation service the show-this card editor refuses.
    /// That one is asked to carry arbitrary text somebody typed, in a language
    /// the app cannot read back; this is a fixed pair, written once, checked
    /// once, and never assembled from anything.
    ///
    /// Bound to `language` by the same discipline: a country with no single
    /// honest language has no phrases either, and the check enforces it.
    struct Phrases: Equatable {
        var doctor: String
        var lostPassport: String
    }

    /// The canonical spelling, for anywhere that wants to name it.
    var country: String
    /// In the order somebody in trouble would want them.
    var emergency: [Service]

    /// What to call the language a stranger here is most likely to read.
    ///
    /// It exists to *label* the show-this card editor's first field — "Thai",
    /// "Vietnamese" — so the travellers know which language they are being
    /// asked to write. The app never translates and this is not a translation
    /// table; it is a word to put above a text field.
    ///
    /// `nil` wherever there is no single honest answer, which is rule 1 applied
    /// to a second column: Belgium, Switzerland, Canada, India, South Africa.
    /// Labelling a field "Hindi" in Chennai is the same class of mistake as
    /// printing Thai emergency numbers under "Vietnam", and the fallback — an
    /// unlabelled "local language" — costs nothing.
    var language: String?

    /// Sockets and mains, or `nil` where this app doesn't know.
    var power: Power?

    /// The two phrases in the local script, or `nil`.
    ///
    /// `nil` for three different reasons, all of them rule 1:
    ///
    /// - the language is `nil`, so there is no one script to write in;
    /// - the language is English, so the card already says it;
    /// - nobody has checked the sentences with somebody who reads them.
    ///
    /// The last is the list to grow, and it is deliberately a whitelist rather
    /// than an oversight: Khmer, Lao, Nepali, Sinhala, Filipino, Croatian,
    /// Slovak, Slovene, Bulgarian, Estonian, Latvian, Lithuanian, Icelandic and
    /// Maltese are all `nil` here pending a reader. A missing phrase costs a
    /// gesture and a pointed finger. A wrong one gets held up to a stranger in
    /// an emergency and sends somebody nowhere, which is the whole argument
    /// this file already makes about emergency numbers.
    var phrases: Phrases?

    /// "191 police · 1669 medical" — the format the screen already used, now
    /// assembled from the country actually being stood in.
    var emergencyLine: String {
        emergency.map { "\($0.number) \($0.label)" }.joined(separator: " · ")
    }

    /// True when there is more here than the emergency numbers — which is the
    /// question "is a card worth opening?" and therefore whether Papers draws a
    /// row at all.
    var hasCard: Bool {
        power != nil || phrases != nil
    }

    /// The `tel:` link for a number, or `nil` if it isn't one.
    ///
    /// `nil` means the tile prints the number and dials nothing. The tile used
    /// to fall back to `tel://112` — a tap on a number that failed to parse
    /// rang an emergency line nobody chose, in a country that may not answer
    /// it. Spaces and dashes are how numbers are written; anything else is not
    /// a number.
    static func dialURL(_ number: String) -> URL? {
        let digits = number.filter { $0 != " " && $0 != "-" }
        guard !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && ($0.isNumber || "+*#".contains($0)) })
        else { return nil }
        return URL(string: "tel://\(digits)")
    }

    // MARK: - Lookup

    /// The facts for a country name, or `nil` if this app has never heard of it.
    ///
    /// Deliberately returns an optional rather than a default. There is no
    /// sensible fallback for an emergency number: a wrong one is worse than a
    /// missing one, because a missing one sends somebody to a hotel desk and a
    /// wrong one sends them nowhere.
    static func lookup(_ name: String) -> CountryFacts? {
        let key = normalise(name)
        guard !key.isEmpty else { return nil }
        return byKey[key]
    }

    /// Case, accents, punctuation and a leading "the" are all things somebody
    /// might type differently from how the table spells it, and none of them
    /// change which country is meant.
    static func normalise(_ name: String) -> String {
        let folded = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return folded.hasPrefix("the ") ? String(folded.dropFirst(4)) : folded
    }

    // MARK: - The table

    /// Every spelling that resolves, built once from `all`.
    private static let byKey: [String: CountryFacts] = {
        var table: [String: CountryFacts] = [:]
        for (facts, aliases) in all {
            for name in [facts.country] + aliases {
                table[normalise(name)] = facts
            }
        }
        return table
    }()

    /// Everywhere the app can speak for, and the other names people write for
    /// them. Kept short on purpose — see the second rule above.
    ///
    /// `112` is the single emergency number across the EU and EEA and is
    /// reachable from any phone there, which is why those countries share one
    /// entry rather than each carrying a national number that also works. The
    /// sockets are not one rule and cannot be — Ireland, Malta and Cyprus take
    /// the British plug, Denmark and Switzerland have their own — so they ride
    /// alongside, one per country.
    private static let all: [(CountryFacts, [String])] = {
        func facts(_ country: String, _ language: String?,
                   _ services: [(String, String)],
                   _ power: Power? = nil, _ phrases: Phrases? = nil) -> CountryFacts {
            CountryFacts(country: country,
                         emergency: services.map { CountryFacts.Service(number: $0.0, label: $0.1) },
                         language: language, power: power, phrases: phrases)
        }

        /// One number for everything.
        func single(_ country: String, _ language: String?, _ number: String,
                    _ power: Power? = nil, _ phrases: Phrases? = nil,
                    _ aliases: [String] = []) -> (CountryFacts, [String]) {
            (facts(country, language, [(number, "for anything")], power, phrases), aliases)
        }

        /// Most of the world is 230 V at 50 Hz, so that is the default and the
        /// exceptions are written out.
        func plug(_ sockets: [String], _ mains: String = "230 V · 50 Hz") -> Power {
            Power(sockets: sockets, mains: mains)
        }

        func say(_ doctor: String, _ lostPassport: String) -> Phrases {
            Phrases(doctor: doctor, lostPassport: lostPassport)
        }

        var entries: [(CountryFacts, [String])] = [
            // The three the packed trip visits.
            (facts("Thailand", "Thai", [("191", "police"), ("1669", "medical")],
                   plug(["A", "B", "C", "O"]),
                   say("ฉันต้องการหมอ", "ฉันทำหนังสือเดินทางหาย")),
             ["Kingdom of Thailand"]),
            (facts("Vietnam", "Vietnamese", [("113", "police"), ("115", "medical"), ("114", "fire")],
                   plug(["A", "B", "C"], "220 V · 50 Hz"),
                   say("Tôi cần bác sĩ", "Tôi bị mất hộ chiếu")),
             ["Viet Nam", "Việt Nam"]),
            (facts("South Korea", "Korean", [("112", "police"), ("119", "medical")],
                   plug(["C", "F"], "220 V · 60 Hz"),
                   say("의사가 필요합니다", "여권을 잃어버렸습니다")),
             ["Korea", "Republic of Korea"]),

            // The rest of the region they are most likely to add.
            (facts("Cambodia", "Khmer", [("117", "police"), ("119", "medical")],
                   plug(["A", "C", "G"])), []),
            (facts("Laos", "Lao", [("191", "police"), ("195", "medical")],
                   plug(["A", "B", "C", "E", "F"])),
             ["Lao PDR", "Lao People's Democratic Republic"]),
            (facts("Japan", "Japanese", [("110", "police"), ("119", "medical")],
                   plug(["A", "B"], "100 V · 50 Hz east, 60 Hz west"),
                   say("医者が必要です", "パスポートをなくしました")), []),
            // Traditional characters here, simplified in the entry below. The
            // language label is the same word and the script is not, which is
            // why phrases are per country rather than per language.
            (facts("Taiwan", "Mandarin", [("110", "police"), ("119", "medical")],
                   plug(["A", "B"], "110 V · 60 Hz"),
                   say("我需要醫生", "我的護照遺失了")), []),
            (facts("China", "Mandarin", [("110", "police"), ("120", "medical")],
                   plug(["A", "C", "I"], "220 V · 50 Hz"),
                   say("我需要医生", "我的护照丢了")),
             ["PRC", "People's Republic of China"]),
            (facts("Singapore", "English", [("999", "police"), ("995", "medical")],
                   plug(["G"])), []),
            (facts("Indonesia", "Indonesian", [("112", "for anything")],
                   plug(["C", "F"]),
                   say("Saya butuh dokter", "Paspor saya hilang")), []),
            (facts("Nepal", "Nepali", [("100", "police"), ("102", "medical")],
                   plug(["C", "D", "M"])), []),
            // Twenty-two scheduled languages. A card labelled "Hindi" is wrong
            // in most of the south, so this one says nothing.
            (facts("India", nil, [("112", "for anything")],
                   plug(["C", "D", "M"])), []),
            (facts("Sri Lanka", nil, [("119", "police"), ("1990", "medical")],
                   plug(["D", "G", "M"])), []),

            // Elsewhere, for a second trip.
            (facts("Australia", "English", [("000", "for anything")],
                   plug(["I"])), []),
            (facts("South Africa", nil, [("10111", "police"), ("10177", "medical")],
                   plug(["C", "D", "M", "N"])), []),
            (facts("Morocco", "Arabic", [("19", "police"), ("15", "medical")],
                   plug(["C", "E"], "220 V · 50 Hz"),
                   say("أحتاج إلى طبيب", "لقد فقدت جواز سفري")), []),
            (facts("Brazil", "Portuguese", [("190", "police"), ("192", "medical")],
                   plug(["C", "N"], "127 V or 220 V by state · 60 Hz"),
                   say("Preciso de um médico", "Perdi meu passaporte")), []),
            (facts("Chile", "Spanish", [("133", "police"), ("131", "medical")],
                   plug(["C", "L"], "220 V · 50 Hz"),
                   say("Necesito un médico", "He perdido mi pasaporte")), []),
            (facts("Peru", "Spanish", [("105", "police"), ("106", "medical")],
                   plug(["A", "B", "C"], "220 V · 60 Hz"),
                   say("Necesito un médico", "He perdido mi pasaporte")), []),

            single("Malaysia", "Malay", "999", plug(["G"], "240 V · 50 Hz"),
                   say("Saya perlukan doktor", "Pasport saya hilang")),
            single("Philippines", "Filipino", "911", plug(["A", "B", "C"], "220 V · 60 Hz")),
            single("New Zealand", "English", "111", plug(["I"]), nil, ["Aotearoa"]),
            single("United States", "English", "911", plug(["A", "B"], "120 V · 60 Hz"), nil,
                   ["USA", "US", "America", "United States of America"]),
            single("Canada", nil, "911", plug(["A", "B"], "120 V · 60 Hz")),
            single("Mexico", "Spanish", "911", plug(["A", "B"], "127 V · 60 Hz"),
                   say("Necesito un médico", "He perdido mi pasaporte")),
            single("Argentina", "Spanish", "911", plug(["C", "I"], "220 V · 50 Hz"),
                   say("Necesito un médico", "He perdido mi pasaporte")),
            single("United Kingdom", "English", "999", plug(["G"]), nil,
                   ["UK", "Britain", "Great Britain", "England", "Scotland", "Wales"]),
            single("Turkey", "Turkish", "112", plug(["C", "F"]),
                   say("Doktora ihtiyacım var", "Pasaportumu kaybettim"),
                   ["Türkiye"])
        ]

        // The EU and EEA answer 112 everywhere, so they are one rule rather
        // than thirty facts that could each be wrong on their own. Everything
        // else about them is per country.
        let oneOneTwo: [(String, String?, [String], Phrases?)] = [
            ("Netherlands", "Dutch", ["C", "F"],
             say("Ik heb een dokter nodig", "Ik ben mijn paspoort verloren")),
            ("Belgium", nil, ["C", "E"], nil),
            ("Germany", "German", ["C", "F"],
             say("Ich brauche einen Arzt", "Ich habe meinen Pass verloren")),
            ("France", "French", ["C", "E"],
             say("J'ai besoin d'un médecin", "J'ai perdu mon passeport")),
            ("Spain", "Spanish", ["C", "F"],
             say("Necesito un médico", "He perdido mi pasaporte")),
            ("Portugal", "Portuguese", ["C", "F"],
             say("Preciso de um médico", "Perdi o meu passaporte")),
            ("Italy", "Italian", ["C", "F", "L"],
             say("Ho bisogno di un medico", "Ho perso il passaporto")),
            ("Greece", "Greek", ["C", "F"],
             say("Χρειάζομαι γιατρό", "Έχασα το διαβατήριό μου")),
            ("Ireland", "English", ["G"], nil),
            ("Austria", "German", ["C", "F"],
             say("Ich brauche einen Arzt", "Ich habe meinen Pass verloren")),
            ("Denmark", "Danish", ["C", "E", "F", "K"],
             say("Jeg har brug for en læge", "Jeg har mistet mit pas")),
            ("Sweden", "Swedish", ["C", "F"],
             say("Jag behöver en läkare", "Jag har tappat bort mitt pass")),
            ("Norway", "Norwegian", ["C", "F"],
             say("Jeg trenger en lege", "Jeg har mistet passet mitt")),
            ("Finland", "Finnish", ["C", "F"],
             say("Tarvitsen lääkäriä", "Olen kadottanut passini")),
            ("Iceland", "Icelandic", ["C", "F"], nil),
            ("Poland", "Polish", ["C", "E"],
             say("Potrzebuję lekarza", "Zgubiłem paszport")),
            ("Czechia", "Czech", ["C", "E"],
             say("Potřebuji lékaře", "Ztratil jsem pas")),
            ("Slovakia", "Slovak", ["C", "E"], nil),
            ("Hungary", "Hungarian", ["C", "F"],
             say("Orvosra van szükségem", "Elvesztettem az útlevelemet")),
            ("Slovenia", "Slovene", ["C", "F"], nil),
            ("Croatia", "Croatian", ["C", "F"], nil),
            ("Romania", "Romanian", ["C", "F"],
             say("Am nevoie de un medic", "Mi-am pierdut pașaportul")),
            ("Bulgaria", "Bulgarian", ["C", "F"], nil),
            ("Estonia", "Estonian", ["C", "F"], nil),
            ("Latvia", "Latvian", ["C", "F"], nil),
            ("Lithuania", "Lithuanian", ["C", "F"], nil),
            ("Luxembourg", nil, ["C", "F"], nil),
            ("Switzerland", nil, ["C", "J"], nil),
            ("Malta", "Maltese", ["G"], nil),
            ("Cyprus", "Greek", ["G"],
             say("Χρειάζομαι γιατρό", "Έχασα το διαβατήριό μου"))
        ]
        for (country, language, sockets, phrases) in oneOneTwo {
            entries.append(single(country, language, "112", plug(sockets), phrases))
        }
        entries.append(single("Czechia", "Czech", "112", plug(["C", "E"]),
                              say("Potřebuji lékaře", "Ztratil jsem pas"),
                              ["Czech Republic"]))
        entries.append(single("Netherlands", "Dutch", "112", plug(["C", "F"]),
                              say("Ik heb een dokter nodig", "Ik ben mijn paspoort verloren"),
                              ["Holland", "Nederland"]))

        return entries
    }()

    /// Every entry, for the checks. Nothing in the app iterates the table —
    /// screens look up the country they are standing in — but the invariants
    /// that keep the columns honest are about the table as a whole.
    static var everyCountry: [CountryFacts] { all.map(\.0) }
}
