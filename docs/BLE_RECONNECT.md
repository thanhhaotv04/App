# Kết nối lại Bluetooth

Android dùng một kênh BLE nền cho nội dung, tốc độ và chỉ đường; không kết
nối qua plugin rồi ngắt để chuyển sang OsmAnd. Quyền thông báo chỉ cần cho
chỉ đường OsmAnd, không phải điều kiện để kết nối ESP32.

- Reconnect tới cùng ESP32 giữ nguyên kênh tốt hoặc phiên nhập PIN đang mở.
- Nếu lần nối cũ còn treo ở bước mở kênh, Reconnect hủy lần đó và thử mới
  ngay, không phải chờ hết watchdog trước khi tận dụng 20 giây quảng bá.
- Chọn ESP32 khác mới đóng kênh cũ và lưu thiết bị mới.
- Mở lại app thử nối thiết bị đã lưu; Disconnect vẫn ngừng tự nối.
- App hiện `Connecting…` / `Pairing…` trong khi mở kênh dữ liệu; không suy
  ra kênh đã sẵn sàng chỉ từ biểu tượng Bluetooth trên điện thoại/ESP32.
- Tự thử lại vẫn giới hạn 20 giây; hết thời gian, nhấn thả Button 2 trên
  ESP32 rồi chọn Reconnect. App không quét/tìm kiếm vô hạn trong nền.

Kiểm thử hồi quy nằm ở `NavigationBleRecoveryTest.kt` và `widget_test.dart`.
Không chạy `connectedDebugAndroidTest` trên điện thoại dùng hằng ngày: dùng
unit/widget test và kiểm tra thao tác trên bản APK cài đè, không gỡ app.

## Kết quả kiểm tra 10/10/2026

- 59 unit test Android và 60 test Flutter đạt; analyze và kiểm tra riêng tư đạt.
- Cài đè APK debug vào hồ sơ cá nhân, checksum cấu hình Flutter giữ nguyên;
  Fleet vẫn đăng nhập và Trip off. Không nạp firmware hoặc đổi PIN.
- Trên điện thoại thật: Reconnect khi kênh tốt giữ nguyên mã client GATT;
  Disconnect → Connect saved ESP32 nối lại được trong cửa sổ quảng bá.
- Mẫu Left / Nguyen Hue / 250 m nhận ACK requestId từ ESP32 và app xác nhận
  nhận mẫu. ACK không thay cho kiểm tra bằng mắt hình trên TFT.
- Ca đổi bo/PIN mới và mất sóng cưỡng bức chưa thử lại bằng phần cứng;
  các ca giữ phiên PIN, hủy lần nối treo và timeout đã có unit test.
