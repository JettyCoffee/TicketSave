import Foundation
import SwiftData

final class TrainScheduleRepository {
    private let service = GaotieScheduleService()

    func getOrFetch(trainCode: String, trainDate: Date, modelContext: ModelContext) async throws -> TrainScheduleCache {
        let dateKey = TicketOCRMapper.departureDateKey(trainDate)

        let descriptor = FetchDescriptor<TrainScheduleCache>(
            predicate: #Predicate<TrainScheduleCache> {
                $0.trainCode == trainCode && $0.trainDate == dateKey
            }
        )

        if let cached = try modelContext.fetch(descriptor).first {
            return cached
        }

        let remote = try await service.fetchSchedule(trainCode: trainCode)
        let cache = TrainScheduleCache(
            trainCode: trainCode,
            trainNo: trainCode,
            trainDate: dateKey,
            startStation: remote.startStation,
            endStation: remote.endStation,
            stopsJSON: TrainScheduleCache.encodeStops(remote.stops),
            cachedAt: .now
        )

        modelContext.insert(cache)
        try modelContext.save()
        return cache
    }

    func inferArrivalTime(
        schedule: TrainScheduleCache,
        departureStation: String,
        arrivalStation: String,
        departureDateTime: Date
    ) -> Date? {
        let stops = schedule.stops
        guard let depIndex = stops.firstIndex(where: { normalize($0.stationName) == normalize(departureStation) }),
              let arrIndex = stops.firstIndex(where: { normalize($0.stationName) == normalize(arrivalStation) }),
              arrIndex > depIndex else {
            return nil
        }

        let depStop = stops[depIndex]
        let arrStop = stops[arrIndex]

        let departureTimeString = depStop.startTime ?? depStop.arriveTime
        guard let depClock = departureTimeString,
              let arrClock = arrStop.arriveTime else {
            return nil
        }

        guard let depClockDate = parseClock(depClock),
              let arrClockDate = parseClock(arrClock) else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: departureDateTime)

        var depDayShift = depStop.arriveDayDiff
        var arrDayShift = arrStop.arriveDayDiff
        if arrDayShift < depDayShift {
            arrDayShift = depDayShift
        }

        let depComponents = calendar.dateComponents([.hour, .minute], from: depClockDate)
        let arrComponents = calendar.dateComponents([.hour, .minute], from: arrClockDate)

        var depDateComps = calendar.dateComponents([.year, .month, .day], from: dayStart)
        depDateComps.hour = depComponents.hour
        depDateComps.minute = depComponents.minute
        depDateComps.second = 0
        depDateComps.timeZone = TimeZone(identifier: "Asia/Shanghai")

        guard let depScheduleDate = calendar.date(from: depDateComps) else { return nil }

        let realOffsetDays = max(0, calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: departureDateTime)).day ?? 0)
        depDayShift = max(depDayShift, realOffsetDays)

        var arrDateComps = depDateComps
        arrDateComps.day = depDateComps.day.map { $0 + (arrDayShift - depDayShift) }
        arrDateComps.hour = arrComponents.hour
        arrDateComps.minute = arrComponents.minute

        guard var arrivalDate = calendar.date(from: arrDateComps) else { return nil }
        if arrivalDate <= depScheduleDate {
            arrivalDate = calendar.date(byAdding: .day, value: 1, to: arrivalDate) ?? arrivalDate
        }

        let depDelta = departureDateTime.timeIntervalSince(depScheduleDate)
        return arrivalDate.addingTimeInterval(depDelta)
    }

    private func parseClock(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.date(from: value)
    }

    private func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "")
    }
}
