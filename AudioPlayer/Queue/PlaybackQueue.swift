import Foundation

/// Режим повтора.
enum RepeatMode: String, Codable, Sendable {
    case off
    /// Весь список по кругу.
    case all
    /// Один трек.
    case one

    /// Следующий режим по нажатию кнопки: Off → All → One → Off.
    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// «Честный рандом»: порядок проигрывания на один круг.
/// Трек не повторится, пока не сыграны все остальные.
struct TrueShuffleState: Codable, Sendable, Equatable {
    /// Порядок проигрывания текущего круга.
    private(set) var order: [UUID] = []
    /// Где мы сейчас в этом порядке. Всё, что левее — история.
    private(set) var position: Int = 0

    var current: UUID? {
        order.indices.contains(position) ? order[position] : nil
    }

    /// Новый круг: текущий трек идёт первым, остальные перемешаны.
    mutating func start<G: RandomNumberGenerator>(items: [UUID], current: UUID?, using generator: inout G) {
        var rest = items
        if let current, let index = rest.firstIndex(of: current) {
            rest.remove(at: index)
            order = [current] + FisherYates.shuffled(rest, using: &generator)
        } else {
            order = FisherYates.shuffled(rest, using: &generator)
        }
        position = 0
    }

    /// Следующий трек. Когда круг закончился: при повторе — новая перетасовка
    /// (первый трек нового круга не совпадает с последним прошлого), иначе nil.
    mutating func next<G: RandomNumberGenerator>(repeatAll: Bool, using generator: inout G) -> UUID? {
        if position + 1 < order.count {
            position += 1
            return order[position]
        }
        guard repeatAll, !order.isEmpty else { return nil }
        let last = order[order.count - 1]
        var fresh = FisherYates.shuffled(order, using: &generator)
        if fresh.count > 1, fresh[0] == last {
            let other = Int.random(in: 1..<fresh.count, using: &generator)
            fresh.swapAt(0, other)
        }
        order = fresh
        position = 0
        return order[0]
    }

    /// Предыдущий трек по истории; nil — мы в начале круга.
    mutating func previous() -> UUID? {
        guard position > 0 else { return nil }
        position -= 1
        return order[position]
    }

    /// Список изменился: удалённые треки исключаются, новые встают
    /// в случайные места среди ещё не сыгранных.
    mutating func sync<G: RandomNumberGenerator>(items: [UUID], using generator: inout G) {
        let allowed = Set(items)
        var kept: [UUID] = []
        var keptBeforePosition = 0
        for (index, uid) in order.enumerated() where allowed.contains(uid) {
            if index < position {
                keptBeforePosition += 1
            }
            kept.append(uid)
        }
        var newPosition = min(keptBeforePosition, max(0, kept.count - 1))
        let known = Set(kept)
        var seen = Set<UUID>()
        for uid in items where !known.contains(uid) && !seen.contains(uid) {
            seen.insert(uid)
            if kept.isEmpty {
                kept.append(uid)
                newPosition = 0
            } else {
                let low = newPosition + 1
                let slot = Int.random(in: low...kept.count, using: &generator)
                kept.insert(uid, at: slot)
            }
        }
        order = kept
        position = newPosition
    }
}

/// Очередь воспроизведения: список в порядке показа + режимы повтора и рандома.
/// Чистая логика без звука и базы — её проверяют unit-тесты.
struct PlaybackQueue: Codable, Sendable {
    /// Треки в том порядке, как они показаны в списке.
    private(set) var items: [UUID] = []
    /// Текущий трек.
    private(set) var currentUID: UUID?
    var repeatMode: RepeatMode = .off
    /// Включён «честный рандом».
    private(set) var shuffleOn: Bool = false
    private(set) var shuffle = TrueShuffleState()

    var isEmpty: Bool { items.isEmpty }

    /// Номер текущего трека в списке (с нуля).
    var currentIndex: Int? {
        guard let currentUID else { return nil }
        return items.firstIndex(of: currentUID)
    }

    // MARK: - Изменение очереди

    /// Новый список и текущий трек (nil — первый в списке).
    mutating func set<G: RandomNumberGenerator>(items newItems: [UUID], current: UUID?, using generator: inout G) {
        items = newItems
        if let current, newItems.contains(current) {
            currentUID = current
        } else {
            currentUID = newItems.first
        }
        if shuffleOn {
            shuffle.start(items: items, current: currentUID, using: &generator)
        }
    }

    mutating func set(items newItems: [UUID], current: UUID?) {
        var generator = SystemRandomNumberGenerator()
        set(items: newItems, current: current, using: &generator)
    }

    /// Список изменился (добавили, удалили, пересортировали), текущий трек сохраняется.
    mutating func updateItems<G: RandomNumberGenerator>(_ newItems: [UUID], using generator: inout G) {
        items = newItems
        if shuffleOn {
            shuffle.sync(items: newItems, using: &generator)
        }
    }

    mutating func updateItems(_ newItems: [UUID]) {
        var generator = SystemRandomNumberGenerator()
        updateItems(newItems, using: &generator)
    }

    /// Включает или выключает «честный рандом».
    mutating func setShuffle<G: RandomNumberGenerator>(_ isOn: Bool, using generator: inout G) {
        shuffleOn = isOn
        if isOn {
            shuffle.start(items: items, current: currentUID, using: &generator)
        } else {
            shuffle = TrueShuffleState()
        }
    }

    mutating func setShuffle(_ isOn: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffle(isOn, using: &generator)
    }

    // MARK: - Переходы

    /// Следующий трек.
    /// `auto` = true — трек закончился сам (учитывается «повтор одного»),
    /// false — пользователь нажал «Следующий» (переключаем даже при «повторе одного»).
    /// nil — список закончился.
    mutating func advance<G: RandomNumberGenerator>(auto: Bool, using generator: inout G) -> UUID? {
        guard !items.isEmpty else { return nil }
        if auto, repeatMode == .one, let currentUID {
            return currentUID
        }
        if shuffleOn {
            guard let next = shuffle.next(repeatAll: repeatMode == .all, using: &generator) else { return nil }
            currentUID = next
            return next
        }
        guard let index = currentIndex else {
            currentUID = items[0]
            return items[0]
        }
        if index + 1 < items.count {
            currentUID = items[index + 1]
            return currentUID
        }
        if repeatMode == .all {
            currentUID = items[0]
            return currentUID
        }
        return nil
    }

    mutating func advance(auto: Bool) -> UUID? {
        var generator = SystemRandomNumberGenerator()
        return advance(auto: auto, using: &generator)
    }

    /// Предыдущий трек; nil — мы в начале.
    mutating func goBack() -> UUID? {
        if shuffleOn {
            guard let previous = shuffle.previous() else { return nil }
            currentUID = previous
            return previous
        }
        guard let index = currentIndex, index > 0 else { return nil }
        currentUID = items[index - 1]
        return currentUID
    }
}
