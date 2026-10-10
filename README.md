# App

Bộ sưu tập ứng dụng phục vụ quản lý cá nhân, lưu hành trình và kết nối thiết bị
ESP32. Mỗi ứng dụng được phát triển trên một **branch riêng**, với mã nguồn và
hướng dẫn sử dụng đi kèm.

Branch **`main`** là trang giới thiệu chung. Chọn ứng dụng bên dưới để xem mã
nguồn, cách cài đặt và hướng dẫn chạy dự án.

## Danh sách ứng dụng

| Biểu tượng | Ứng dụng | Giới thiệu | Branch |
| :---: | --- | --- | --- |
| <img src="https://raw.githubusercontent.com/thanhhaotv04/App/VietNam-Checking-Map/assets/App_VietNamMap_Logo_no_background.png" width="48" alt="Biểu tượng VietNam Map Checkin"> | [VietNam Map Checkin](#vietnam-map-checkin) | Lưu địa điểm đã đến, ảnh và hành trình khám phá Việt Nam. | [`VietNam-Checking-Map`](https://github.com/thanhhaotv04/App/tree/VietNam-Checking-Map) |
| <img src="https://raw.githubusercontent.com/thanhhaotv04/App/Money-Manager/docs/images/app-icon.svg" width="48" alt="Biểu tượng Money Manager"> | [Money Manager](#money-manager) | Theo dõi thu nhập, chi tiêu và các khoản chi định kỳ. | [`Money-Manager`](https://github.com/thanhhaotv04/App/tree/Money-Manager) |
| <img src="https://raw.githubusercontent.com/thanhhaotv04/App/Task-Reminder/assets/branding/app_icon.png" width="48" alt="Biểu tượng Task Reminder"> | [Task Reminder](#task-reminder) | Quản lý công việc, lịch nhắc và tiến độ hằng ngày. | [`Task-Reminder`](https://github.com/thanhhaotv04/App/tree/Task-Reminder) |
| <img src="https://raw.githubusercontent.com/thanhhaotv04/App/ESP32-NavRide/App/web/icons/Icon-512.png" width="48" alt="Biểu tượng ESP32-NavRide"> | [ESP32-NavRide](#esp32-navride) | Hiển thị chỉ dẫn đường từ điện thoại lên màn hình ESP32 cho xe máy. | [`ESP32-NavRide`](https://github.com/thanhhaotv04/App/tree/ESP32-NavRide) |

## VietNam Map Checkin

Nhật ký du lịch giúp lưu lại những nơi đã ghé thăm và theo dõi hành trình khám
phá các tỉnh, thành Việt Nam.

<p align="center"><img src="https://raw.githubusercontent.com/thanhhaotv04/App/VietNam-Checking-Map/docs/images/03-map.png" width="260" alt="Giao diện VietNam Map Checkin với bản đồ Việt Nam, ô tìm tỉnh thành và màu thể hiện số lần check-in"></p>
<p align="center"><sub>Khám phá Việt Nam qua bản đồ những nơi đã ghé thăm</sub></p>

- Lưu check-in với địa điểm, ngày giờ, ghi chú và nhiều ảnh; hỗ trợ lấy vị trí GPS.
- Quản lý album, chọn ảnh bìa, sắp xếp ảnh và chia sẻ album dưới dạng ZIP.
- Xem bản đồ, các tỉnh/thành đã đi, thống kê theo vùng và dòng thời gian chuyến đi.
- Lưu dữ liệu trên thiết bị và đồng bộ check-in, album theo tài khoản qua backend.
- Hỗ trợ backup mã hóa, chế độ riêng tư và loại bỏ metadata vị trí trong ảnh.

**Công nghệ:** Flutter, Node.js.

[Xem mã nguồn](https://github.com/thanhhaotv04/App/tree/VietNam-Checking-Map)
· [Hướng dẫn sử dụng và chạy dự án](https://github.com/thanhhaotv04/App/blob/VietNam-Checking-Map/README.md)

## Money Manager

Ứng dụng quản lý thu chi cá nhân, có thể dùng tài khoản local trên thiết bị hoặc
chọn tài khoản đồng bộ khi cần sử dụng backend.

<p align="center"><img src="https://raw.githubusercontent.com/thanhhaotv04/App/Money-Manager/docs/images/01-overview.png" width="260" alt="Giao diện Money Manager hiển thị tổng tiền, số tiền hôm nay, tháng này và thống kê từng tháng"></p>
<p align="center"><sub>Xem tổng quan các khoản đã ghi theo ngày và tháng</sub></p>

- Theo dõi thu nhập, chi tiêu và các khoản chi định kỳ.
- Dùng tài khoản local mà không cần backend hoặc kết nối Wi-Fi.
- Đồng bộ dữ liệu theo tài khoản khi chọn sử dụng máy chủ.
- Ẩn/hiện số tiền, quản lý lịch sử và hoàn tác sau khi xóa từng giao dịch.
- Hỗ trợ đổi mật khẩu và kiểm tra cập nhật APK trên Android.

**Công nghệ:** Flutter, Node.js.

[Xem mã nguồn](https://github.com/thanhhaotv04/App/tree/Money-Manager)
· [Hướng dẫn sử dụng và chạy dự án](https://github.com/thanhhaotv04/App/blob/Money-Manager/README.md)

## Task Reminder

Ứng dụng sắp xếp công việc và lịch nhắc, giúp theo dõi việc cần làm trong ngày
cũng như tiến độ theo tháng. Có thể sử dụng offline và chủ động đồng bộ khi cần.

<p align="center"><img src="https://raw.githubusercontent.com/thanhhaotv04/App/Task-Reminder/docs/images/03-work-list.png" width="260" alt="Giao diện Task Reminder ở chế độ tối với việc hôm nay, danh sách công việc và nút thêm hoặc lên lịch"></p>
<p align="center"><sub>Quản lý danh sách công việc và đưa từng việc vào lịch</sub></p>

- Tạo công việc với ghi chú, biểu tượng, mức ưu tiên và thời gian tập trung dự kiến.
- Thêm nhanh bằng câu nhập như `Nộp báo cáo mai 9:30 !cao ~45p #laptop`.
- Lên lịch theo ngày, thứ trong tuần hoặc một/nhiều ngày trong tháng.
- Xem My Day, tiến độ, chuỗi ngày hoàn thành và tổng thời gian tập trung.
- Bật nhắc việc trên Android; đồng bộ theo tài khoản và kiểm tra cập nhật APK.

**Công nghệ:** Flutter, Node.js, thông báo cục bộ trên Android.

[Xem mã nguồn](https://github.com/thanhhaotv04/App/tree/Task-Reminder)
· [Hướng dẫn sử dụng và chạy dự án](https://github.com/thanhhaotv04/App/blob/Task-Reminder/README.md)

## ESP32-NavRide

Bộ ứng dụng Android và firmware dành cho màn hình phụ trên xe máy. Điện thoại
gửi chỉ dẫn từ **OsmAnd** qua Bluetooth LE đến **ESP32-S3 N16R8**, hiển thị trên
màn hình **TFT ST7735 1.8 inch (128 × 160)**.

<p align="center">
  <img src="https://raw.githubusercontent.com/thanhhaotv04/App/ESP32-NavRide/docs/images/04-osmand-cropped.jpg" width="260" height="549" alt="OsmAnd trên điện thoại hiển thị bản đồ, hướng đi tiếp trên đường Đỗ Mười và khoảng cách 3,6 km">
  <img src="https://raw.githubusercontent.com/thanhhaotv04/App/ESP32-NavRide/docs/images/05-esp32-navigation-cropped.jpg" width="260" height="549" alt="Màn hình ESP32 hiển thị mũi tên đi thẳng, tên đường QL.1 Đỗ Mười và khoảng cách 3,60 km">
</p>
<p align="center"><sub>OsmAnd trên điện thoại · Chỉ dẫn trên màn hình ESP32</sub></p>

- Hiển thị mũi tên, tên đường sắp rẽ và khoảng cách.
- Nhận tốc độ GPS từ điện thoại, thông báo cá nhân và việc cần làm.
- Có đồng hồ, bấm giờ, đếm ngược, QR và chế độ chỉ hiển thị giờ.
- Hỗ trợ kết nối Wi-Fi hoặc Bluetooth; một phương thức hoạt động tại một thời điểm.
- Dẫn đường qua Bluetooth không cần Wi-Fi; tải trước bản đồ trong OsmAnd để dùng
  ngoại tuyến. Cầu nối OsmAnd yêu cầu app Android.

**Công nghệ:** Flutter, Android, ESP32-S3, Arduino, PlatformIO, Bluetooth LE.

[Xem mã nguồn](https://github.com/thanhhaotv04/App/tree/ESP32-NavRide)
· [Hướng dẫn tổng quan](https://github.com/thanhhaotv04/App/blob/ESP32-NavRide/README.md)
· [Ứng dụng Android](https://github.com/thanhhaotv04/App/blob/ESP32-NavRide/App/README.md)
· [Firmware và nối dây](https://github.com/thanhhaotv04/App/blob/ESP32-NavRide/Firmware/README.md)

## Tải mã nguồn ứng dụng

Trên GitHub, bấm tên branch trong bảng trên hoặc dùng menu chọn branch để mở
ứng dụng muốn xem.

Để tải riêng một ứng dụng về máy, clone đúng branch. Ví dụ với Task Reminder:

```bash
git clone --single-branch --branch Task-Reminder https://github.com/thanhhaotv04/App.git task-reminder
cd task-reminder
```

Thay `Task-Reminder` bằng tên branch tương ứng trong bảng và `task-reminder`
bằng tên thư mục muốn lưu. Sau đó làm theo **README.md của ứng dụng** để cài
môi trường, chạy thử hoặc tạo APK. ESP32-NavRide có thêm hướng dẫn nạp firmware
trong thư mục `Firmware/`.

## Cài đặt và cập nhật

Hướng dẫn tạo APK, tải bản cài và cập nhật nằm trong README của từng ứng dụng.
Các tính năng đồng bộ cần backend được cấu hình theo hướng dẫn của app đó.
Bản APK được cung cấp trong branch có thể chưa chứa mọi thay đổi mới nhất của
mã nguồn.
