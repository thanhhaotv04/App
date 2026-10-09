<p align="center"><img src="App/web/icons/Icon-512.png" width="112" alt="Biểu tượng ESP32-NavRide"></p>

# ESP32-NavRide

**Nhìn hướng rẽ mà không cần nhìn bản đồ trên điện thoại.** OsmAnd chỉ đường, app ESP32-NavRide chuyển mũi tên, tên đường, khoảng cách và tốc độ GPS lên màn hình ESP32-S3 1,8 inch.

Điện thoại kết nối ESP32 bằng **Bluetooth** (dẫn đường không cần Wi-Fi) hoặc **Wi-Fi**. App còn gửi thông báo, việc cần làm; màn hình có đồng hồ, bấm giờ và hẹn giờ.

## Hình ảnh

| 1. OsmAnd và ESP32 đã kết nối | 2. Chọn Bluetooth hoặc Wi-Fi |
| --- | --- |
| <img src="docs/images/01-navigation.jpg" width="260" alt="App báo OsmAnd và màn hình ESP32 đã sẵn sàng"> | <img src="docs/images/02-connection.jpg" width="260" alt="Cài đặt kết nối Bluetooth và Wi-Fi"> |

| 3. Tạo thông báo trong app | 4. OsmAnd dẫn đường |
| --- | --- |
| <img src="docs/images/03-content.jpg" width="260" alt="Màn hình thông báo và việc cần làm"> | <img src="docs/images/04-osmand.jpg" width="260" alt="Tuyến đường và hướng rẽ trong OsmAnd"> |

| 5. Hướng rẽ trên ESP32 | 6. Menu trên ESP32 |
| --- | --- |
| <img src="docs/images/05-display.jpg" width="260" alt="Màn hình ESP32 hiển thị hướng rẽ, tên đường và khoảng cách"> | <img src="docs/images/06-menu.jpg" width="260" alt="Menu Wi-Fi, Bluetooth, chủ đề, thông tin ESP32, QR và đồng hồ"> |

**7. Fleet management — đang phát triển.** Khi bạn chủ động bắt đầu chuyến đi, app lưu các điểm GPS và đồng bộ với Firebase khi có mạng. Thông báo cá nhân và chỉ dẫn OsmAnd không được đưa lên Fleet.

<img src="docs/images/07-fleet.png" width="260" alt="Giao diện Fleet tracking trong app, đã che email tài khoản">

Firebase đã kết nối và đã thử đồng bộ điểm ghi khi mất mạng. [Xem lịch sử chuyến đi trên dashboard](https://navride-96851.web.app) (cần tài khoản được cấp quyền).

## Bắt đầu

- **App Android:** mã nguồn và cách cài/build APK ở [App/](App/README.md). APK cũ trong repo thuộc package ID cũ; để dùng Firebase, hãy build app hiện tại theo hướng dẫn.
- **Firmware ESP32-S3:** mã nguồn, sơ đồ dây và cách nạp bằng PlatformIO ở [Firmware/](Firmware/README.md).
- **OsmAnd:** cài trên điện thoại, tải bản đồ, bật tích hợp ESP32-NavRide rồi bắt đầu dẫn đường. [Các bước kết nối](App/README.md).

Chỉ dùng màn hình phụ khi điều khiển xe an toàn; hãy thiết lập app và ESP32 khi xe đã dừng.
