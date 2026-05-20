import Foundation

@MainActor public class Timeline {
    
    public struct EventGroup {
        public let startTime: TimeInterval
        public fileprivate(set) var endTime: TimeInterval
        var animations = [TimelineAnimation]()
        
        public var duration: TimeInterval {
            return endTime - startTime
        }
        
        public var timeInterval: ClosedRange<TimeInterval> {
            return startTime...endTime
        }
    }
    
    private struct AsyncAnimation {
        let animation: TimelineAnimation
        var currentTime: TimeInterval
    }
    
    /// The current time, which can be changed by calling `seek(to:)`.
    public private(set) var currentTime = TimeInterval(0)
    /// The time offset th be added to `currentTime` and be used as the start time for new animations.
    public private(set) var timeOffset = TimeInterval(0)
    /// The event groups.
    public private(set) var eventGroups = [EventGroup]()
    /// The current undo/redo group, or the event group that will be started when calling `beginUndoGrouping()`.
    public private(set) var currentEventGroup = 0
    /// When the `groupingLevel > 0`, timeline events can be added. To increase the grouping level, call `beginUndoGrouping()`; to decrease it, call `endUndoGrouping()`.
    public private(set) var groupingLevel = 0
    /// The current undo/redo animation.
    public private(set) var undoAnimation: (direction: TimeDirection, timeInterval: ClosedRange<TimeInterval>)?
    
    private var checkpoint = 0
    private var asyncAnimations = [AsyncAnimation]()
    private var animationQueue = [AnyHashable: [TimelineAnimation]]()
    
    public init() {
    }
    
    // MARK: - Animations
    
    /// The duration corresponds to the `endTime` of the last event group, or 0 if the timeline has no event groups.
    public var duration: TimeInterval {
        return eventGroups.last?.endTime ?? 0
    }
    
    /**
     Add the given `timeOffset` to the time offset added to the timeline's `currentTime` to determine the effective start time of new animations.
     
     When closing the current undo gorup, its end time is set to the maximum among all the animation end times or `currentTime + timeoffset`, whichever is greater, and the time offset is reset.
     */
    public func addTimeOffset(_ timeOffset: TimeInterval) {
        if timeOffset <= 0 {
            preconditionFailure("precondition failure: timeOffset > 0")
        }
        self.timeOffset += timeOffset
    }
    
    public func addAnimation(_ animation: TimelineAnimation) {
        if groupingLevel == 0 {
            preconditionFailure("precondition failure: groupingLevel > 0")
        } else if animation.startTime < currentTime {
            preconditionFailure("precondition failure: currrentTime <= animation.startTime")
        } else if animation.duration < 0 {
            preconditionFailure("precondition failure: animation.duration >= 0")
        } else if undoAnimation != nil {
            preconditionFailure("Animations may not be added during undo/redo animations.")
        }
        let index = eventGroups[currentEventGroup].animations.lastIndex(where: { $0.startTime <= animation.startTime }).map({ $0 + 1 }) ?? 0
        eventGroups[currentEventGroup].animations.insert(animation, at: index)
    }
    
    /**
     Sets `currentTime` to the given `time`.
     
     If you closed any of the recent undo groups by calling `endUndoGrouping(startAsyncAnimations:)` with an argument of `true`, intsead of calling this method you need to call `seekAsyncAnimations(by:)`.
     */
    public func seek(to time: TimeInterval) {
        switch undoAnimation {
        case nil:
            if !(0...duration).contains(time) {
                preconditionFailure("precondition failure: 0 <= time <= duration")
            }
            _seek(to: time)
        case (.backward, let timeInterval)?:
            if !timeInterval.contains(time) {
                preconditionFailure("The seeked unto time must be within the undo time interval.")
            } else if currentTime < time {
                preconditionFailure("The seeked undo time must be less than currentTime.")
            }
            _seek(to: time)
            if time <= timeInterval.lowerBound {
                undoAnimation = nil
            }
        case (.forward, let timeInterval)?:
            if !timeInterval.contains(time) {
                preconditionFailure("The seeked redo time must be within the redo time interval.")
            } else if time < currentTime {
                preconditionFailure("The seeked redo time must be greater than currentTime.")
            }
            _seek(to: time)
            if timeInterval.upperBound <= time {
                undoAnimation = nil
            }
        }
    }
    
