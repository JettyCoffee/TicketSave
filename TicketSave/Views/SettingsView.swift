import SwiftUI

struct SettingsView: View {
    @State private var deepSeekAPIKey: String = ""
    @State private var saved = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("请输入 DeepSeek API Key", text: $deepSeekAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button("保存 API Key") {
                        let ok = AppSecretsStore.saveDeepSeekAPIKey(deepSeekAPIKey)
                        saved = ok
                        saveFailed = !ok
                    }
                    .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if saved {
                        Text("已保存到本机安全存储")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if saveFailed {
                        Text("保存失败，请重试")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("DeepSeek")
                } footer: {
                    Text("仅保存在本机 Keychain，不会上传到你的服务器。")
                }
            }
            .navigationTitle("设置")
            .onAppear {
                deepSeekAPIKey = AppSecretsStore.loadDeepSeekAPIKey() ?? ""
            }
        }
    }
}

#Preview {
    SettingsView()
}
