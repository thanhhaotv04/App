# Kiểm thử và phân quyền dashboard — 10/10/2026

## Đã sửa

- Chỉ một admin: đúng UID được cấu hình, đúng email, email đã xác minh.
  Không cấp quyền bằng cách sửa email trên giao diện hoặc tự thêm `role: admin`.
- Tài xế chỉ chọn/xem xe đang được phân công. Đổi tài xế thu hồi quyền cũ;
  người mới đọc lịch sử theo xe nhưng không sửa chuyến/ghi điểm vào chuyến cũ.
- Admin xem xe ở mọi fleet; tạo/sửa tên, phân công, Archive/Restore,
  thêm/thu hồi thành viên. Không xóa vĩnh viễn xe hoặc chuyến đủ 2 điểm.
- Thao tác nhạy cảm có xác nhận, nút Cancel mặc định, Escape hủy đúng kể cả
  sau lần xác nhận trước. Tên/UID được hiển thị bằng text, không chèn HTML.
- Lỗi tải Firebase có thông báo và Reload; không submit mật khẩu lên URL.
  Có email đặt mật khẩu, xác minh email; không tiết lộ email có tồn tại không.
- Lỗi mất quyền xóa điểm/tuyến trên màn; mất mạng giữ tuyến cùng xe/ngày
  với nhãn Offline. Đổi xe/ngày không giữ nhầm tuyến cũ.
- Trip qua nửa đêm lấy thêm hồ sơ trip gốc; thiếu hồ sơ ghi “First point”,
  không giả thời điểm bắt đầu. Chuyến đang chạy hiển thị “In progress”.
- Cập nhật danh sách không làm mất focus/scroll. Đăng nhập/đăng xuất có
  focus rõ. Tắt animation bản đồ dễ lỗi khi logout trong lúc phóng/thu.
- Mobile thấy email tài khoản và bản đồ trước danh sách dài. Dark mặc định,
  hỗ trợ Light; kiểm tra 320/375/768/1024/1440 px và font 200%.
- Rules bắt buộc giới hạn truy vấn; không mở truy vấn không giới hạn.
- Vá dependency công cụ: gRPC, basic-ftp, OpenTelemetry core, uuid của gaxios.

## Bằng chứng kiểm thử

`npm run test:dashboard`: 9 kiểm thử logic/login/theme.

`npm run test:rules`: 13 nhóm kiểm thử Firestore Emulator, gồm trường hợp
thành công và từ chối; không dùng database thật.

`npm run test:browser`: 9 nhóm Chromium, mock Firebase; thử hai role,
xác nhận/hủy Archive, Restore, thêm driver/xe, logout khi đang tải, mất mạng,
mất quyền, nửa đêm, responsive, bàn phím và axe ở hai theme.

Không thao tác Archive, đổi phân công hoặc xóa lịch sử **xe thật** để test.
Bootstrap chỉ tạo tài khoản admin, tài liệu UID bảo vệ và gửi email đã được
chủ project đồng ý. Không lưu mật khẩu/token/liên kết đặt lại mật khẩu.

Đã triển khai rules + Hosting lên project `navride-96851` và kiểm tra lại:

- Hai địa chỉ Hosting trả HTTP 200, đúng HTML hiện tại; sáu tệp JS/CSS đã
  đối chiếu khớp bản local; rules đang chạy khớp `firestore.rules`.
- Truy cập xe khi chưa đăng nhập bị từ chối HTTP 403.
- CSP, HTTPS/HSTS, chống nhúng iframe, nosniff và Permissions-Policy có hiệu
  lực; HTML không cache, module phải revalidate để tránh dùng giao diện cũ.
- SDK Firebase thật tải được trên trang production, màn đăng nhập hoạt động
  đến trạng thái sẵn sàng, không có lỗi JavaScript khi mở bằng Chromium mới.
- Email enumeration protection đang bật. Admin UID đã được cấu hình và API
  Firebase đã xác nhận gửi email đặt mật khẩu; chủ tài khoản chưa xác nhận
  hoàn tất đăng nhập/xác minh tại thời điểm kiểm thử.

Chạy lại kiểm tra chỉ đọc bằng `node scripts/verify-deployment.cjs`.

## Không coi là đã hoàn tất

