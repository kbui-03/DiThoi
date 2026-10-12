import Foundation

/// Every step a trip can be set up through, in order.
///
/// Which of them a given flow walks is up to each step, not to a chain of
/// `if`s. Adding one is a case here and a line in `isIncluded`, and the order
/// can't be got wrong at a call site because there isn't one. The first trip
/// and every trip after it go through the same list.
///
/// In `Model/` rather than beside `ArrivalFlow`, which only draws them. The
/// rules branch on four things now, and `Features/` isn't compiled by
/// `run-checks.sh`: a registry whose whole job is deciding which questions
/// get asked wants a check, the way `whatTravels` and `packedSummary` do.
enum SetupStep: CaseIterable, Equatable {
    case hello, destination, who, writingTo, inside, dates, itinerary, invite

    func isIncluded(_ context: SetupContext) -> Bool {
        switch self {
        // The tap on "Start the next trip" was the hello.
        case .hello: !context.returning
        // A returning traveller is asked where next before anything else.
        // Not the observer, who sets no trip parameters, and not a first
        // launch, where who is holding the phone decides the whole app.
        case .destination: context.returningTraveller
        // Asked outright unless it is already answered, and then only when
        // somebody says the answer changed.
        case .who: !context.returningTraveller || context.changingWho
        // The observer's letters are addressed, so who they are for is a
        // question the flow has to ask rather than inherit.
        case .writingTo: context.isObserver
        // Somebody else answered the trip's questions: confirm them.
        case .inside: context.isPacked || context.isObserver
        case .dates, .itinerary: !(context.isPacked || context.isObserver)
        case .invite: context.invites
        }
    }

    /// The steps a context walks, in order.
    static func steps(for context: SetupContext) -> [SetupStep] {
        allCases.filter { $0.isIncluded(context) }
    }
}

/// What decides the steps.
///
/// A flow holds an index into `SetupStep.steps(for:)`, so a change here may
/// only ever add or remove steps *after* the one on screen. Anything that
/// could move one before it is captured once, when the flow opens:
///
/// - `returning` and `returningTraveller`: the `who` step writes the names
///   and the role that decide them, so asking again halfway would drop
///   `hello` or `destination` out from under the index.
/// - `changingWho` only ever inserts `who`, directly after `destination`,
///   and is only ever set from `destination`.
/// - `isObserver` may change on the `who` step itself, which removes
///   `dates`/`itinerary` and adds `writingTo`/`inside` — all of them after it.
struct SetupContext: Equatable {
    var isObserver: Bool
    var isPacked: Bool
    var invites: Bool
    var returning: Bool
    /// Returning, and not the observer, at the moment the flow opened.
    var returningTraveller: Bool = false
    var changingWho: Bool = false
}
