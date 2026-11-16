import Foundation

/// Перемешивание Фишера — Йейтса: каждая перестановка равновероятна.
enum FisherYates {
    /// Перемешивает с заданным генератором случайных чисел (в тестах — с предсказуемым).
    static func shuffled<T, G: RandomNumberGenerator>(_ items: [T], using generator: inout G) -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        // Идём с конца: элемент i меняется местами со случайным из 0...i
        var i = result.count - 1
        while i > 0 {
            let j = Int.random(in: 0...i, using: &generator)
            if i != j {
                result.swapAt(i, j)
            }
            i -= 1
        }
        return result
    }

    static func shuffled<T>(_ items: [T]) -> [T] {
        var generator = SystemRandomNumberGenerator()
        return shuffled(items, using: &generator)
    }

    /// Перестановка элементов как при перетаскивании в списке:
    /// элементы с номерами `offsets` переезжают на позицию `destination`.
    static func moved<T>(_ items: [T], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [T] {
        var result = items
        let moving = offsets.sorted().map { items[$0] }
        for index in offsets.sorted(by: >) {
            result.remove(at: index)
        }
        let shift = offsets.filter { $0 < destination }.count
        let target = min(max(0, destination - shift), result.count)
        result.insert(contentsOf: moving, at: target)
        return result
    }
}
