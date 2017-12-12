//
//  Path.swift
//  ArcKit
//
//  Created by Matt Greenfield on 2/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Upsurge
import CoreLocation

@objc public class Path: TimelineItem {

    // valid path settings
    @objc static var minimumValidDuration: TimeInterval = 10
    @objc static var minimumValidDistance: Double = 10
    @objc static var minimumValidSamples = 2

    // keeper path settings
    @objc static var minimumKeeperDuration: TimeInterval = 60
    @objc static var minimumKeeperDistance: Double = 20

    private var _distance: CLLocationDistance?

    public override var isValid: Bool {
        if samples.count < Path.minimumValidSamples {
            return false
        }

        if duration < Path.minimumValidDuration {
            return false
        }

        if distance < Path.minimumValidDistance {
            return false
        }

        return true
    }

    @objc public override var isWorthKeeping: Bool {
        if !isValid {
            return false
        }
        if duration < Path.minimumKeeperDuration {
            return false
        }
        if distance < Path.minimumKeeperDistance {
            return false
        }
        return true
    }

    /// The distance of the path, as the sum of the distances between each sample.
    @objc public var distance: CLLocationDistance {
        if let distance = _distance {
            return distance
        }
        let distance = samples.distance
        _distance = distance
        return distance
    }

    public var speed: CLLocationSpeed {
        return metresPerSecond
    }

    public var mps: CLLocationSpeed {
        return metresPerSecond
    }

    public var metresPerSecond: CLLocationSpeed {
        if samples.count == 1, let sampleSpeed = samples.first?.location?.speed, sampleSpeed >= 0 {
            return sampleSpeed
        }
        if duration > 0 {
            return distance / duration
        }
        return 0
    }

    public var kph: Double {
        return kilometresPerHour
    }

    public var kmh: Double {
        return kilometresPerHour
    }

    public var kilometresPerHour: Double {
        return mps * 3.6
    }

    public var mph: Double {
        return milesPerHour
    }

    public var milesPerHour: Double {
        return kilometresPerHour / 1.609344
    }

    public override func distance(from otherItem: TimelineItem) -> CLLocationDistance? {
        if let path = otherItem as? Path {
            return distance(from: path)
        }
        if let visit = otherItem as? Visit {
            return distance(from: visit)
        }
        return nil
    }

    internal func distance(from visit: Visit) -> CLLocationDistance? {
        return visit.distance(from: self)
    }
    
    internal func distance(from otherPath: Path) -> CLLocationDistance? {
        guard let myStart = start, let theirStart = otherPath.start else {
            return nil
        }
        if myStart < theirStart {
            if let myEdge = samples.last, let theirEdge = otherPath.samples.first {
                return myEdge.distance(from: theirEdge)
            }
        } else {
            if let myEdge = samples.first, let theirEdge = otherPath.samples.last {
                return myEdge.distance(from: theirEdge)
            }
        }
        return nil
    }
    
    public func samplesInside(_ visit: Visit) -> Set<LocomotionSample> {
        guard let visitCenter = visit.center else {
            return []
        }
        var insiders: Set<LocomotionSample> = []
        for sample in samples {
            guard let sampleLocation = sample.location else {
                continue
            }
            let metresFromCentre = visitCenter.distance(from: sampleLocation)
            if metresFromCentre <= visit.radius2sd {
                insiders.insert(sample)
            }
        }
        return insiders
    }

    public func samplesOutside(_ visit: Visit) -> Set<LocomotionSample> {
        return Set(samples).subtracting(samplesInside(visit))
    }

    /// The percentage of the path's distance, duration, and sample count that is contained inside the given visit.
    public func percentInside(_ visit: Visit) -> Double {
        return visit.containedPercentOf(self)
    }

    public override func maximumMergeableDistance(from otherItem: TimelineItem) -> CLLocationDistance {
        if let path = otherItem as? Path {
            return maximumMergeableDistance(from: path)
        }
        if let visit = otherItem as? Visit {
            return maximumMergeableDistance(from: visit)
        }
        return 0
    }

    private func maximumMergeableDistance(from visit: Visit) -> CLLocationDistance {
        return visit.maximumMergeableDistance(from: self)
    }

    private func maximumMergeableDistance(from otherPath: Path) -> CLLocationDistance {
        guard let timeSeparation = self.timeIntervalFrom(otherPath) else {
            return 0
        }
        var speeds: [CLLocationSpeed] = []
        if self.mps > 0 {
            speeds.append(self.mps)
        }
        if otherPath.mps > 0 {
            speeds.append(otherPath.mps)
        }
        return CLLocationDistance(mean(speeds) * timeSeparation * 4)
    }

    internal override func cleanseEdge(with otherPath: Path) -> LocomotionSample? {
        if otherPath.samples.isEmpty {
            return nil
        }

        // fail out if separation distance is too much
        guard withinMergeableDistance(from: otherPath) else {
            return nil
        }

        // get the activity types
        guard let myActivityType = movingActivityType, let theirActivityType = otherPath.movingActivityType else {
            return nil
        }

        // can't path-path cleanse two paths of same type
        if myActivityType == theirActivityType {
            return nil
        }

        // get the edges
        guard let myEdge = self.edgeSample(with: otherPath), let theirEdge = otherPath.edgeSample(with: self) else {
            return nil
        }
        guard myEdge.hasUsableCoordinate, theirEdge.hasUsableCoordinate else {
            return nil
        }
        guard let myEdgeLocation = myEdge.location, let theirEdgeLocation = theirEdge.location else {
            return nil
        }

        let modeShiftSpeed = TimelineManager.highlander.maximumModeShiftSpeed
        let mySpeedIsSlow = myEdgeLocation.speed < modeShiftSpeed
        let theirSpeedIsSlow = theirEdgeLocation.speed < modeShiftSpeed

        // are the edges on opposite sides of the mode change speed boundary?
        if mySpeedIsSlow != theirSpeedIsSlow {
            NotificationCenter.default.post(Notification(name: .debugInfo, object: TimelineManager.highlander,
                                                         userInfo: ["info": "edges are opposite sides of the mode shift boundary"]))
            return nil
        }
        
        // is their edge my activity type?
        if theirEdge.activityType == myActivityType {
            self.add(theirEdge)
            NotificationCenter.default.post(Notification(name: .debugInfo, object: TimelineManager.highlander,
                                                         userInfo: ["info": "moved path edge (\(theirActivityType)) to adjacent path"]))
            return theirEdge
        }

        return nil
    }

    override func samplesChanged() {
        super.samplesChanged()
        _distance = nil
    }
}

extension Path {

    public override var description: String {
        return String(format: "%@ path", isWorthKeeping ? "keeper" : isValid ? "valid" : "invalid")
    }

}