- Chủ tài khoản cần mở email, tự đặt mật khẩu mạnh và xác minh email. Test
  mock/emulator không thay cho đăng nhập admin thực tế bằng mật khẩu của chủ.
- App Check chưa enforce cho Android/Web; cần đăng ký cả hai trước khi bật.
- Chưa đặt password policy toàn project; chủ tài khoản cần chọn mật khẩu
  mạnh, riêng biệt qua email. Không thay chính sách đăng nhập của các tài
  xế hiện có trong đợt thêm quyền quản trị này.
- Chuyến dưới 2 điểm được dọn khi admin mở dashboard có mạng; không có tác vụ
  tự chạy khi admin vắng mặt. Quota chống gửi GPS tùy ý và MFA cần thiết
  kế/cấu hình riêng. Chưa thay gói Firebase hay bật dịch vụ trả phí.
- `npm audit` còn 3 cảnh báo high trong cây công cụ CLI: `braces`, `chokidar`,
  `firebase-tools` (cùng chuỗi phụ thuộc). `braces` chưa có bản vá trong dải
  tương thích; không ép major `chokidar` làm sai watcher/glob của CLI.
  `npm audit --omit=dev` không có cảnh báo; Node dependencies không được
  phục vụ bởi Firebase Hosting. Chỉ dùng CLI với tệp/path tin cậy.
- Archive/thu hồi quyền chặn cloud ở rules, không tắt GPS/điều hướng BLE từ xa.
  Bản app điện thoại hiện tại vẫn cần tài xế bấm `End ride` khi ngừng sử dụng.
- Không sửa/nạp firmware hoặc phát hành APK trong đợt chỉnh dashboard này.

Test browser không phải chứng nhận WCAG hoặc kết luận hệ thống không còn lỗi.
Sau triển khai cần kiểm tra assets/rules thật, HTTP 403 cho người chưa đăng
nhập và đăng nhập bằng từng loại tài khoản để nghiệm thu vận hành.

## Màu từng chuyến — 11/10/2026

- Mỗi chuyến trong xe/ngày đang xem có màu và số riêng; đường, marker,
  danh sách chuyến và timeline dùng cùng bảng màu. Lọc một chuyến không
  đổi màu của nó. Không nối điểm từ hai chuyến khác nhau; chuyến thiếu
  hồ sơ hoặc dữ liệu cũ vẫn có màu. Không chỉ dựa vào màu để nhận diện.
- Đã sửa chú thích lấy điểm thành tối thiểu 1 phút và di chuyển hơn 100 m,
  cả online/offline, khớp app hiện tại. Không đổi quy tắc database.
- Đạt 11 test logic và 10 nhóm Chromium; quan sát lời gọi Leaflet thật để
  đối chiếu màu đường/marker/chú giải, lọc và cập nhật realtime. Có kiểm tra
  responsive, bàn phím, axe cho dark/light. Ảnh thử dùng dữ liệu giả.
  Cập nhật trạng thái đơn thuần không vẽ lại tuyến/đóng popup đang xem.
- Hosting đã triển khai; hai domain, HTML và sáu asset khớp local;
  rules giữ nguyên, truy cập xe không đăng nhập vẫn bị từ chối HTTP 403.

### Fleet không cần ESP32

- Kiểm tra app: `startFleetTrip` yêu cầu đăng nhập, xe được phân công và
  quyền GPS; không kiểm tra BLE. Giới hạn BLE chỉ áp dụng `startSpeed` để
  gửi tốc độ lên màn ESP32, không áp dụng Fleet.
- Thử trên điện thoại thật khi người dùng xác nhận đứng yên: Disconnect
  ESP32 → Start trip thành công, app hiện đồng thời `ESP32 not connected`
  và `Trip active`; foreground service yêu cầu GPS mỗi 15 giây.
- Lần thử chưa có fix GPS đủ chính xác, nên chưa chứng minh được điểm mới
  lên server khi không có ESP32. Không dùng GPS giả để thay kết quả này.
  Đã End trip sau thử; không cài/gỡ app hoặc nạp firmware.
- Kết thúc: app báo `Trip ended; synced`, không còn service GPS hoạt động;
  đã kết nối lại ESP32 và xác nhận `Connected · Bluetooth` trên app.
