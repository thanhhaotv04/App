# ESP32-NavRide

ESP32-NavRide là màn hình phụ cho xe máy, sử dụng ESP32-S3 N16R8 và TFT
ST7735 1.8 inch (128×160). App Android gửi chỉ dẫn từ OsmAnd qua Bluetooth LE
để hiển thị mũi tên, tên đường sắp rẽ và khoảng cách. App cũng hỗ trợ gửi tốc độ
GPS của điện thoại, thông báo cá nhân và việc cần làm.

Firmware có đồng hồ, Stopwatch, Timer, QR và chế độ chỉ hiển thị giờ.
Có thể kết nối bằng Wi-Fi hoặc Bluetooth; sau khi kết nối, chỉ một phương thức
hoạt động tại một thời điểm. Dẫn đường qua Bluetooth không cần Wi-Fi;
OsmAnd cần tải trước bản đồ nếu muốn sử dụng ngoại tuyến.

## Cấu trúc repo

| Thư mục | Nội dung |
| --- | --- |
| [Firmware/](Firmware/) | Firmware ESP32-S3, cấu hình PlatformIO và tài liệu nối dây |
| [App/](App/) | App Flutter; cầu nối OsmAnd chạy trên Android |
| [App/backend/](App/backend/) | Máy chủ tải và cập nhật APK trong app |
| [App/backend/releases/](App/backend/releases/) | APK đã phát hành và thông tin phiên bản |

## Nạp firmware bằng PlatformIO

1. Cài **VS Code** và extension **PlatformIO IDE**.
2. Mở thư mục **Firmware/** trong VS Code, nơi có [platformio.ini](Firmware/platformio.ini).
   Cấu hình hiện tại dành cho ESP32-S3 N16R8 (16 MB flash, 8 MB Octal PSRAM).
3. Nối màn hình theo [hướng dẫn firmware](Firmware/README.md).
4. Tạo file `Firmware/include/secrets.h` với nội dung sau. Có thể để trống
   SSID/mật khẩu để thiết lập kết nối từ app; file này đã được bỏ qua bởi Git.

```cpp
#pragma once

constexpr char DEFAULT_WIFI_SSID[] = "";
constexpr char DEFAULT_WIFI_PASSWORD[] = "";
```

Cắm cáp USB có truyền dữ liệu, mở terminal PlatformIO trong thư mục `Firmware/`
và chạy:

```bash
pio run
pio device list
pio run -t upload --upload-port /dev/ttyACM0
pio device monitor --port /dev/ttyACM0 --baud 115200
```

Thay `/dev/ttyACM0` bằng cổng thực tế từ `pio device list`. Trên Linux, cổng
OTG/native USB thường là `/dev/ttyACM0`, cổng TTL/CH340 thường là `/dev/ttyUSB0`;
Windows dùng `COMx`. Log của firmware hiện đi qua cổng OTG/native USB.
Cũng có thể dùng các nút **Build**, **Upload** và **Serial Monitor** của PlatformIO.

Nếu bo chưa vào chế độ nạp: giữ **BOOT**, nhấn-thả **RST**, thả **BOOT**, rồi
thử Upload lại. Sau khi nạp xong, nhấn RST để chạy firmware nếu cần.

## App và tải APK

Mã nguồn app nằm trong [App/](App/). Tải
[APK đã phát hành: ESP32-NavRide 261001.4](App/backend/releases/esp32-navride-261001.4.apk).
Trên GitHub, mở tệp rồi chọn **Download raw file** nếu trình duyệt chưa tự tải.
Chuyển APK sang điện thoại Android, mở tệp và cho phép cài ứng dụng từ nguồn
đang mở tệp khi Android yêu cầu.

APK đã phát hành có thể chưa chứa các thay đổi mới nhất trong mã nguồn.
Để tự tạo APK từ source hiện tại, cài Flutter SDK và Android SDK, rồi chạy
từ thư mục gốc repo:

```bash
cd App
flutter pub get
flutter build apk --release
```

APK tạo ra tại `App/build/app/outputs/flutter-apk/app-release.apk` (tính từ
thư mục gốc repo).

### Tải/cập nhật qua mạng nội bộ

Cài Node.js 22 trở lên và chạy từ thư mục gốc repo:

```bash
node App/backend/server.js
```

Cho điện thoại và máy tính vào cùng mạng Wi-Fi, mở địa chỉ sau trên điện thoại
để tải APK đã phát hành; thay `<IP-may-tinh>` bằng IP máy chạy backend:

```text
http://<IP-may-tinh>:3000/releases/esp32-navride-261001.4.apk
```

Nếu đã cài app, vào **Settings → App updates**, nhập
`http://<IP-may-tinh>:3000`, rồi chọn **Check for updates**. Backend phục vụ
bản trong `App/backend/releases/latest.json`; build APK riêng không tự cập nhật
bản phát hành này. Chi tiết phát hành và thiết lập OsmAnd: [App/README.md](App/README.md).

## Kết nối OsmAnd

Trên ESP32, chọn **Menu → Bluetooth** hoặc nhấn Button 2. Trong app, chọn
**Settings → Bluetooth → ESP32-NavRide**, nhập PIN trên màn hình ESP32 nếu
được hỏi và cấp quyền truy cập thông báo. Trong OsmAnd, bật tích hợp
**ESP32-NavRide** ở **Menu → Plugins**, rồi bắt đầu dẫn đường.

Để thử giao diện app trên máy tính, chạy `flutter run -d chrome` trong `App/`.
Cầu nối OsmAnd yêu cầu APK Android; bản web chỉ dùng để thử giao diện và
gửi lệnh thủ công khi có kết nối phù hợp.
