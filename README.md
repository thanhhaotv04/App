# App

Bộ sưu tập ứng dụng phục vụ quản lý cá nhân, lưu hành trình và kết nối thiết bị
ESP32. Mỗi ứng dụng được phát triển trên một **branch riêng**, với mã nguồn và
hướng dẫn sử dụng đi kèm.

Branch **`main`** là trang giới thiệu chung. Chọn ứng dụng bên dưới để xem mã
nguồn, cách cài đặt và hướng dẫn chạy dự án.

## Danh sách ứng dụng

| Ứng dụng | Giới thiệu | Branch |
| --- | --- | --- |
| [VietNam Map Checkin](#vietnam-map-checkin) | Lưu địa điểm đã đến, ảnh và hành trình khám phá Việt Nam. | [`VietNam-Checking-Map`](https://github.com/thanhhaotv04/App/tree/VietNam-Checking-Map) |
| [Money Manager](#money-manager) | Theo dõi thu nhập, chi tiêu và các khoản chi định kỳ. | [`Money-Manager`](https://github.com/thanhhaotv04/App/tree/Money-Manager) |
| [Task Reminder](#task-reminder) | Quản lý công việc, lịch nhắc và tiến độ hằng ngày. | [`Task-Reminder`](https://github.com/thanhhaotv04/App/tree/Task-Reminder) |
| [ESP32-NavRide](#esp32-navride) | Hiển thị chỉ dẫn đường từ điện thoại lên màn hình ESP32 cho xe máy. | [`ESP32-NavRide`](https://github.com/thanhhaotv04/App/tree/ESP32-NavRide) |

## VietNam Map Checkin

Nhật ký du lịch giúp lưu lại những nơi đã ghé thăm và theo dõi hành trình khám
phá các tỉnh, thành Việt Nam.

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
