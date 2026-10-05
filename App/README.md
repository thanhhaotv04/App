# ESP32-NavRide app

Flutter app quản lý thông báo cá nhân và việc cần làm, gửi lên ESP32-NavRide
qua Wi‑Fi HTTP hoặc Bluetooth LE. Dữ liệu nội dung và cấu hình được lưu cục bộ
trên thiết bị chạy app.

## Chạy Web demo

```bash
cd /home/thanhhao/thanhhao/Github/App/ESP32-NavRide/App
flutter pub get
flutter run -d chrome
```

App có ba mục: `Navigation`, `Content`, `Settings`, dùng một nền trung tính và
không có bộ chọn màu. Web có thể thử lưu thông báo và việc cần làm khi chưa
kết nối; app không giả báo đã gửi hoặc đã kết nối ESP32. Muốn kết nối thật,
vào `Settings`, chọn `Wi-Fi` hoặc `Bluetooth`. Web Bluetooth cần HTTPS/localhost
và quyền Bluetooth của trình duyệt. Địa chỉ ESP32 chấp nhận cả `192.168.1.55`
lẫn URL đầy đủ như `http://192.168.1.55`.

Lưu nội dung hoặc đánh dấu hoàn thành chỉ cập nhật dữ liệu trên điện thoại.
Để hiện lên ESP32, mở menu của nội dung và chọn `Send to display`. Có thể xóa
và hoàn tác; việc bỏ lựa chọn màu không làm mất dữ liệu hoặc cấu hình đã lưu.
Trang Navigation ưu tiên bước cần làm tiếp theo; kiểm tra mũi tên, cập nhật app
và cấu hình mạng Wi-Fi được thu gọn, mở khi cần.

Ứng dụng tập trung vào bốn chức năng chính: chọn Wi-Fi/Bluetooth, gửi thông
báo cá nhân, quản lý việc cần làm và chuyển chỉ dẫn OsmAnd qua BLE. Android
đăng ký API dẫn đường chính thức của OsmAnd và đọc `getAppInfo().turnInfo`:
`next_turn_type`, `next_turn_distance`, `next_turn_name` thuộc cùng lượt rẽ.
Không ghép khoảng cách mới với tên đường cũ, không lấy `current_` làm đường
sắp rẽ. Nếu API không có dữ liệu mới, app dùng thông báo dẫn đường làm dự phòng.
Firmware vẽ biểu tượng vòng xuyến và quay đầu dạng tuyến đường liền nét, tương
phản cao trên TFT. Số lối ra được hiện ở giữa vòng xuyến khi OsmAnd cung cấp
ordinal. App ưu tiên góc ra thật từ snapshot OsmAnd AIDL; khi snapshot còn
hoạt động, thông báo không thay thế hình vòng xuyến bằng dữ liệu thiếu góc.
Nếu chỉ có thông báo, firmware vẫn dùng cùng kiểu hình nhưng góc mặc định 0
chưa thể diễn tả chính xác nhánh ra. Số lối ra vẫn lấy từ OsmAnd.
Phần thử dẫn đường hỗ trợ các loại hướng bên dưới và vòng xuyến lối ra 1–6
ở khoảng cách mẫu 250 m. Góc trong các mẫu chỉ để thử hình vẽ;
tuyến thật luôn dùng góc OsmAnd cung cấp, không cố định góc theo số lối ra.

