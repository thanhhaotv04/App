# ESP32-NavRide firmware

Firmware cho ESP32-S3 + TFT ST7735 1.8 inch 128x160. Pin TFT giữ nguyên theo
`/home/thanhhao/thanhhao/ESP32/ESP32_TFT1.8inch`:

Phiên bản hiện tại: `1.3.12`.

| TFT | ESP32-S3 |
|---|---:|
| SCL/SCK | GPIO21 |
| SDA/MOSI | GPIO47 |
| CS | GPIO41 |
| DC | GPIO40 |
| RST | GPIO45 |
| BLK | 3V3 |

| Nút | ESP32-S3 | Chức năng |
|---|---:|---|
| Button 1 | GPIO38 - GND | Trong menu: mục tiếp; ngoài menu: nhấn để chuyển nhanh sang Wi-Fi `SuBo` |
| Button 2 | GPIO39 - GND | Trong menu: chọn; ngoài menu: nhấn để ngắt BLE cũ và chờ kết nối mới |
| Button 3 | GPIO0 - GND | Mở/đóng menu; từ trang thông tin quay về menu |

Nhấn Button 3 để mở menu `WiFi`, `Bluetooth`, `Theme: Light/Dark`, `ESP32 Info`.
Trong menu, nhấn Button 1 để chuyển mục, Button 2 để chọn; ngoài
menu, nhấn Button 1/2 một lần để chuyển nhanh phương thức, không cần giữ nút.
Menu tự đóng sau 15 giây không thao tác. Theme được lưu qua lần khởi động sau.
Trang thông tin hiện tên thiết bị, phương thức, trạng thái, SSID, IP, RSSI và phiên bản
firmware; không hiện mật khẩu Wi-Fi. Mục `WiFi` dùng mạng đã lưu; nếu đang ở
đúng chế độ được chọn thì menu chỉ đóng, không ngắt kết nối. Hãy thao tác menu
khi xe đã dừng. **GPIO0 là chân BOOT:** không giữ Button 3 khi bật nguồn hoặc
nạp firmware.

## Chế độ kết nối

- Lần đầu khởi động: AP `ESP32-NavRide-Setup`, mật khẩu `monitor1234`, IP
  `192.168.4.1`, đồng thời quảng bá BLE `ESP32-NavRide`.
- Gửi Wi-Fi từ app qua `POST /api/setup` để chuyển sang Wi-Fi HTTP. BLE sẽ tắt.
- Hoặc gửi lệnh `set_mode: bluetooth` qua HTTP/setup để chuyển sang BLE. Wi-Fi
  sẽ tắt.
- Nhấn Button 1 hoặc Button 2 ngoài menu sẽ chuyển phương thức ngay, không
  reboot. Trong lúc chờ, chữ `WiFi` hoặc `BLT` ở góc phải nhấp nháy màu vàng; khi kết nối
  thành công chữ đứng yên và chuyển xanh.
- Nhấn Button 2 ngoài menu khi BLE đang kết nối sẽ chủ động ngắt thiết bị cũ,
  quảng bá lại và ưu tiên điện thoại/cầu nối dẫn đường kết nối tiếp theo.
- Cả hai chế độ được lưu qua lần bật nguồn tiếp theo. Wi-Fi và BLE không chạy
  đồng thời sau khi setup.
- BLE dùng service UUID `7e6d0001-5b1a-4d8f-9a2c-320001000001` và command
  characteristic `7e6d0002-5b1a-4d8f-9a2c-320001000002`.
- BLE thương lượng MTU 185 byte để nhận trọn gói JSON chỉ đường từ Android.
- App gửi tối đa 180 byte sau mã hóa JSON. Lệnh có `requestId` được xác nhận
  bằng `ok:<loại>:<requestId>`: `navigation`, `popup`, `clear`, `mode`,
  `wifi_saved`, `ping`. Lệnh cũ không có ID vẫn nhận ACK không kèm ID.
