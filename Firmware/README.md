# ESP32-NavRide firmware

Firmware cho ESP32-S3 + TFT ST7735 1.8 inch 128x160. Pin TFT giữ nguyên theo
`ESP32_TFT1.8inch`:

Phiên bản hiện tại: `1.3.32`.

32 pixel trên cùng (1/5 màn hình): hàng đầu là ngày/tháng/năm
`dd/mm/yyyy`, phút của Stopwatch/Timer và trạng thái kết nối;
hàng dưới là đồng hồ `HH:MM`. Chỉ đường chiếm vùng chính; hai dòng tên đường
chiếm khoảng 2/3 chiều ngang bên trái, cột 1/3 bên phải dành cho tốc độ
và đơn vị `km/h`. Tên ngắn dùng font lớn; tên dài dùng chữ hẹp hơn nhưng vẫn
cao hai dòng (ví dụ `Nguyen Thi` / `Minh Khai`). Không còn nhãn `GPS`:
số tốc độ cao 40 px, tự chọn bề ngang nét cho 1–3 chữ số để không tràn cột.
Không hiện giới hạn tốc độ.
Chỉ vùng tốc độ thay đổi được vẽ lại. Không có dữ liệu hợp lệ hoặc mất kết nối
thì hiện `--`, không giả định xe đang đứng yên. Tốc độ hết hạn sau 5 giây
không nhận gói mới. Badge Stopwatch/Timer nằm giữa hàng trên cùng, không
chồng lên tốc độ hay tên đường. Phần chỉ đường dùng 128 pixel còn lại: biểu tượng bên
trái, khoảng cách bên phải; số lối ra nằm giữa biểu tượng vòng xuyến.
Tên đường dài tự ngắt dòng trong cột bên trái.
Tên dài đổi trang mỗi 3,5 giây; chấm báo trang nằm trên tên đường. Chỉ vùng tên
đường được cập nhật. Vòng xuyến hỗ trợ lối ra 1–6 (và số lối ra từ nguồn tối đa
99); góc mũi tên ra lấy từ
OsmAnd, không suy ra góc từ số thứ tự lối ra. Nhánh mờ là gợi ý minh họa,
không phải tọa độ từng nhánh thực tế.

### GPS speed (Android + Bluetooth)

Trong app: `Navigation → GPS speed → Start GPS speed`, cấp quyền vị trí chính
xác khi dùng app và bật Location trên điện thoại. Có thể mở OsmAnd hoặc tắt
màn hình điện thoại: foreground service tiếp tục lấy `Location.getSpeed()`,
đổi m/s sang km/h rồi gửi qua kết nối BLE đang dùng. Không cần internet/Wi-Fi,
không lưu tọa độ. `Stop GPS speed` hoặc nút Stop trong thông báo sẽ dừng GPS.
Sau khi app bị Android buộc dừng, mở app và Start lại; không tự thu vị trí
ở lần khởi động sau. Chuyển khỏi bridge Bluetooth cũng dừng dịch vụ.

Gói riêng: `{"apiVersion":1,"command":"speed","kmh":42}`; dùng `null`
khi chưa có bản đo hợp lệ. ESP32 trả `ok:speed`; giá trị ngoài 0–300, sai
kiểu hoặc thiếu trường bị từ chối. Gói tốc độ không thay thế gói chỉ đường/
cài đặt đang chờ và không phát lại bản đo cũ sau khi BLE lỗi.
Giới hạn tuổi bản đo trên điện thoại là 5 giây; speed accuracy nếu có phải
≤3 m/s. GPS có thể dao động nhẹ khi đứng yên và không thay thế đồng hồ xe.

`Test display → Speed · 42 km/h (test)` gửi mẫu 5 giây, chỉ dùng khi
đang đỗ xe và GPS speed đã dừng. Đây không phải tốc độ thực.

OsmAnd bản chuẩn có MaxSpeedWidget nội bộ nhưng API AppInfo/turnInfo đang
dùng không xuất tốc độ tối đa của đoạn đường. Màn hình không hiển thị giới hạn
tốc độ; chưa hỗ trợ cảnh báo vượt tốc độ. Không suy giới
hạn từ tốc độ xe, loại đường hay tốc độ trong mô phỏng.

