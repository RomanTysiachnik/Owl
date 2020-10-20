//
//  Owl
//  A declarative type-safe framework for building fast and flexible list with Tables & Collections
//
//  Created by Daniele Margutti
//   - Web: https://www.danielemargutti.com
//   - Twitter: https://twitter.com/danielemargutti
//   - Mail: hello@danielemargutti.com
//
//  Copyright © 2019 Daniele Margutti. Licensed under Apache 2.0 License.
//

import Foundation

public extension StagedChangeset where Collection: RangeReplaceableCollection, Collection.Element: ElementRepresentable {
    @inlinable
    init(source: Collection, target: Collection) {
        self.init(source: source, target: target, section: 0)
    }
    @inlinable
    init(source: Collection, target: Collection, section: Int) {
        let sourceElements = ContiguousArray(source)
        let targetElements = ContiguousArray(target)

        // Return empty changesets if both are empty.
        if sourceElements.isEmpty && targetElements.isEmpty {
            self.init()
            return
        }

        // Return changesets that all deletions if source is not empty and target is empty.
        if !sourceElements.isEmpty && targetElements.isEmpty {
            self.init([Changeset(data: target, elementDeleted: sourceElements.indices.map { ElementPath(element: $0, section: section) })])
            return
        }

        // Return changesets that all insertions if source is empty and target is not empty.
        if sourceElements.isEmpty && !targetElements.isEmpty {
            self.init([Changeset(data: target, elementInserted: targetElements.indices.map { ElementPath(element: $0, section: section) })])
            return
        }

        var firstStageElements = ContiguousArray<Collection.Element>()
        var secondStageElements = ContiguousArray<Collection.Element>()

        let result = differentiate(
            source: sourceElements,
            target: targetElements,
            useTargetIndexForUpdated: false,
            mapIndex: { ElementPath(element: $0, section: section) },
            updatedElementsPointer: &firstStageElements,
            notDeletedElementsPointer: &secondStageElements
        )

        var changesets = ContiguousArray<Changeset<Collection>>()

        // The 1st stage changeset.
        // - Includes:
        //   - element updates
        if !result.updated.isEmpty {
            changesets.append(
                Changeset(
                    data: Collection(firstStageElements),
                    elementUpdated: result.updated
                )
            )
        }

        // The 2nd stage changeset.
        // - Includes:
        //   - element deletes
        if !result.deleted.isEmpty {
            changesets.append(
                Changeset(
                    data: Collection(secondStageElements),
                    elementDeleted: result.deleted
                )
            )
        }

        // The 3rd stage changeset.
        // - Includes:
        //   - element inserts
        //   - element moves
        if !result.inserted.isEmpty || !result.moved.isEmpty {
            changesets.append(
                Changeset(
                    data: target,
                    elementInserted: result.inserted,
                    elementMoved: result.moved
                )
            )
        }

        // Set the target to `data` of the last stage.
        if !changesets.isEmpty {
            let index = changesets.index(before: changesets.endIndex)
            changesets[index].data = target
        }

        self.init(changesets)
    }
}

/// A set of changes and metadata as a result of calculating differences in linear collection.
@usableFromInline
internal struct DifferentiateResult<Index> {
    @usableFromInline
    internal let deleted: [Index]
    @usableFromInline
    internal let inserted: [Index]
    @usableFromInline
    internal let updated: [Index]
    @usableFromInline
    internal let moved: [(source: Index, target: Index)]
    @usableFromInline
    internal let sourceTraces: ContiguousArray<Trace<Int>>
    @usableFromInline
    internal let targetReferences: ContiguousArray<Int?>

    @usableFromInline
    internal init(
        deleted: [Index] = [],
        inserted: [Index] = [],
        updated: [Index] = [],
        moved: [(source: Index, target: Index)] = [],
        sourceTraces: ContiguousArray<Trace<Int>>,
        targetReferences: ContiguousArray<Int?>
        ) {
        self.deleted = deleted
        self.inserted = inserted
        self.updated = updated
        self.moved = moved
        self.sourceTraces = sourceTraces
        self.targetReferences = targetReferences
    }
}

/// A set of informations in middle of difference calculation.
@usableFromInline
internal struct Trace<Index> {
    @usableFromInline
    internal var reference: Index?
    @usableFromInline
    internal var deleteOffset = 0
    @usableFromInline
    internal var isTracked = false

    @usableFromInline
    internal init() {}
}

/// The occurrences of element.
@usableFromInline
internal enum Occurrence {
    case unique(index: Int)
    case duplicate(reference: IndicesReference)
}

/// A mutable reference to indices of elements.
@usableFromInline
internal final class IndicesReference {
    @usableFromInline
    internal var indices: ContiguousArray<Int>
    @usableFromInline
    internal var position = 0

    @usableFromInline
    internal init(_ indices: ContiguousArray<Int>) {
        self.indices = indices
    }

    @inlinable
    internal func push(_ index: Int) {
        indices.append(index)
    }

    @inlinable
    internal func next() -> Int? {
        guard position < indices.endIndex else {
            return nil
        }
        defer { position += 1 }
        return indices[position]
    }
}

/// Dictionary key using UnsafePointer for performance optimization.
@usableFromInline
internal struct TableKey<T: Hashable>: Hashable {
    @usableFromInline
    internal let pointeeHashValue: Int
    @usableFromInline
    internal let pointer: UnsafePointer<T>