    private func _seek(to time: TimeInterval) {
        if time < currentTime {
            for eventGroup in eventGroups.reversed() {
                guard time <= eventGroup.endTime && eventGroup.startTime < currentTime else {
                    continue
                }
                let animations = eventGroup.animations.filter({ time <= $0.endTime && $0.startTime < currentTime })
                for animation in animations.reversed() {
                    if animation.endTime <= currentTime {
                        animation.enter?(.backward)
                    }
                    animation.progress(max(0.0, (time - animation.startTime) / animation.duration))
                    if time <= animation.startTime {
                        animation.exit?(.backward)
                    }
                }
            }
        } else if currentTime < time {
            for eventGroup in eventGroups {
                guard currentTime <= eventGroup.endTime && eventGroup.startTime < time else {
                    continue
                }
                let animations = eventGroup.animations.filter({ currentTime < $0.endTime && $0.startTime <= time })
                for animation in animations {
                    if currentTime <= animation.startTime {
                        animation.enter?(.forward)
                    }
                    animation.progress(min((time - animation.startTime) / animation.duration, 1.0))
                    if animation.endTime <= time {
                        animation.exit?(.forward)
                    }
                }
            }
        }
        currentTime = time
    }
    
    /// Returns whether there are unfinished async animations that should be continued with `seekAsyncAnimations(by:)`.
    public var hasAsyncAnimations: Bool {
        return !asyncAnimations.isEmpty
    }
    
    /// Returns the progress of the last async animation.
    public var lastAsyncAnimationTime: TimeInterval? {
        return asyncAnimations.last?.currentTime
    }
    
    /// Adds an async animation that is not added to the timeline.
    public func addEphemeralAnimation(_ animation: TimelineAnimation) {
        appendAsyncAnimations([AsyncAnimation(animation: animation, currentTime: currentTime)])
    }
    
    /**
     Seek async animations started by the closing of the most recent undo groups.
     
     When `hasAsyncAnimations == false`, the animations should stop.
     */
    public func seekAsyncAnimations(by timeOffset: TimeInterval) {
        if currentTime != liveTime {
            preconditionFailure("precondition failure: currrentTime != liveTime")
        } else if timeOffset < 0 {
            preconditionFailure("precondition failure: timeOffset >= 0")
        }
        for (i, asyncAnimation) in asyncAnimations.enumerated() {
            let time = min(asyncAnimation.currentTime + timeOffset, asyncAnimation.animation.endTime)
            seekAsyncAnimation(at: i, to: time)
        }
        asyncAnimations.removeAll(where: { $0.currentTime >= $0.animation.endTime })
    }
    
    private func seekAsyncAnimation(at index: Int, to time: TimeInterval) {
        let asyncAnimation = asyncAnimations[index]
        let currentTime = asyncAnimation.currentTime
        asyncAnimations[index].currentTime = time
        let animation = asyncAnimation.animation
        let subject = animation.subject
        guard animation.startTime <= time, let index = animationQueue[subject]?.firstIndex(where: { $0 === animation }) else {
            return
        }
        if index > 0 {
            for animation in animationQueue[subject]![..<index] {
                animation.enter?(.forward)
                animation.progress(1.0)
                animation.exit?(.forward)
            }
            animationQueue[subject]!.removeFirst(index)
        }
        if currentTime <= animation.startTime {
            animation.enter?(.forward)
        }
        animation.progress(min((time - animation.startTime) / animation.duration, 1.0))
        if animation.endTime <= time {
            animation.exit?(.forward)
            animationQueue[subject]!.remove(at: animationQueue[subject]!.firstIndex(where: { $0 === animation })!)
            if animationQueue[subject]!.isEmpty {
                animationQueue.removeValue(forKey: subject)
            }
        }
    }
    
    /// Completes all async/undo/redo animations immediately.
    public func completeAllAnimations() {
        switch undoAnimation {
        case (.backward, let timeInterval)?:
            seek(to: timeInterval.lowerBound)
        case (.forward, let timeInterval)?:
            seek(to: timeInterval.upperBound)
        case nil:
            for asyncAnimation in asyncAnimations {
                let animation = asyncAnimation.animation
                if asyncAnimation.currentTime <= animation.endTime {
                    if asyncAnimation.currentTime <= animation.startTime {
                        animation.enter?(.forward)
                    }
                    animation.progress(1.0)
                    animation.exit?(.forward)
                }
            }
            animationQueue.removeAll()
            asyncAnimations.removeAll()
        }
    }
    
