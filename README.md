<p align="center"><img src="assets/App_VietNamMap_Logo_no_background.png" width="112" alt="Biểu tượng VietNam Map Checkin"></p>

# VietNam Map Checkin

**Lưu dấu những nơi bạn đã đi qua trên bản đồ Việt Nam.** Thêm địa điểm, ảnh và ghi chú; gom kỷ niệm vào album và nhìn lại hành trình của mình qua từng tỉnh/thành.

Ứng dụng Flutter cho **Android và web**, gồm năm mục: **Checkin, Album, Map, Insights và Account**. Check-in và ảnh được lưu trên thiết bị trước, rồi đồng bộ hai chiều khi backend khả dụng. Dữ liệu được tách riêng theo tài khoản.

## Check-in

Lưu tỉnh/thành, địa điểm, ngày giờ, ghi chú và nhiều ảnh cho mỗi lần ghé thăm. Thêm địa điểm thủ công hoặc dùng GPS để tự nhận diện tỉnh/thành; tìm kiếm và lọc danh sách theo nguồn check-in.

<p align="center"><img src="docs/images/01-checkin.png" width="260" alt="Màn hình Check-in với ô tìm kiếm, bộ lọc nguồn, danh sách địa điểm và nút Add check-in"></p>
<p align="center"><sub>Tìm lại kỷ niệm hoặc thêm một điểm dừng mới</sub></p>

## Album

Gom ảnh và check-in vào từng chuyến đi. Tạo, đổi tên và tìm album theo tên, địa điểm hoặc ngày; chọn ảnh bìa, sắp xếp ảnh và chia sẻ album dưới dạng ZIP. Xóa album không xóa check-in gốc.

<p align="center"><img src="docs/images/02-albums.png" width="260" alt="Màn hình Albums với nút New album, ô tìm kiếm và các album Food Tour, Market Tour"></p>
<p align="center"><sub>Mỗi chuyến đi là một album riêng</sub></p>

## Bản đồ Việt Nam

Chạm vào một tỉnh/thành để xem kỷ niệm hoặc thêm check-in tại đó. Tìm nhanh địa phương bằng tên; màu sắc trên bản đồ thể hiện số check-in. Trên máy tính, rê chuột lên tỉnh/thành để xem ảnh gần đây.

<p align="center"><img src="docs/images/03-map.png" width="260" alt="Bản đồ Việt Nam với ô tìm tỉnh hoặc thành phố và thang màu số check-in: 0, 1–2, 3–5, 6 trở lên"></p>
<p align="center"><sub>Nhìn lại hành trình qua những vùng đã ghé thăm</sub></p>

Bản đồ và thống kê sử dụng bộ dữ liệu lịch sử **63 tỉnh/thành**.

## Thống kê hành trình

**Insights** cho biết tỷ lệ tỉnh/thành đã ghé thăm (**Vietnam coverage**), số địa phương còn lại và tiến độ theo 8 vùng. **Travel rhythm** thống kê check-in theo tháng, số ngày có check-in và chuỗi ngày liên tiếp gần đây.

<p align="center">
  <img src="docs/images/04-vietnam-coverage.png" width="380" alt="Vietnam coverage hiển thị tỷ lệ hoàn thành, số tỉnh còn lại trong bản đồ lịch sử và nút Explore the map">
  <img src="docs/images/05-travel-rhythm.png" width="380" alt="Travel rhythm hiển thị số ngày có check-in, chuỗi ngày gần đây và biểu đồ check-in theo 12 tháng">
</p>
<p align="center"><sub>Tiến độ khám phá Việt Nam · Nhịp đi của bạn qua từng tháng</sub></p>

Mở **Timeline** để xem các check-in được nhóm thành chuyến đi, hoặc sao chép **Travel recap** để chia sẻ bản tóm tắt hành trình.

## Tài khoản và đồng bộ

Trong **Account**, lưu **Backend URL** rồi chọn **Sync now** để đồng bộ check-in, album và ảnh. **Sync center** giúp theo dõi thao tác đang chờ, lỗi và xử lý xung đột dữ liệu.

<p align="center"><img src="docs/images/06-backend-sync.png" width="420" alt="Backend and sync với trường Backend URL và ba nút Save URL, Sync now, Sync center"></p>
<p align="center"><sub>Cấu hình máy chủ và đồng bộ khi có kết nối</sub></p>

Account còn có giao diện sáng/tối, đổi mật khẩu, backup mã hóa, lịch backup tự động, tùy chọn **Local only**, **Hide exact coordinates** và quản lý dung lượng ảnh. [Xem chi tiết dữ liệu và quyền riêng tư](docs/development.md#chức-năng-dữ-liệu-và-bảo-mật).

## Cập nhật ứng dụng

Mở **Account → App update → Check for update** để kiểm tra APK mới từ backend đã cấu hình. App kiểm tra SHA-256 của APK tải về trước khi chuyển cho Android cài đặt.

<p align="center"><img src="docs/images/07-app-update.png" width="420" alt="App update hiển thị phiên bản đang cài và nút Check for update"></p>
<p align="center"><sub>Kiểm tra bản cập nhật ngay trong ứng dụng Android</sub></p>

Địa chỉ backend, phiên bản và số liệu trong ảnh là ví dụ từ lúc chụp; hãy dùng địa chỉ máy chủ của bạn. HTTP chỉ dành cho LAN tin cậy; khi triển khai thật, cấu hình HTTPS theo [hướng dẫn backend](docs/development.md#chạy-backend).

## Bắt đầu

- **Android:** [build APK và cài đặt](docs/development.md#build-apk-android).
- **Web:** [chạy ứng dụng trên trình duyệt](docs/development.md#chạy-trên-web).
- **Backend và cập nhật LAN:** [chạy máy chủ](docs/development.md#chạy-backend) và [phát hành bản cập nhật](docs/development.md#phát-hành-bản-cập-nhật-qua-lan).
- **Quyền riêng tư:** [báo cáo rà soát và giới hạn kiểm chứng](docs/privacy-review.md).
