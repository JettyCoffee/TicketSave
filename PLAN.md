我现在需要制作一个 iOS APP（使用 iOS26 的设计语言规范）APP 的功能是收藏 12306 的车票，这包含以下几个功能：
1。APP 要可以从图库或直接扫描车票，并智能读取车票信息（最好能接入 12306 的 API 获取）
2。车票使用票价展示的方式，每张车票要有订单号，起点 终点站，车次号，时间，座位号，价格，坐席，检票口
3。APP 还应该根据导入的车票，维护一个人生足迹，用地图可视化的展示（具体效果你自己丰富完善）
4。其他你认为可以给这个 APP 加上的 feature 或者你觉得有什么可以完善的地方自行开发脑洞
5。在每次修改完后需要编译一次以保证没有 bug error


sk-0eaa23e603d04282afd25cd37ba3af0a

xcodebuild -project TicketSave.xcodeproj -scheme TicketSave -destination 'generic/platform=iOS Simulator' build

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project TicketSave.xcodeproj -scheme TicketSave -destination 'generic/platform=iOS Simulator' build