- Mọi nhãn trạng thái/menu dùng tiếng Anh; tên đường vẫn được bỏ dấu để
  phù hợp với font TFT. Lệnh `ping` kiểm tra kết nối và đồng bộ giờ, không
  tạo popup.
- Nội dung thông báo được giới hạn về bộ ký tự ASCII của font TFT; app chuyển
  tiếng Việt có dấu và dấu câu thông minh trước khi gửi. Firmware giải mã
  UTF-8, bỏ dấu tiếng Việt và lọc emoji để dữ liệu BLE/HTTP trực tiếp không
  làm vỡ font hoặc tạo khoảng trắng giữa từng byte dấu.
- Icon rẽ trái/phải có đoạn đi thẳng rồi cua 90 độ; U-turn trở về bên trái.
  Với OsmAnd AIDL, app gửi thêm `angle` từ `next_turn_angle`. Vòng xuyến vẽ
  lối đi vào từ dưới, dải cong liên tục, các nhánh đã đi qua và mũi tên rời
  vòng ở góc do OsmAnd cung cấp; số lối ra nằm giữa. `roundabout` chạy ngược chiều kim đồng hồ,
  `roundabout_left` chạy thuận chiều. Nếu nguồn chỉ có số lối ra mà thiếu góc
  (ví dụ notification), firmware chỉ vẽ vòng với mũi tên chỉ chiều lưu thông,
  không đoán một nhánh ra có thể sai. Các nét dày, tương phản cao và nằm
  trong vùng vẽ cục bộ để nhấp nháy mà không chớp cả màn hình.
- Hướng dẫn OsmAnd BLE nhận thêm tên đường từ thông báo khi có, giữ màn dẫn
  đường cố định và hiển thị mũi tên, tên đường, khoảng cách theo km. Thông báo
  mới chỉ phủ tạm 8 giây rồi trở về dẫn đường; thay đổi trạng thái BLE không
  che mất chỉ dẫn. Khi chỉ khoảng cách thay đổi, màn hình chỉ vẽ lại vùng số.
- Với một lượt rẽ đã biết: từ 2 km trở lên hiện mũi tên đi thẳng, số km còn
  lại và tên đường sẽ rẽ vào; dưới 2 km chuyển sang mũi tên rẽ, dưới 1 km
  mũi tên rẽ nhấp nháy mỗi 500 ms và khoảng cách hiện bằng mét (ví dụ `999 m`;
  đúng `1 km` trở lên hiện `1.00 km`). Chỉ vùng mũi tên được vẽ lại khi nhấp
  nháy. Nếu OsmAnd báo `straight` thay vì một lượt rẽ, firmware không tự
  suy đoán lượt rẽ kế tiếp hoặc tên đường chưa được API cung cấp.
- Lệnh dẫn đường tùy chọn `requestId` (số dương); trạng thái BLE phản hồi
  `ok:navigation:<requestId>` sau khi đã xử lý, để app phân biệt xếp hàng gửi
  với ESP32 đã nhận. Lệnh cũ không có `requestId` vẫn nhận `ok:navigation`.

## Build

```bash
/home/thanhhao/.platformio/penv/bin/pio run
/home/thanhhao/.platformio/penv/bin/pio run -t upload --upload-port /dev/ttyACM0
```

Firmware có HTTP `GET /api/health`, `POST /api/setup`, `POST /api/command` và
BLE nhận cùng JSON command contract. Các lệnh chính là `push_notification`,
`push_task`, `navigation`, `clear_popup`, `configure_wifi`, `set_mode`; app tự gửi
timestamp để đồng hồ vẫn chạy khi dùng BLE. Múi giờ luôn là Việt Nam UTC+7,
kể cả khi Wi-Fi tắt. Lệnh HTTP sai trả về 400; dẫn đường
hiện mũi tên và khoảng cách trong vùng dưới đồng hồ. Log chạy qua cổng USB
native `/dev/ttyACM0` (115200 baud).