| TFT | ESP32-S3 |
|---|---:|
| SCL/SCK | GPIO21 |
| SDA/MOSI | GPIO47 |
| CS | GPIO41 |
| DC | GPIO40 |
| RST | GPIO45 |
| BLK | 3V3 |

### Kiểm tra phần cứng trước khi nạp

- Cấp TFT qua `VDD → 3V3`, `GND → GND`; `BLK → 3V3`. Nút bấm nối GPIO
  với GND, firmware dùng `INPUT_PULLUP`.
- **RST của TFT nối G45, không nối G21 hoặc RST/EN của bo ESP32.** G21 là
  clock SPI. Không giữ Button 3 (GPIO0/BOOT) khi bật nguồn hoặc reset.
- Không nối thiết bị ngoài vào G35/G36/G37: ESP32-S3 N16R8 dùng các chân này
  cho Octal PSRAM. Firmware cũng giữ riêng GPIO19/20 cho USB OTG và GPIO43/44
  cho CH340 UART.
- GPIO45 là chân strapping. Trước khi dùng sơ đồ này trên bo khác, đọc
  `esptool ... flash_id` và xác nhận điện áp flash/PSRAM phù hợp. Bo được kiểm
  tra ngày 08/10/2026 có flash Quad 16 MB, PSRAM Octal 8 MB và eFuse cố định
  VDD_SPI ở 3,3 V; firmware không ghi eFuse.
- [include/hardware_pins.h](include/hardware_pins.h) là nguồn cấu hình chân.
  Build sẽ báo lỗi nếu TFT/nút dùng trùng GPIO hoặc dùng chân bộ nhớ, USB,
  UART đã dành riêng. SPI khi vẽ màn hình được đặt 10 MHz để giảm nhạy với
  dây nối; trình khởi tạo ST7735 vẫn theo thư viện Adafruit.
- Bộ đếm và vẽ TFT chạy trong `loop()`. Callback BLE chỉ xếp lệnh vào hàng
  đợi để tránh hai luồng cùng ghi SPI. Việc kiểm tra code không thay thế phép
  đo nguồn, kiểm tra dây thực tế hoặc xác nhận hình trên TFT.