    @usableFromInline
    internal init(pointer: UnsafePointer<T>) {
        self.pointeeHashValue = pointer.pointee.hashValue
        self.pointer = pointer
    }

    @inlinable
    internal static func == (lhs: TableKey, rhs: TableKey) -> Bool {
        return lhs.pointeeHashValue == rhs.pointeeHashValue
            && (lhs.pointer.distance(to: rhs.pointer) == 0 || lhs.pointer.pointee == rhs.pointer.pointee)
    }

    @inlinable
    internal func hash(into hasher: inout Hasher) {
        hasher.combine(pointeeHashValue)
    }
}

internal extension MutableCollection where Element: MutableCollection, Index == Int, Element.Index == Int {
    @inlinable
    subscript(path: ElementPath) -> Element.Element {
        get { return self[path.section][path.element] }
        set { self[path.section][path.element] = newValue }
    }
}


/// The shared algorithm to calculate diffs between two linear collections.
@inlinable
@discardableResult
internal func differentiate<E: Differentiable, I>(
    source: ContiguousArray<E>,
    target: ContiguousArray<E>,
    useTargetIndexForUpdated: Bool,
    mapIndex: (Int) -> I,
    updatedElementsPointer: UnsafeMutablePointer<ContiguousArray<E>>? = nil,
    notDeletedElementsPointer: UnsafeMutablePointer<ContiguousArray<E>>? = nil
    ) -> DifferentiateResult<I> {
    var deleted = [I]()
    var inserted = [I]()
    var updated = [I]()
    var moved = [(source: I, target: I)]()

    var sourceTraces = ContiguousArray<Trace<Int>>()
    var sourceIdentifiers = ContiguousArray<String>()
    var targetReferences = ContiguousArray<Int?>(repeating: nil, count: target.count)

    sourceTraces.reserveCapacity(source.count)
    sourceIdentifiers.reserveCapacity(source.count)

    for sourceElement in source {
        sourceTraces.append(Trace())
        sourceIdentifiers.append(sourceElement.differenceIdentifier)
    }

    sourceIdentifiers.withUnsafeBufferPointer { bufferPointer in
        // The pointer and the table key are for optimization.
        var sourceOccurrencesTable = [TableKey<String>: Occurrence](minimumCapacity: source.count)

        // Track indices of elements found in source collection into occurrences table.
        for sourceIndex in sourceIdentifiers.indices {
            let pointer = bufferPointer.baseAddress!.advanced(by: sourceIndex)
            let key = TableKey(pointer: pointer)

            switch sourceOccurrencesTable[key] {
            case .none:
                sourceOccurrencesTable[key] = .unique(index: sourceIndex)

            case .unique(let otherIndex)?:
                let reference = IndicesReference([otherIndex, sourceIndex])
                sourceOccurrencesTable[key] = .duplicate(reference: reference)

            case .duplicate(let reference)?:
                reference.push(sourceIndex)
            }
        }

        // Track target and source indices of the elements having same identifier.
        for targetIndex in target.indices {
            var targetIdentifier = target[targetIndex].differenceIdentifier
            let key = TableKey(pointer: &targetIdentifier)

            switch sourceOccurrencesTable[key] {
            case .none:
                break

            case .unique(let sourceIndex)?:
                if case .none = sourceTraces[sourceIndex].reference {
                    targetReferences[targetIndex] = sourceIndex
                    sourceTraces[sourceIndex].reference = targetIndex
                }

            case .duplicate(let reference)?:
                if let sourceIndex = reference.next() {
                    targetReferences[targetIndex] = sourceIndex
                    sourceTraces[sourceIndex].reference = targetIndex
                }
            }
        }
    }

    var offsetByDelete = 0
    var untrackedSourceIndex: Int? = 0

    // Track deletes.
    for sourceIndex in source.indices {
        sourceTraces[sourceIndex].deleteOffset = offsetByDelete

        if let targetIndex = sourceTraces[sourceIndex].reference {
            let targetElement = target[targetIndex]
            updatedElementsPointer?.pointee.append(targetElement)
            notDeletedElementsPointer?.pointee.append(targetElement)
        }
        else {
            let sourceElement = source[sourceIndex]
            deleted.append(mapIndex(sourceIndex))
            sourceTraces[sourceIndex].isTracked = true
            offsetByDelete += 1
            updatedElementsPointer?.pointee.append(sourceElement)
        }
    }

    // Track updates / moves / inserts.
    for targetIndex in target.indices {
        untrackedSourceIndex = untrackedSourceIndex.flatMap { index in
            sourceTraces.suffix(from: index).firstIndex { !$0.isTracked }
        }

        if let sourceIndex = targetReferences[targetIndex] {
            sourceTraces[sourceIndex].isTracked = true

            let sourceElement = source[sourceIndex]
            let targetElement = target[targetIndex]

            if !targetElement.isContentEqual(to: sourceElement) {
                updated.append(mapIndex(useTargetIndexForUpdated ? targetIndex : sourceIndex))
            }

            if sourceIndex != untrackedSourceIndex {
                let deleteOffset = sourceTraces[sourceIndex].deleteOffset
                moved.append((source: mapIndex(sourceIndex - deleteOffset), target: mapIndex(targetIndex)))
            }
        }
        else {
            inserted.append(mapIndex(targetIndex))
        }
    }

    return DifferentiateResult(
        deleted: deleted,
        inserted: inserted,
        updated: updated,
        moved: moved,
        sourceTraces: sourceTraces,
        targetReferences: targetReferences
    )
}