    /// Returns whether `currentTime == liveTime`.
    public var isLive: Bool {
        return currentTime == liveTime
    }
    
    /// The live time is the time at which the timeline will expand, which is either the start time of the current undo group or, if no redo operations are possible, the end of the timeline (which corresponds to `duration`).
    public var liveTime: TimeInterval {
        return currentEventGroup < eventGroups.count ? eventGroups[currentEventGroup].startTime : duration
    }
    
    // MARK: - Undo
    
    public func removeAllRedoActions() {
        eventGroups.removeLast(eventGroups.count - currentEventGroup)
    }
    
    /**
     Begins a new undo group at `currentTime` and increases `groupingLevel` by 1.
     
     To begin an undo group, `currentTime` must be equal to `liveTime`, which means that animations belonging to different undo groups can never intersect (unless they're being played live asynchronously).
     */
    public func beginUndoGrouping() {
        if groupingLevel > 0 {
            preconditionFailure("precondition failure: groupingLevel == 0")
        } else if currentTime != liveTime {
            preconditionFailure("precondition failure: currentTime == liveTime")
        }
        if undoAnimation != nil {
            completeAllAnimations()
        }
        removeAllRedoActions()
        groupingLevel += 1
        eventGroups.append(EventGroup(startTime: currentTime, endTime: currentTime))
    }
    
    /**
     End the current undo group by decreasing the `groupingLevel` by 1.
     
     If you added animations during the undo grouping, the `startAsyncAnimations` argument determines whether they are run sequentially or asynchronously. For sequential animations, set up a timer that calls `seek(to:)` with a time value interpolated between `currentTime` and `duration`, or until `isLive == true`; it is an error to begin another undo group before the animation completes. For asynchronous animations, `currentTime` is immediately set to `duration` to allow you to begin another undo group at any time, and you have to set up a timer that calls `seekAsyncAnimations(by:)` instead until `hasAsyncAnimations == false`. In order to be able to seek the past timeline, though, it is required that all async animations and all undo/redo animations be completed by calling `completeAllAnimations()`.
     */
    public func endUndoGrouping(startAsyncAnimations: Bool) {
        if groupingLevel == 0 {
            preconditionFailure("precondition failure: groupingLevel > 0")
        }
        groupingLevel -= 1
        eventGroups[currentEventGroup].endTime = max(eventGroups[currentEventGroup].animations.map({ $0.endTime }).max() ?? 0, currentTime + timeOffset)
        timeOffset = 0
        if startAsyncAnimations {
            appendAsyncAnimations(eventGroups[currentEventGroup].animations.map({ AsyncAnimation(animation: $0, currentTime: currentTime) }))
            currentTime = duration
        } else {
            completeAllAnimations()
        }
        currentEventGroup += 1
    }
    
    private func appendAsyncAnimations(_ animations: [AsyncAnimation]) {
        asyncAnimations.append(contentsOf: animations)
        for animation in animations {
            let animation = animation.animation
            let subject = animation.subject
            if animationQueue[subject] == nil {
                animationQueue[subject] = []
            }
            animationQueue[subject]!.insert(animation, at: animationQueue[subject]!.lastIndex(where: { $0.startTime <= animation.startTime }).map({ $0 + 1 }) ?? 0)
        }
    }
    
    /// Removes all undo and redo actions and resets `currentTime` and `duration`.
    public func removeAllActions() {
        currentTime = 0
        groupingLevel = 0
        currentEventGroup = 0
        eventGroups.removeAll()
        checkpoint = 0
    }
    
    public var canUndo: Bool {
        return currentEventGroup > 0 || groupingLevel > 0
    }
    
