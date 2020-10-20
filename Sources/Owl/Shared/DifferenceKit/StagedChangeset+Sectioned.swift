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

public extension StagedChangeset where Collection: RangeReplaceableCollection, Collection.Element: DifferentiableSection {
    @inlinable
    init(source: Collection, target: Collection) {
        typealias Section = Collection.Element
        typealias SectionIdentifier = String
        typealias Element = ElementRepresentable
        typealias ElementIdentifier = String

        let sourceSections = ContiguousArray(source)
        let targetSections = ContiguousArray(target)

        let contiguousSourceSections = ContiguousArray(sourceSections.map { ContiguousArray($0.elements) })
        let contiguousTargetSections = ContiguousArray(targetSections.map { ContiguousArray($0.elements) })

        var firstStageSections = sourceSections
        var secondStageSections = ContiguousArray<Section>()
        var thirdStageSections = ContiguousArray<Section>()
        var fourthStageSections = ContiguousArray<Section>()

        var sourceElementTraces = contiguousSourceSections.map { section in
            ContiguousArray(repeating: Trace<ElementPath>(), count: section.count)
        }
        var targetElementReferences = contiguousTargetSections.map { section in
            ContiguousArray<ElementPath?>(repeating: nil, count: section.count)
        }

        let flattenSourceCount = contiguousSourceSections.reduce(into: 0) { $0 += $1.count }
        var flattenSourceIdentifiers = ContiguousArray<ElementIdentifier>()
        var flattenSourceElementPaths = ContiguousArray<ElementPath>()

        thirdStageSections.reserveCapacity(contiguousTargetSections.count)
        fourthStageSections.reserveCapacity(contiguousTargetSections.count)

        flattenSourceIdentifiers.reserveCapacity(flattenSourceCount)
        flattenSourceElementPaths.reserveCapacity(flattenSourceCount)

        // Calculate section differences.

        let sectionResult = differentiate(
            source: sourceSections,
            target: targetSections,
            useTargetIndexForUpdated: true,
            mapIndex: { $0 }
        )

        // Calculate element differences.

        var elementDeleted = [ElementPath]()
        var elementInserted = [ElementPath]()
        var elementUpdated = [ElementPath]()
        var elementMoved = [(source: ElementPath, target: ElementPath)]()

        for sourceSectionIndex in contiguousSourceSections.indices {
            for sourceElementIndex in contiguousSourceSections[sourceSectionIndex].indices {
                let sourceElementPath = ElementPath(element: sourceElementIndex, section: sourceSectionIndex)
                let sourceElement = contiguousSourceSections[sourceElementPath]
                flattenSourceIdentifiers.append(sourceElement.differenceIdentifier)
                flattenSourceElementPaths.append(sourceElementPath)
            }
        }

        flattenSourceIdentifiers.withUnsafeBufferPointer { bufferPointer in
            // The pointer and the table key are for optimization.
            var sourceOccurrencesTable = [TableKey<ElementIdentifier>: Occurrence](minimumCapacity: flattenSourceCount)

            // Track indices of elements found in flatten source collection into occurrences table.
            for flattenSourceIndex in flattenSourceIdentifiers.indices {
                let pointer = bufferPointer.baseAddress!.advanced(by: flattenSourceIndex)
                let key = TableKey(pointer: pointer)

                switch sourceOccurrencesTable[key] {
                case .none:
                    sourceOccurrencesTable[key] = .unique(index: flattenSourceIndex)

                case .unique(let otherIndex)?:
                    let reference = IndicesReference([otherIndex, flattenSourceIndex])
                    sourceOccurrencesTable[key] = .duplicate(reference: reference)

                case .duplicate(let reference)?:
                    reference.push(flattenSourceIndex)
                }
            }

            // Track target and source indices of the elements having same identifier.
            for targetSectionIndex in contiguousTargetSections.indices {
                let targetElements = contiguousTargetSections[targetSectionIndex]

                for targetElementIndex in targetElements.indices {
                    var targetIdentifier = targetElements[targetElementIndex].differenceIdentifier
                    let key = TableKey(pointer: &targetIdentifier)

                    switch sourceOccurrencesTable[key] {
                    case .none:
                        break

                    case .unique(let flattenSourceIndex)?:
                        let sourceElementPath = flattenSourceElementPaths[flattenSourceIndex]
                        let targetElementPath = ElementPath(element: targetElementIndex, section: targetSectionIndex)

                        if case .none = sourceElementTraces[sourceElementPath].reference {
                            targetElementReferences[targetElementPath] = sourceElementPath
                            sourceElementTraces[sourceElementPath].reference = targetElementPath
                        }

                    case .duplicate(let reference)?:
                        if let flattenSourceIndex = reference.next() {
                            let sourceElementPath = flattenSourceElementPaths[flattenSourceIndex]
                            let targetElementPath = ElementPath(element: targetElementIndex, section: targetSectionIndex)
                            targetElementReferences[targetElementPath] = sourceElementPath
                            sourceElementTraces[sourceElementPath].reference = targetElementPath
                        }
                    }
                }
            }
        }

        // Track element deletes.
        for sourceSectionIndex in contiguousSourceSections.indices {
            let sourceSection = sourceSections[sourceSectionIndex]
            let sourceElements = contiguousSourceSections[sourceSectionIndex]
            var firstStageElements = sourceElements

            // Should not track element deletes in the deleted section.
            if case .some = sectionResult.sourceTraces[sourceSectionIndex].reference {
                var offsetByDelete = 0

                var secondStageElements = ContiguousArray<Element>()

                for sourceElementIndex in sourceElements.indices {
                    let sourceElementPath = ElementPath(element: sourceElementIndex, section: sourceSectionIndex)

                    sourceElementTraces[sourceElementPath].deleteOffset = offsetByDelete

                    // Track element deletes if target section is tracked as inserts.
                    if let targetElementPath = sourceElementTraces[sourceElementPath].reference,
                        case .some = sectionResult.targetReferences[targetElementPath.section] {
                        let targetElement = contiguousTargetSections[targetElementPath]
                        firstStageElements[sourceElementIndex] = targetElement
                        secondStageElements.append(targetElement)
                        continue
                    }

                    elementDeleted.append(sourceElementPath)
                    sourceElementTraces[sourceElementPath].isTracked = true
                    offsetByDelete += 1
                }

                let secondStageSection = Section(source: sourceSection, elements: secondStageElements)
                secondStageSections.append(secondStageSection)

            }

            let firstStageSection = Section(source: sourceSection, elements: firstStageElements)
            firstStageSections[sourceSectionIndex] = firstStageSection
        }

        // Track element updates / moves / inserts.
        for targetSectionIndex in contiguousTargetSections.indices {
            // Should not track element updates / moves / inserts in the inserted section.
            guard let sourceSectionIndex = sectionResult.targetReferences[targetSectionIndex] else {
                thirdStageSections.append(targetSections[targetSectionIndex])
                fourthStageSections.append(targetSections[targetSectionIndex])
                continue
            }

            var untrackedSourceIndex: Int? = 0
            let targetElements = contiguousTargetSections[targetSectionIndex]

            let sectionDeleteOffset = sectionResult.sourceTraces[sourceSectionIndex].deleteOffset

            let thirdStageSection = secondStageSections[sourceSectionIndex - sectionDeleteOffset]
            thirdStageSections.append(thirdStageSection)

            var fourthStageElements = ContiguousArray<Element>()
            fourthStageElements.reserveCapacity(targetElements.count)

            for targetElementIndex in targetElements.indices {
                untrackedSourceIndex = untrackedSourceIndex.flatMap { index in
                    sourceElementTraces[sourceSectionIndex].suffix(from: index).firstIndex { !$0.isTracked }
                }

                let targetElementPath = ElementPath(element: targetElementIndex, section: targetSectionIndex)
                let targetElement = contiguousTargetSections[targetElementPath]

                // Track element inserts if source section is tracked as deletes.
                guard let sourceElementPath = targetElementReferences[targetElementPath],
                    let movedSourceSectionIndex = sectionResult.sourceTraces[sourceElementPath.section].reference else {
                        fourthStageElements.append(targetElement)
                        elementInserted.append(targetElementPath)
                        continue
                }

                sourceElementTraces[sourceElementPath].isTracked = true

                let sourceElement = contiguousSourceSections[sourceElementPath]
                fourthStageElements.append(targetElement)

                if !targetElement.isContentEqual(to: sourceElement) {
                    elementUpdated.append(sourceElementPath)
                }

                if sourceElementPath.section != sourceSectionIndex || sourceElementPath.element != untrackedSourceIndex {
                    let deleteOffset = sourceElementTraces[sourceElementPath].deleteOffset
                    let moveSourceElementPath = ElementPath(element: sourceElementPath.element - deleteOffset, section: movedSourceSectionIndex)
                    elementMoved.append((source: moveSourceElementPath, target: targetElementPath))
                }
            }

            let fourthStageSection = Section(source: thirdStageSection, elements: fourthStageElements)
            fourthStageSections.append(fourthStageSection)
        }

        var changesets = ContiguousArray<Changeset<Collection>>()

        // The 1st stage changeset.
        // - Includes:
        //   - element updates
        if !elementUpdated.isEmpty {
            changesets.append(
                Changeset(
                    data: Collection(firstStageSections),
                    elementUpdated: elementUpdated
                )
            )
        }

        // The 2nd stage changeset.
        // - Includes:
        //   - section deletes
        //   - element deletes
        if !sectionResult.deleted.isEmpty || !elementDeleted.isEmpty {
            changesets.append(
                Changeset(
                    data: Collection(secondStageSections),
                    sectionDeleted: sectionResult.deleted,
                    elementDeleted: elementDeleted
                )
            )
        }

        // The 3rd stage changeset.
        // - Includes:
        //   - section inserts
        //   - section moves
        if !sectionResult.inserted.isEmpty || !sectionResult.moved.isEmpty {
            changesets.append(
                Changeset(
                    data: Collection(thirdStageSections),
                    sectionInserted: sectionResult.inserted,
                    sectionMoved: sectionResult.moved
                )
            )
        }

        // The 4th stage changeset.
        // - Includes:
        //   - element inserts
        //   - element moves
        if !elementInserted.isEmpty || !elementMoved.isEmpty {
            changesets.append(
                Changeset(
                    data: Collection(fourthStageSections),
                    elementInserted: elementInserted,
                    elementMoved: elementMoved
                )
            )
        }

        // The 5th stage changeset.
        // - Includes:
        //   - section updates
        if !sectionResult.updated.isEmpty {
            changesets.append(
                Changeset(
                    data: target,
                    sectionUpdated: sectionResult.updated
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
