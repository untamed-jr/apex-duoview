import Foundation

/// The next live programme to offer while a live one is watched (Android's `pickNextLive`).
public enum NextLive {
    /// The first of F1 TV's "live now" items (`live`, in its order) that is not on screen, not
    /// turned down with "Not now", and either went live after the watched programme was opened
    /// (it is not in `liveAtStart`) or, once the watched broadcast has ended, is any live item.
    /// Content ids of 0 or less are never offered. Nil when nothing qualifies.
    public static func pick(live: [CatalogItem], onScreen: Int, liveAtStart: Set<Int>, declined: Set<Int>,
                            watchedEnded: Bool) -> CatalogItem? {
        live.first { item in
            item.contentId > 0 && item.contentId != onScreen && !declined.contains(item.contentId)
                && (watchedEnded || !liveAtStart.contains(item.contentId))
        }
    }
}
