import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("数据与统计") {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("旅行统计", systemImage: "chart.bar.fill")
                    }

                    NavigationLink {
                        JourneyMapView()
                    } label: {
                        Label("人生足迹", systemImage: "map.fill")
                    }
                }

                Section("OCR 方案") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前添加流程")
                            .font(.system(size: 13, weight: .semibold))
                        Text("仅使用本地 Vision OCR 识别车票，并通过 gaotie 时刻表补全到达时间与经停信息。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("我的")
        }
    }
}