Các mã hướng rẽ chính lấy từ [TurnType](https://github.com/osmandapp/OsmAnd/blob/master/OsmAnd-java/src/main/java/net/osmand/router/TurnType.java);
hình trên TFT được giản lược để vừa 58×66 px, đối chiếu với
[TurnPathHelper](https://github.com/osmandapp/OsmAnd/blob/master/OsmAnd/src/net/osmand/plus/views/TurnPathHelper.java):

| OsmAnd | Hướng trên TFT |
| --- | --- |
| C | Straight |
| TL / TSLL / TSHL / KL | Left / Slight left / Sharp left / Keep left |
| TR / TSLR / TSHR / KR | Right / Slight right / Sharp right / Keep right |
| TU / TRU | U-turn trái / U-turn phải |
| OFFR | Off route |
| RNDB / RNLB | Vòng xuyến ngược chiều / thuận chiều kim đồng hồ; hiện số lối ra |

OsmAnd còn có biểu tượng chỉ dẫn làn đường và điểm trên bản đồ; chúng không
thuộc 14 mã `TurnType` chính và API hiện tại không chuyển hình làn đường qua BLE.

Để dùng OsmAnd: chuyển ESP32 sang Bluetooth, chọn `ESP32-NavRide`, rồi bật
quyền truy cập thông báo khi app yêu cầu. Nếu quyền đã được cấp từ trước, app
tự chuyển kết nối BLE sang cầu nối OsmAnd ngay sau khi chọn ESP32, không cần
bấm `Enable navigation` thêm lần nữa.
Kiểm tra trạng thái `ESP32 display`, `OsmAnd` rồi mở `Test display` để gửi một
mũi tên mẫu. App chỉ báo nhận mẫu thành công sau khi firmware xác nhận
đúng mã lệnh. Trong OsmAnd mở `Menu → Plugins`, bật `ESP32-NavRide`
(ứng dụng bên thứ ba), quay lại NavRide một lần rồi bắt đầu dẫn đường.
Khi cầu nối được bật, thông báo và việc cần làm dùng cùng kết nối BLE Android,
không tranh kết nối với luồng OsmAnd.

Khi dừng tuyến trong OsmAnd, app kiểm tra lại trạng thái tuyến rồi xóa chỉ dẫn
trên TFT; việc cập nhật thông báo giữa tuyến không xóa nhầm mũi tên. Nếu điện
thoại mất BLE quá 15 giây, firmware cũng tự ẩn chỉ dẫn cũ để tránh hiển thị
một lượt rẽ đã hết hiệu lực.

Để hiện tên đường trên TFT:

1. Trong OsmAnd (đúng hồ sơ dẫn đường đang dùng), mở `Menu → Cấu hình hồ sơ →
   Cài đặt dẫn đường → Lời dẫn bằng giọng nói` (`Configure profile → Navigation
   settings → Voice prompts`). Chọn ngôn ngữ/giọng **TTS**, bật `Turn-by-Turn
   directions` và `Street names (TTS)`. Giọng ghi sẵn không đọc tên đường.
2. Trong Android, cho phép OsmAnd hiện thông báo dẫn đường và cấp **quyền truy
   cập thông báo** cho ESP32-NavRide khi app mở trang cài đặt quyền. Bắt đầu
   dẫn đường thực tế hoặc mô phỏng; chỉ xem trước tuyến chưa tạo chỉ dẫn.
3. Kiểm tra trạng thái OsmAnd là `Navigation source connected`, sau đó
   làm mới trạng thái cầu nối trong app và gửi mẫu `Nguyen Hue · 250 m` để
   kiểm tra riêng đường truyền BLE. Nếu mẫu có tên đường nhưng tuyến thật
   hiện `--`, dữ liệu điểm rẽ của OsmAnd chưa có tên đường. App không tự điền
   tên đường cũ. TTS là tùy chọn lời nói, không bắt buộc cho tên đường từ API.
4. Nếu quyền đã cấp nhưng dịch vụ chưa chạy, app tự thử nối lại rồi khởi động
   lại riêng component dịch vụ. Có thể bấm `Retry connection` để thử lại;
   không cần tắt/bật quyền mỗi lần vào app. Quyền được kiểm tra theo đúng
   component hiện tại, không nhầm quyền còn lưu của tên component cũ.
   Nếu Android vẫn chặn, kiểm tra quyền thông báo và cho phép app chạy nền
   trong cài đặt pin của điện thoại.

Khi cài bằng USB vào hồ sơ cá nhân, dùng
`adb install --user 0 -r build/app/outputs/flutter-apk/app-release.apk`.
Không dùng lệnh cài cho mọi user trên điện thoại có hồ sơ công việc.

Tài liệu OsmAnd: [Voice Prompts / Notifications](https://osmand.net/docs/user/navigation/guidance/voice-navigation/)
và [Navigation Settings](https://osmand.net/docs/user/navigation/guidance/navigation-settings/).
Trường API đối chiếu từ [ExternalApiHelper](https://github.com/osmandapp/OsmAnd/blob/master/OsmAnd/src/net/osmand/plus/helpers/ExternalApiHelper.java).
Sau khi build APK release, chạy `bash tool/check_osmand_release.sh` trong thư
mục App. Quy tắc R8 giữ tên lớp `ALatLon` để đọc Bundle từ ứng dụng OsmAnd;
không bỏ quy tắc này dù unit test bản debug vẫn đạt.
Trang Navigation tự làm mới trạng thái khi app đang mở: `Ready for directions` khi đã kết nối, `Sending directions` khi có dữ liệu OsmAnd và xác nhận
từ ESP32. App hiển thị đang chờ nếu chưa có xác nhận từ firmware.
Web chỉ thử giao diện và gửi lệnh thủ công; cầu nối AIDL/notification của OsmAnd
chỉ chạy trên Android. Sau khi cài APK, hãy thử hành trình thực tế khi xe đứng
yên trước khi gắn màn hình lên xe.

## Cập nhật APK trong app

Trong `Settings → App updates`, nhập URL máy chủ cập nhật riêng rồi bấm
`Check for updates`. Web dùng để xem và kiểm tra giao diện; tải/cài APK chỉ hoạt
động trên Android. Máy chủ cần cung cấp:

- `GET /api/update/latest`: JSON gồm `versionName`, `versionCode`, `apkUrl`,
  `notes`, `sizeBytes`, `sha256`.
- APK tại `/releases/<ten-file>.apk` trên cùng scheme/host/port với API.

Ví dụ metadata:

```json
{
  "versionName": "261001.4",
  "versionCode": 26100104,
  "apkUrl": "/releases/esp32-navride-261001.4.apk",
  "notes": "Connection and interface improvements.",
  "sizeBytes": 24576000,
  "sha256": "64-ky-tu-hex-viet-thuong"
}
```

App giới hạn APK 200 MB, không theo redirect, kiểm tra kích thước và SHA-256.
Trước khi mở trình cài đặt, phần Android còn xác minh đúng application ID,
phiên bản mới hơn, cùng chữ ký với app đang cài và không phải bản debug.

Backend cập nhật đã có sẵn trong `backend/` và không cần cài dependency. Bản
đã phát hành vẫn giữ tên APK và metadata cũ để không làm hỏng liên kết hoặc
SHA-256. Khi phát hành bản mới, dùng `versionCode` lớn hơn bản đang phát hành
và cùng khóa ký; không phát hành lại cùng số phiên bản. Ví dụ quy trình (thay
`<ten-phien-ban-moi>` và `<version-code-moi>` bằng giá trị đã chọn):

```bash
flutter build apk --release --build-name='<ten-phien-ban-moi>' --build-number='<version-code-moi>'
node backend/publish.js build/app/outputs/flutter-apk/app-release.apk \
  '<ten-phien-ban-moi>' '<version-code-moi>' "Bản ESP32-NavRide."
node backend/server.js
```

Điện thoại cùng Wi-Fi nhập `http://192.168.1.149:3000`. Nếu IP máy tính thay
đổi, xem IP mới bằng `ip -4 -brief address` rồi sửa URL trong app. Các bản sau
phải dùng `versionCode` lớn hơn và cùng khóa ký Android với bản đang cài.
Android application ID `com.thanhhao.esp32_monitor` được giữ nguyên để cập
nhật đè app cũ và giữ dữ liệu. Chỉ tên hiển thị, namespace mã nguồn và tên
APK mới đổi thành ESP32-NavRide. Sau khi cài bản đổi tên, Android có thể yêu
cầu bật lại quyền truy cập thông báo do tên component listener đã thay đổi.

## Giao tiếp thật

Lần đầu nối điện thoại/máy tính vào AP `ESP32-NavRide-Setup` (mật khẩu
`monitor1234`, IP `192.168.4.1`), sau đó nhập SSID/mật khẩu Wi‑Fi trong màn
`Settings`. Hoặc chọn thiết bị BLE `ESP32-NavRide`. Khi firmware đã chuyển sang
một phương thức, phương thức còn lại sẽ được tắt.

## Kiểm tra

```bash
flutter analyze
flutter test
flutter build web --release
```

## Giao diện và kiểm thử cục bộ

Nhãn, hướng dẫn và lỗi trong app/firmware dùng tiếng Anh. Tên đường, SSID và
nội dung đã lưu không bị dịch; TFT bỏ dấu tiếng Việt do giới hạn font. Bộ đọc
OsmAnd vẫn nhận cả hướng dẫn tiếng Việt lẫn tiếng Anh. Theme của màn ESP32
vẫn có Light/Dark; app chỉ dùng một giao diện trung tính.

Bố cục tham khảo cách ưu tiên chỉ dẫn của [Apple Watch Maps](https://support.apple.com/en-gb/guide/watch/apdea7480950/26/watchos/26)
và các mục điều hướng ổn định trong [Apple Tab Bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars).
Không dùng hình ảnh, font hoặc tài nguyên độc quyền của Apple.

Lệnh BLE có `requestId`, chỉ coi là thành công khi nhận ACK đúng ID. Firmware
1.3.1 bổ sung ACK cho thông báo, công việc, Wi-Fi, chuyển chế độ và `ping`;
firmware 1.3.3 cải thiện icon vòng xuyến/quay đầu. Cầu nối Android tự thử nối
lại BLE theo backoff và phát lại chỉ dẫn hiện hành sau khi kết nối trở lại.
Cần dùng firmware mới với app này. Gói BLE được kiểm tra sau khi mã hóa JSON;
chỉ phần chữ hiển thị được rút ngắn để vừa màn hình/gói tin, không cắt mật khẩu.
HTTP phải trả JSON `ok: true`, không chỉ mã HTTP 200.

Kiểm thử trình duyệt (cần Playwright, server web ở cổng 8080):

```bash
node tool/web_smoke.cjs
# Có gửi nội dung thật lên ESP32:
ESP32_IP=192.168.1.55 node tool/web_smoke.cjs
# Nếu Playwright cài tạm ngoài repo, đặt PLAYWRIGHT_MODULE tới thư mục package.
```

APK build cục bộ không tự trở thành bản cập nhật trên backend. Bản thử giữ
versionCode hiện hành có thể cài thủ công; muốn cập nhật trong app phải phát
hành bản mới với versionCode lớn hơn và metadata đã kiểm tra.