    /**
     If `startAnimation == false`, this method performs an instantaneous undo operation and immediately sets `currentTime` to the previous undo group's `startTime`.
     
     When performing an animated undo operation, set up a timer that calls `seek(to:)` with a time value interpolated between `upperBound` and `lowerBound` of the time interval of `currentEventGroup`. When `isLive` returns `true`, the timer should stop.
     */
    public func undo(startAnimation: Bool) {
        if !canUndo {
            preconditionFailure("precondition failure: canUndo")
        }
        if groupingLevel > 0 {
            endUndoGrouping(startAsyncAnimations: false)
        }
        completeAllAnimations()
        currentEventGroup -= 1
        if startAnimation {
            undoAnimation = (.backward, eventGroups[currentEventGroup].timeInterval)
        } else {
            seek(to: eventGroups[currentEventGroup].startTime)
        }
    }
    
    public var canRedo: Bool {
        return currentEventGroup < eventGroups.count && groupingLevel == 0
    }
    
    /**
     If `startAnimation == false`, this method performs an instantaneous redo operation and immediately sets `currentTime` to the next redo group's `endTime`.
     
     When performing an animated redo operation, set up a timer that calls `seek(to:)` with a time value interpolated between `lowerBound` and `upperBound` of the time interval of `currentEventGroup - 1`. When `isLive` returns `true`, the timer should stop.
     */
    public func redo(startAnimation: Bool) {
        if !canRedo {
            preconditionFailure("precondition failure: canRedo")
        }
        completeAllAnimations()
        if startAnimation {
            undoAnimation = (.forward, eventGroups[currentEventGroup].timeInterval)
        } else {
            seek(to: eventGroups[currentEventGroup].endTime)
        }
        currentEventGroup += 1
    }
    
    /// Returns whether the given `eventGroup` is a valid undo/redo target for `undo(to:)`.
    public func canUndo(to eventGroup: Int) -> Bool {
        return (0...eventGroups.count).contains(eventGroup)
    }
    
    /// Calls `undo()` or `redo()` until the given `eventGroup` is reached.
    public func undo(to eventGroup: Int, startAnimation: Bool) {
        if !canUndo(to: eventGroup) {
            preconditionFailure("precondition failure: 0 <= eventGroup <= eventGroups.count")
        }
        if groupingLevel > 0 {
            endUndoGrouping(startAsyncAnimations: false)
        }
        completeAllAnimations()
        if eventGroup < currentEventGroup {
            if startAnimation {
                undoAnimation = (.backward, eventGroups[eventGroup].startTime...eventGroups[currentEventGroup - 1].endTime)
            } else {
                seek(to: eventGroups[eventGroup].startTime)
            }
        } else if eventGroup > currentEventGroup {
            if startAnimation {
                undoAnimation = (.forward, eventGroups[currentEventGroup].startTime...eventGroups[eventGroup - 1].endTime)
            } else {
                seek(to: eventGroups[eventGroup - 1].endTime)
            }
        }
        currentEventGroup = eventGroup
    }
    
    /**
     Sets a checkpoint after the last modified event, closing any open undo groups.
     
     Setting a checkpoint can be useful to check if the timeline has been modified after some previous state has been persisted on disk by querying `isCheckPointOutdated`.
     */
    public func setCheckpoint() {
        if groupingLevel > 0 {
            endUndoGrouping(startAsyncAnimations: false)
        }
        checkpoint = currentEventGroup
    }
    
    /// Returns whether the timeline has been modified after setting the last checkpoint.
    public var isCheckPointOutdated: Bool {
        return checkpoint != currentEventGroup
    }
    
}

@MainActor open class TimelineAnimation { // ideally this would be a protocol, but then performance becomes very bad
    
    /// The animation id. Only useful for debugging purposes.
    public let id: String
    /// The subject the animation acts on. If multiple animations with the same subject overlap, only the latest one is executed.
    public let subject: AnyHashable
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let endTime: TimeInterval
    public let enter: ((_ direction: TimeDirection) -> Void)?
    public let progress: (_ t: Double) -> Void
    public let exit: ((_ direction: TimeDirection) -> Void)?
    
    public init(id: String, subject: AnyHashable, startTime: TimeInterval, duration: TimeInterval, enter: ((_: TimeDirection) -> Void)? = nil, progress: @escaping ((_: Double) -> Void), exit: ((_: TimeDirection) -> Void)? = nil) {
        self.id = id
        self.subject = subject
        self.startTime = startTime
        self.duration = duration
        self.endTime = startTime + duration
        self.enter = enter
        self.progress = progress
        self.exit = exit
    }
    
}

public enum TimeDirection {
    case backward
    case forward
}
