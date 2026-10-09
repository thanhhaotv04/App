# Rà soát quyền riêng tư — 08–09/10/2026

Phạm vi: mã nguồn Flutter/Android, backend Node, dữ liệu chia sẻ và lịch sử Git của nhánh `VietNam-Checking-Map`. Kiểm thử backend sử dụng tài khoản và thư mục tạm riêng; không thay dữ liệu đang có của người dùng.

## Các lỗi đã sửa

- Kho check-in rất cũ được gắn một lần với ID của tài khoản chủ đã có trước khi backend nhận đăng ký. Đổi tên/xóa tài khoản không cho người đăng ký lại tên cũ kế thừa hành trình. Kho cũ chưa có chủ vẫn được giữ nhưng không tự cấp cho tài khoản vừa tạo; quản trị viên phải xác minh chủ để phục hồi.

- Backend từng chấp nhận đường dẫn ảnh dựa trên tiền tố account ID/tên đăng nhập. Tên đăng nhập trùng ID của người khác có thể làm vượt kiểm tra quyền. Đường dẫn hiện phải nằm trong các bản ghi ảnh thực sự thuộc tài khoản; đường dẫn vượt thư mục bị loại.
- Mọi đường tải ảnh dùng cùng kiểm tra origin và đường dẫn; không gửi token đến URL ảnh bên ngoài và không theo redirect. Token đã lưu được gắn với origin backend; đổi máy chủ yêu cầu đăng nhập lại trước khi sync. Preview web dùng tải byte có xác thực.
- Không còn lưu token dự phòng dạng rõ trong SharedPreferences khi secure storage lỗi. Token cũ được chuyển sang secure storage hoặc loại bỏ nếu thiết bị không hỗ trợ. Mật khẩu dạng rõ từ bản cũ được chuyển thành verifier một chiều khi khởi động.
- Giới hạn thử mật khẩu áp dụng cả các API dữ liệu dùng header cũ; có thêm giới hạn theo IP để chặn đổi liên tục tên tài khoản. Logout đọc phiên mới nhất trong hàng đợi ghi, tránh ghi đè phiên của thiết bị khác.
- Backend tự đặt tọa độ về 0 khi nhận `hideLocation`; dữ liệu riêng tư và ảnh trả về với `Cache-Control: no-store`. Bộ nhớ đệm ảnh được xóa khi đăng xuất.
- Ảnh nhỏ trước đây giữ EXIF/GPS. Hiện metadata được loại khi chọn ảnh, upload cả ảnh cũ hoặc chia sẻ album; chiều ảnh, ảnh trong suốt và ảnh động được giữ.
- Album ZIP không xuất `localPhoto`, đường dẫn backend hoặc trạng thái đồng bộ. Tên file được đánh số để ảnh trùng tên không ghi đè nhau. Ẩn tọa độ theo từng check-in hoặc cài đặt riêng tư hiện tại; nếu thiếu ảnh, báo lỗi thay vì chia sẻ thiếu âm thầm.
- Đọc/xóa ảnh cục bộ bị giới hạn trong thư mục tài khoản hiện tại, bao gồm kiểm tra symlink. Android loại dữ liệu ứng dụng khỏi Auto Backup và chuyển thiết bị tự động; backup mã hóa trong app vẫn hoạt động. Cấu hình theo [tài liệu Android về Auto Backup](https://developer.android.com/identity/data/autobackup).
- Cập nhật lockfile backend để xử lý cảnh báo `multer` và `proxy-addr`; không thêm thư viện. Git bỏ qua file môi trường, khóa riêng, backup và thư mục ảnh cục bộ.

## Thao tác đã đơn giản hóa

- Công tắc riêng tư tự lưu; không cần nút Save privacy. Nếu lưu thất bại, công tắc trở về trạng thái trước và báo lỗi.
- Hai ô mật khẩu mới nằm trong mục Change password có thể mở rộng; đổi tên, mật khẩu và đăng xuất vẫn có đầy đủ.
- Đăng ký kiểm tra đúng quy tắc của backend trước khi gửi yêu cầu; phím Enter không gửi lặp khi đang xử lý. Các ô mật khẩu tắt gợi ý và tự sửa.
- Màn hình Account giải thích HTTPS và cách kết nối lại khi đổi máy chủ.

## Kiểm chứng

- `flutter analyze --no-pub`: không có vấn đề; 46/46 Flutter tests đạt, gồm backup mã hóa, offline, đổi tên tài khoản, đăng xuất, URL/redirect ảnh, secure storage, EXIF, ZIP và upload ảnh cũ.
- Widget tests của Account ở rộng 375, 768, 1024 và 1440 px, chữ phóng to 200%; kiểm tra công tắc lưu ngay và các điều khiển còn truy cập được.
- `npm test`: 9/9 đạt, gồm các kiểm thử cũ cộng hồi quy ảnh chéo tài khoản, tọa độ, cache, giới hạn mật khẩu và phiên đồng thời. Các ca hồi quy được chạy lại với backend trước sửa để xác nhận phát hiện lỗi.
- `npm audit --audit-level=moderate`: 0 lỗ hổng; `node --check backend/server.js` và `git diff --check` đạt; build web và Android debug thành công.
- Đã xem giao diện Account được render trong Chromium ở 375 và 1440 px, không có lỗi JavaScript. Screenshot dùng tài khoản giả Preview, được lưu ngoài Git trong `.dart_tool/privacy-review/`.
- Quét nội dung văn bản đang được Git theo dõi và 302 text blobs trong lịch sử nhánh: không thấy private key/token theo các mẫu nhận diện đã dùng; không có accounts/checkins/albums JSON, keystore hoặc backup trong lịch sử nhánh. Đây là quét mẫu, không phải bằng chứng mọi loại thông tin cá nhân đều vắng mặt.

## Giới hạn và cách sử dụng

- HTTP trong LAN vẫn không mã hóa; app chặn HTTP cho địa chỉ Internet công khai. Dùng HTTPS để bảo vệ mật khẩu, token, ảnh và hành trình trên đường truyền. LAN được giữ để tương thích với workflow hiện tại; chỉ dùng trong mạng tin cậy.
- Chia sẻ album vẫn chủ động công bố ảnh, tỉnh/thành, địa điểm, ghi chú và ngày. Ẩn tọa độ không che khuôn mặt, biển số, nội dung ảnh hay địa danh trong ghi chú.
- Bật Privacy không xóa dữ liệu đã đồng bộ trước đó. Ảnh đã có trên backend không được sửa hàng loạt; ảnh cũ được loại metadata khi upload lại hoặc chia sẻ bằng app mới.
- Thiết bị chưa có secure storage hoạt động có thể cần bật HTTPS trên web hoặc mở khóa kho khóa của hệ điều hành rồi đăng nhập lại. Dữ liệu offline và backup vẫn được giữ.
- Không kiểm tra cài APK trên điện thoại thật, quyền truy cập hạ tầng production hoặc mọi bản sao dữ liệu bên ngoài app. Không thể cam kết tuyệt đối không rò rỉ trong mọi môi trường triển khai.
- Lần sửa này chỉ cập nhật mã nguồn trên nhánh cũ; không tăng phiên bản hay thay APK đang được backend phát hành.
