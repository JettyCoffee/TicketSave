import SwiftUI
import MapKit
import SwiftData

struct JourneyMapView: View {
    @Query(sort: \Ticket.departureTime, order: .reverse) private var tickets: [Ticket]
    @State private var selectedCity: String?
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    private var visitedCities: [CityVisit] {
        let db = StationDatabase.shared
        var cityMap: [String: CityVisit] = [:]

        for ticket in tickets {
            for stationName in [ticket.departureStation, ticket.arrivalStation] {
                guard let info = db.lookup(stationName) else { continue }
                let city = info.city
                if var visit = cityMap[city] {
                    visit.count += 1
                    if ticket.departureTime < visit.firstVisit {
                        visit.firstVisit = ticket.departureTime
                    }
                    if ticket.departureTime > visit.lastVisit {
                        visit.lastVisit = ticket.departureTime
                    }
                    visit.stations.insert(stationName)
                    cityMap[city] = visit
                } else {
                    cityMap[city] = CityVisit(
                        city: city,
                        province: info.province,
                        coordinate: info.coordinate,
                        count: 1,
                        firstVisit: ticket.departureTime,
                        lastVisit: ticket.departureTime,
                        stations: [stationName]
                    )
                }
            }
        }
        return Array(cityMap.values).sorted { $0.count > $1.count }
    }

    private var routeLines: [(CLLocationCoordinate2D, CLLocationCoordinate2D, Color)] {
        let db = StationDatabase.shared
        var lines: [(CLLocationCoordinate2D, CLLocationCoordinate2D, Color)] = []
        for ticket in tickets {
            if let dep = db.coordinate(for: ticket.departureStation),
               let arr = db.coordinate(for: ticket.arrivalStation) {
                lines.append((dep, arr, ticket.trainTypeColor))
            }
        }
        return lines
    }

    private var visitedProvinces: Int {
        Set(visitedCities.map(\.province)).count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 地图
                Map(position: $mapCameraPosition) {
                    // 路线
                    ForEach(Array(routeLines.enumerated()), id: \.offset) { _, line in
                        MapPolyline(coordinates: [line.0, line.1])
                            .stroke(line.2.opacity(0.5), lineWidth: 2)
                    }

                    // 城市标记
                    ForEach(visitedCities, id: \.city) { visit in
                        Annotation(visit.city, coordinate: visit.coordinate) {
                            CityAnnotationView(visit: visit, isSelected: selectedCity == visit.city)
                                .onTapGesture {
                                    withAnimation {
                                        selectedCity = selectedCity == visit.city ? nil : visit.city
                                    }
                                }
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))

                // 底部卡片
                VStack(spacing: 0) {
                    // 统计条
                    statsBar

                    // 选中城市的详情
                    if let cityName = selectedCity,
                       let visit = visitedCities.first(where: { $0.city == cityName }) {
                        selectedCityCard(visit)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .navigationTitle("人生足迹")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation {
                                mapCameraPosition = .automatic
                            }
                        } label: {
                            Label("查看全部", systemImage: "map")
                        }
                        Button {
                            withAnimation {
                                mapCameraPosition = .region(MKCoordinateRegion(
                                    center: CLLocationCoordinate2D(latitude: 35.0, longitude: 105.0),
                                    span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40)
                                ))
                            }
                        } label: {
                            Label("全国视图", systemImage: "globe.asia.australia")
                        }
                    } label: {
                        Image(systemName: "map.circle")
                    }
                }
            }
        }
    }

    // MARK: - Stats Bar
    private var statsBar: some View {
        HStack(spacing: 24) {
            Label("\(visitedCities.count) 城市", systemImage: "building.2.fill")
            Label("\(visitedProvinces) 省份", systemImage: "map.fill")
            Label("\(tickets.count) 行程", systemImage: "train.side.front.car")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - City Card
    private func selectedCityCard(_ visit: CityVisit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(visit.city)
                        .font(.system(size: 20, weight: .bold))
                    Text(visit.province)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(visit.count)次")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Text("途经")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("首次到访")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(visit.firstVisit, style: .date)
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("最近到访")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(visit.lastVisit, style: .date)
                        .font(.system(size: 13, weight: .medium))
                }
            }

            // 途经车站
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(visit.stations).sorted(), id: \.self) { station in
                        Text(station)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

// MARK: - City Visit Model
struct CityVisit {
    let city: String
    let province: String
    let coordinate: CLLocationCoordinate2D
    var count: Int
    var firstVisit: Date
    var lastVisit: Date
    var stations: Set<String>
}

// MARK: - City Annotation View
struct CityAnnotationView: View {
    let visit: CityVisit
    let isSelected: Bool

    private var size: CGFloat {
        let base: CGFloat = 28
        let extra = min(CGFloat(visit.count - 1) * 3, 18)
        return base + extra
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.05)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size
                    )
                )
                .frame(width: size * 2, height: size * 2)

            Circle()
                .fill(.blue.gradient)
                .frame(width: size, height: size)
                .overlay {
                    if visit.count > 1 {
                        Text("\(visit.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: .blue.opacity(0.3), radius: 4, y: 2)

            if isSelected {
                Circle()
                    .stroke(.blue, lineWidth: 2)
                    .frame(width: size + 6, height: size + 6)
            }
        }
    }
}

#Preview {
    JourneyMapView()
        .modelContainer(for: Ticket.self, inMemory: true)
}