Tham khảo [hướng dẫn phần cứng ESP32-S3 của Espressif](https://docs.espressif.com/projects/esp-hardware-design-guidelines/en/latest/esp32s3/schematic-checklist.html).

| Nút | ESP32-S3 | Chức năng |
|---|---:|---|
| Button 1 | GPIO38 - GND | Trong menu: mục tiếp; ngoài menu: nhấn để chuyển nhanh sang Wi-Fi đã cấu hình |
| Button 2 | GPIO39 - GND | Trong menu: chọn; ngoài menu: nhấn để ngắt BLE cũ và chờ kết nối mới |
| Button 3 | GPIO0 - GND | Nhấn ngắn: menu/quay lại; giữ ít nhất 2 giây: bật/tắt đồng hồ offline |

Nhấn ngắn Button 3 để mở menu `WiFi`, `Bluetooth`, `Theme: Light/Dark`, `ESP32 Info`, `QR`, `Clock`.
Trong menu, nhấn Button 1 để chuyển mục, Button 2 để chọn; ngoài
menu, nhấn Button 1/2 một lần để chuyển nhanh phương thức, không cần giữ nút.
Menu tự đóng sau 30 giây không thao tác, riêng trang hiển thị QR không tự đóng.
Theme được lưu qua lần khởi động sau.
Trang thông tin hiện tên thiết bị, phương thức, trạng thái, SSID, IP, RSSI và phiên bản
firmware; không hiện mật khẩu Wi-Fi. Mục `WiFi` dùng mạng đã lưu; nếu đang ở
đúng chế độ được chọn thì menu chỉ đóng, không ngắt kết nối. Hãy thao tác menu
khi xe đã dừng. **GPIO0 là chân BOOT:** không giữ Button 3 khi bật nguồn hoặc
nạp firmware.

Giữ Button 3 ít nhất 2 giây để vào/ra màn đồng hồ offline. Màn này chỉ hiện
`HH:MM` và `dd/mm/yyyy` lớn; không hiện chỉ đường, tốc độ hay trạng thái radio.
Giờ bắt đầu sát mép trên (y=2 px), ngày nằm ngay bên dưới; kích thước chữ giữ nguyên.
Khi vào, Wi-Fi được tắt và BLE ngừng quảng bá/ngắt kết nối; giờ đã đồng bộ
vẫn tiếp tục chạy bằng đồng
hồ nội bộ của ESP32 khi bo còn nguồn. Giữ Button 3 lần nữa sẽ thử kết nối lại
phương thức trước đó trong tối đa 20 giây. Bấm nhanh Button 1/2 vẫn có thể
chuyển trực tiếp sang Wi-Fi/Bluetooth và thoát màn offline. Nếu chưa từng đồng
bộ giờ sau khi bật nguồn, màn hiện `--:--` và `--/--/----`; ESP32 không có
RTC pin riêng nên không thể biết giờ đúng sau khi mất nguồn.

`QR → Bank / Profile` vẫn hoạt động ngoại tuyến. Mã cá nhân chỉ nằm trong
`include/qr_assets_private.h`, đã được Git bỏ qua. Source công khai không chứa
QR ngân hàng hoặc liên kết hồ sơ của người dùng; bản build chưa cấu hình hiện
`QR not set`. Mã cá nhân cũ trên máy này được giữ nguyên trong file private.

Để cấu hình QR của bạn, cài `qrcode`, `pillow`, `zxing-cpp` trên máy build và chạy:

```bash
python tools/generate_qr_assets.py BANK_IMAGE PROFILE_IMAGE > include/qr_assets_private.h
```

Công cụ giải mã ảnh gốc và kiểm tra lại bitmap đúng độ phân giải TFT. Không
commit file private, ảnh QR gốc hoặc firmware binary chứa QR và mật khẩu thật.
Button 1 chuyển Bank/Profile; Button 3 quay lại danh sách. Firmware không cần
thư viện QR runtime.

### Clock: Stopwatch và Timer

- `Clock → Stopwatch`: Button 2 Start/Pause/Resume, Button 1 Reset (về 0 và
  dừng), Button 3 Background để trở lại chỉ đường/đồng hồ. Trong trang này hiện
  `HH:MM:SS`; giữa hàng trên của màn chính hiện số phút đã chạy, ví dụ `S12m`
  khi chạy và `P12m` khi tạm dừng. `P0m` nghĩa là dừng trước khi đủ 1 phút.
- `Clock → Timer`: chọn 5, 15, 30, 60 phút để bắt đầu; `View timer` mở timer
  đang chạy, Button 1 Cancel, Button 2 hoặc 3 Background. Chọn một mốc mới
  sẽ thay timer đang chạy. Badge `T5m` là số phút còn lại, làm tròn lên;
  phút cuối hiện `T1m` cho đến khi hết giờ.
- `At time`: đặt giờ 24h rồi phút bằng Button 1 Increase, Button 2 Next,
  cuối cùng Button 2 Start. Giờ đã qua sẽ hẹn vào ngày mai. Cần đồng hồ đã
  được đồng bộ qua điện thoại/Wi-Fi một lần để dùng lựa chọn này; các mốc
  phút và Stopwatch hoạt động ngay cả khi chưa đồng bộ giờ.
- Stopwatch và Timer chạy đồng thời bằng thời gian đơn điệu 64 bit của ESP32,
  tiếp tục khi dẫn đường, mở menu và mất/đổi Wi-Fi/BLE. Đồng bộ NTP/giờ điện
  thoại không làm nhảy số phút. Hai badge chia sẻ giữa hàng trên cùng, tốc độ
  ở góc dưới phải; tên đường tự chọn cỡ chữ. Khi cả hai cùng hoạt động, màn
  hình luân phiên hai badge mỗi 3 giây. Đổi phút chỉ vẽ lại vùng badge.
- Hết giờ: `TIME UP`, màn đen/trắng đổi mỗi 700 ms liên tục. Nhấn rồi thả bất
  kỳ nút nào để dừng báo; lần nhấn đó không đổi chế độ Wi-Fi/BLE. Theme đã lưu
  không bị thay đổi. Stopwatch vẫn chạy trong lúc báo hết giờ.
- Bộ đếm nằm trong RAM: mất nguồn hoặc reset ESP32 sẽ xóa Stopwatch/Timer.
  Các trang Stopwatch, Timer và chỉnh giờ không tự đóng do hết thời gian menu.

Kiểm tra logic độc lập phần cứng:
`g++ -std=c++11 -Wall -Wextra -Werror tools/test_clock_timers.cpp -o /tmp/navride-clock-test && /tmp/navride-clock-test`.

Khi bo và cổng serial đã kết nối, có thể kiểm thử HTTP/BLE bằng
`python3 tools/smoke_test.py --ip <IP_ESP32> --serial <CONG_SERIAL> --pin <PIN_6_SO>`.
Script cần `bleak` và `pyserial`, sẽ gửi dữ liệu mẫu, tạm chuyển sang BLE rồi
trả về Wi-Fi; chỉ chạy khi xe đứng yên. ACK/log không thay thế việc nhìn TFT để
xác nhận hình vẽ thực tế. Nếu không tìm được BLE sau khi chuyển chế độ, nhấn
Button 1 trên ESP32 để quay lại Wi-Fi.

## Chế độ kết nối

- Lần đầu khởi động: AP `ESP32-NavRide-Setup`, mật khẩu riêng 12 ký tự hiện
  trên màn hình TFT (được lưu để dùng lại sau khi khởi động lại), IP
  `192.168.4.1`, đồng thời quảng bá BLE `ESP32-NavRide` tối đa 20 giây.
  Khi một phương thức có thiết bị kết nối, phương thức kia được tắt.
- PIN 6 số hiện ở màn setup và `Menu → ESP32 Info`. Nhập PIN trong app khi
  dùng Wi-Fi; Android sẽ hỏi cùng mã khi ghép đôi BLE. Các API HTTP (kể cả
  `GET /api/health`) yêu cầu header `X-NavRide-Pin`; sau năm lần nhập sai,
  lệnh bị khóa 60 giây. HTTP nội bộ không mã hóa, chỉ dùng trên mạng tin cậy.
  BLE yêu cầu ghép đôi được xác thực.
- Gửi Wi-Fi từ app qua `POST /api/setup` để chuyển sang Wi-Fi HTTP. BLE sẽ tắt.
- Hoặc gửi lệnh `set_mode: bluetooth` qua HTTP/setup để chuyển sang BLE. Wi-Fi
  sẽ tắt.
- Nhấn Button 1 hoặc Button 2 ngoài menu sẽ chuyển phương thức ngay, không
  reboot. Trong lúc tìm, chữ `WiFi` hoặc `BLT` ở góc phải nhấp nháy màu vàng
  tối đa 20 giây; khi kết nối thành công chữ đứng yên và chuyển xanh.
  Nếu hết 20 giây chưa kết nối, ESP32 tắt Wi-Fi hoặc ngừng quảng bá BLE, hiện
  `OFF` thay vì tiếp tục tìm. Nhấn Button 1 để thử Wi-Fi đã lưu, Button 2 để thử BLE,
  hoặc chọn WiFi trong menu để thử mạng đã lưu; sau khi kết nối đang
  hoạt động bị ngắt, ESP32 cũng chỉ thử lại trong một lượt 20 giây.
- Nhấn Button 2 ngoài menu khi BLE đang kết nối sẽ chủ động ngắt thiết bị cũ,
  quảng bá lại và ưu tiên điện thoại/cầu nối dẫn đường kết nối tiếp theo.
- Cả hai chế độ được lưu qua lần bật nguồn tiếp theo. Wi-Fi và BLE không chạy
  đồng thời sau khi setup.
- Ở lần setup đầu, AP Wi-Fi và quảng bá BLE cũng dừng sau 20 giây nếu không
  có thiết bị kết nối. Để mở lại AP setup, giữ Button 3 vào màn đồng hồ rồi
  giữ lần nữa, hoặc khởi động lại bo; không giữ GPIO0 trong lúc bật nguồn.
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
  Với OsmAnd AIDL, app gửi thêm `angle` từ `next_turn_angle` nếu snapshot có
  trường này. Vòng xuyến vẽ
  lối đi vào từ dưới, dải cong liên tục, các nhánh đã đi qua và mũi tên rời
  vòng ở góc do OsmAnd cung cấp; số lối ra nằm giữa. `roundabout` chạy ngược chiều kim đồng hồ,
  `roundabout_left` chạy thuận chiều. Nếu nguồn không có góc (ví dụ notification),
  firmware vẽ mũi tên theo chiều lưu thông trên vòng cùng số lối ra, không
  đoán hướng của đường ra. Các nhãn thao tác (`EXIT`, `SL LEFT`, `KEEP L`,
  `ONTO`...) không hiển thị để bớt rối; mã thao tác vẫn được giữ để vẽ mũi tên
  khi đến gần.
  Hướng ra chỉ chính xác khi AIDL cung cấp góc thực. App ưu tiên
  snapshot AIDL khi tuyến còn hoạt động. Các nét dày, tương phản cao và nằm
  trong vùng vẽ cục bộ để nhấp nháy mà không chớp cả màn hình.
- Hướng dẫn OsmAnd BLE nhận thêm tên đường từ thông báo khi có, giữ màn dẫn
  đường cố định và hiển thị mũi tên, tên đường, khoảng cách. Thông báo mới
  hiện thành dải nhỏ ba giây khi đang dẫn đường; trong menu thì được hoãn tới
  khi thoát menu. Thay đổi trạng thái BLE không che mất chỉ dẫn. Khi chỉ
  khoảng cách thay đổi, màn hình chỉ vẽ lại vùng số.
- Với một lượt rẽ đã biết: từ 2 km trở lên hiện mũi tên đi thẳng, số km còn
  lại và tên đường sẽ rẽ vào; dưới 2 km chuyển sang mũi tên rẽ, chỉ dưới 200 m
  mũi tên rẽ mới nhấp nháy mỗi 500 ms. Dưới 1 km khoảng cách hiện bằng mét
  (ví dụ `999 m`; đúng `1 km` trở lên hiện `1.00 km`). Chỉ vùng mũi tên được vẽ lại khi nhấp
  nháy. Nếu OsmAnd báo `straight` thay vì một lượt rẽ, firmware không tự
  suy đoán lượt rẽ kế tiếp hoặc tên đường chưa được API cung cấp.
- Lệnh dẫn đường tùy chọn `requestId` (số dương); trạng thái BLE phản hồi
  `ok:navigation:<requestId>` sau khi đã xử lý, để app phân biệt xếp hàng gửi
  với ESP32 đã nhận. Lệnh cũ không có `requestId` vẫn nhận `ok:navigation`.

## Build

```bash
pio run
pio run -t upload --upload-port /dev/ttyACM0
```

Firmware có HTTP `GET /api/health`, `POST /api/setup`, `POST /api/command` và
BLE nhận cùng JSON command contract. Các lệnh chính là `push_notification`,
`push_task`, `navigation`, `clear_popup`, `clear_navigation`, `configure_wifi`,
`set_mode`; `clear_popup` không xóa tuyến, còn `clear_navigation` xóa tuyến.
App tự gửi
timestamp để đồng hồ vẫn chạy khi dùng BLE. Múi giờ luôn là Việt Nam UTC+7,
kể cả khi Wi-Fi tắt. Lệnh HTTP sai trả về 400; dẫn đường
hiện mũi tên và khoảng cách trong vùng dưới đồng hồ. Log chạy qua cổng USB
native `/dev/ttyACM0` (115200 baud).
