import SwiftUI

struct TicketCardView: View {
    let ticket: Ticket
    var compact: Bool = false

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部色条 + 车次信息
            headerBar

            // 主体内容
            VStack(spacing: 16) {
                routeSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // 底部撕票线
            tearLine
                .padding(.horizontal, 4)

            // 底部价格栏
            bottomBar
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: trainIcon)
                    .font(.system(size: 14, weight: .bold))
                Text(ticket.trainNumber)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)

            Spacer()

            Text(ticket.trainType)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Text(dateFormatter.string(from: ticket.departureTime))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(ticket.trainTypeColor.gradient)
    }

    // MARK: - Route
    private var routeSection: some View {
        HStack(alignment: .center) {
            // 出发
            VStack(spacing: 4) {
                Text(timeFormatter.string(from: ticket.departureTime))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(ticket.departureStation)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 中间箭头 + 用时
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    dashedLine
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ticket.trainTypeColor)
                    dashedLine
                }

                Text(ticket.durationText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // 到达
            VStack(spacing: 4) {
                Text(timeFormatter.string(from: ticket.arrivalTime))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(ticket.arrivalStation)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }


    // MARK: - Tear Line
    private var tearLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 20, height: 20)
                .offset(x: -10)

            GeometryReader { geo in
                Path { path in
                    let dashWidth: CGFloat = 6
                    let gapWidth: CGFloat = 4
                    var x: CGFloat = 0
                    while x < geo.size.width {
                        path.move(to: CGPoint(x: x, y: geo.size.height / 2))
                        path.addLine(to: CGPoint(x: min(x + dashWidth, geo.size.width), y: geo.size.height / 2))
                        x += dashWidth + gapWidth
                    }
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            }
            .frame(height: 20)

            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 20, height: 20)
                .offset(x: 10)
        }
        .clipped()
    }

    // MARK: - Bottom
    private var bottomBar: some View {
        HStack {
            Text("¥\(ticket.price, specifier: "%.1f")")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(ticket.seatClassColor)
            
            Spacer()
            if !ticket.formattedSeat.isEmpty {
                Text(ticket.formattedSeat)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ticket.seatClass)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(ticket.seatClassColor)

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers
    private var trainIcon: String {
        let prefix = ticket.trainNumber.prefix(1).uppercased()
        switch prefix {
        case "G", "C", "D": return "tram.fill"
        default: return "train.side.front.car"
        }
    }

    private var dashedLine: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 30, height: 1)
    }
}

#Preview {
    TicketCardView(ticket: {
        let t = Ticket(
            trainNumber: "G1234",
            departureStation: "北京南",
            arrivalStation: "上海虹桥",
            departureTime: Date(),
            arrivalTime: Date().addingTimeInterval(4.5 * 3600),
            seatNumber: "12A",
            carriageNumber: "05",
            seatClass: "二等座",
            price: 553.0
        )
        return t
    }())
    .padding()
}
