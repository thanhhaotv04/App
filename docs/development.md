# Hướng dẫn sử dụng và phát triển

[Xem giới thiệu và ảnh giao diện](../README.md). Các lệnh chạy từ thư mục gốc dự án, trừ đoạn có `cd backend`.

## Chuẩn bị

Máy phát triển cần Flutter với Dart tương thích `pubspec.yaml` (Dart 3.12.2 trở lên trong nhánh 3.x), Android SDK để build APK và Node.js 22.13.0 trở lên để chạy backend.

Backend mặc định chạy ở cổng `3002`. Kết nối từ thiết bị khác phải dùng HTTPS với chứng chỉ hợp lệ; HTTP chỉ bind vào loopback để phát triển hoặc đặt sau reverse proxy TLS.

## Sử dụng hằng ngày

- Mặc định dùng tài khoản **local**, không cần backend hoặc Wi-Fi. Chọn
  **Register** để tạo tài khoản trên thiết bị; dữ liệu của mỗi tài khoản được tách riêng.
- Để đồng bộ, chọn **Use a sync account** tại màn hình đăng nhập. Địa chỉ máy chủ
  nằm trong **Server settings**; tài khoản local và tài khoản đồng bộ có dữ liệu riêng,
  không tự gửi giao dịch local lên server.
- Trong **Account → Change password**, có thể đổi mật khẩu local hoặc đồng bộ.
  Tài khoản đồng bộ có **Forgot password?**, cần mã khôi phục do chủ server cấp.
- Nút hình mắt trên thanh đầu trang ẩn/hiện số tiền đã lưu. Lựa chọn được nhớ
  sau khi mở lại app; số tiền đang nhập vẫn hiển thị để tránh nhập nhầm.
- Các nút xóa hàng loạt nằm trong **Account → Delete transactions**, vẫn yêu cầu
  xác nhận. Xóa từng giao dịch trong History có thể **Undo** ngay sau khi xóa.

Các kiểm tra bảo mật và giới hạn hiện tại được ghi trong [SECURITY.md](../SECURITY.md).

## Tạo APK

### Bản LAN từ ngày 19/09/2026

Ứng dụng phát hành có tên **Money Manager LAN**, package
`com.thanhhao.money_manager.lan`. Bản debug có thêm `.debug`, để cài thử không
xung đột chữ ký với bản phát hành. App gốc `com.thanhhao.money_manager` vẫn được
giữ nguyên; không gỡ app cũ khi còn dữ liệu chưa đồng bộ. Đăng nhập bản LAN để
lấy dữ liệu đã có trên backend. Dữ liệu chỉ lưu trong sandbox app cũ không tự
chuyển sang app mới.

Trên cùng Wi-Fi, mở `http://192.168.1.146:3003` để tải APK lần đầu. Trang HTTP
chỉ phục vụ bản cài công khai, không có API tài khoản/dữ liệu. App dùng
`https://192.168.1.146:3002`; CA LAN công khai được đóng gói trong app, không bỏ
kiểm tra TLS/hostname và không cần cài CA lên toàn bộ điện thoại. Các lần sau
dùng **Account → Check for update** trong **Money Manager LAN**.

Khóa ký cố định và cấu hình HTTPS lưu tại `~/.config/money-manager/`, quyền
truy cập chỉ cho chủ tài khoản; bản sao lưu tại
`~/.local/share/money-manager/signing-backup/`. Sao lưu thư mục này ra nơi an
toàn ngoài máy và không tạo lại khóa khi phát hành bản mới. Chỉ CA công khai
trong `assets/certificates/lan-ca.pem` được đưa vào source/APK.

`./fastUpdate.sh --notes "Nội dung cập nhật"` tự nạp `release.env`, kiểm tra
package/version/chữ ký khớp fingerprint cố định và bản đã phát hành trước đó.
Script từ chối phát hành nếu đổi khóa. Quy tắc này tuân theo
[cơ chế ký cập nhật Android](https://developer.android.com/studio/publish/app-signing).

Backend chạy bằng user service `money-manager-backend.service`:

```bash
systemctl --user start money-manager-backend
systemctl --user status money-manager-backend
journalctl --user -u money-manager-backend -n 30
```

Nên giữ IP LAN `192.168.1.146` cố định trên router. Nếu IP đổi, cập nhật địa chỉ
và cấp lại chứng chỉ server bằng cùng CA, không thay khóa ký APK hoặc CA đã
đóng gói. Chứng chỉ server hiện có hạn 825 ngày; CA có hạn 10 năm.

Tại thư mục gốc của dự án, chạy:

```bash
flutter pub get
flutter build apk --debug
```

APK được tạo tại:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Chạy trên web

Mở hai terminal tại thư mục gốc dự án.

Terminal 1 — chạy backend:

```bash
cd backend
npm ci
TLS_CERT=/path/fullchain.pem TLS_KEY=/path/private-key.pem npm start
```

Terminal 2 — chạy web:

```bash
flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Mở `http://localhost:8080` trên máy chạy app. Khi truy cập từ thiết bị khác,
phục vụ web qua HTTPS (ví dụ reverse proxy TLS); secure storage và Web Locks
cần secure context. Không dùng HTTP qua IP LAN. Trong màn hình đăng nhập
chọn **Use a sync account → Server settings**, hoặc vào Account của tài khoản
đồng bộ, rồi đặt địa chỉ máy chủ thành:

```text
https://<TEN-MAY-HOAC-DOMAIN>:3002
```

Trên Linux, dùng `hostname -I` để xem IP LAN của máy chạy backend.

Khi tự host bản web, build tài nguyên đồ họa cùng ứng dụng để tránh phụ thuộc CDN:

```bash
flutter build web --no-web-resources-cdn --no-tree-shake-icons
```

Font Roboto được đóng gói trong app kèm giấy phép. Phục vụ `build/web` qua HTTPS;
không đưa thư mục backend, database, cấu hình TLS hoặc khóa ký vào web root.

Kiểm tra backend đã sẵn sàng:

```bash
curl 'https://<TEN-MAY-HOAC-DOMAIN>:3002/api/health'
```

Flutter web cần thêm `ALLOWED_ORIGINS=https://<WEB-ORIGIN>` khi chạy backend.
Ứng dụng Android không gửi header Origin.

## Dữ liệu, đồng bộ và đăng xuất

- Dữ liệu local mới được mã hóa và tách theo server, username và ID tài khoản.
  Tài khoản tạo lại có cùng username không tự nhận dữ liệu của ID cũ.
- Sau khi nâng cấp từ bản dùng dữ liệu chung hoặc chỉ tách theo username,
  đăng nhập lại nếu được yêu cầu. Trong **Account → Recover older data**,
  xác nhận quyền khôi phục rồi chọn từng mục của mình. Không chọn dữ liệu
  của người khác. Bản gốc được giữ nguyên; lịch chi khôi phục được tạm dừng.
- Thao tác ghi trong app được xếp hàng; bản web dùng Web Locks giữa các tab
  và đọc lại dữ liệu trước mỗi lần ghi. Bản dữ liệu tài chính mã hóa trên web
  được lưu trong IndexedDB để tránh giới hạn dung lượng nhỏ của localStorage.
  Cửa sổ giữ phiên tài khoản cũ không
  được đồng bộ bằng phiên đăng nhập mới.
- Đồng bộ protocol 3 gửi/nhận từng phần tối đa khoảng 512 KiB, kiểm tra cùng
  phiên bản dữ liệu giữa các trang. Cần cập nhật backend cùng mã nguồn này
  trước khi dùng app mới. Protocol 2 vẫn hỗ trợ tài khoản nhỏ và từ chối
  thao tác vượt giới hạn trước khi ghi, yêu cầu nâng cấp app.
- Khi offline, **Sign Out** xóa phiên đăng nhập local và lưu yêu cầu thu hồi
  token trong secure storage. App thử lại khi mở, quay lại ứng dụng, đăng
  nhập hoặc bấm **Retry sign-out**. Token trên server chỉ được xác nhận đã
  thu hồi sau khi server trả lời; trạng thái này hiển thị trên màn hình đăng nhập.
- Giới hạn thử sai đăng nhập áp dụng cho cặp IP/username, không khóa username
  trên mọi IP. Giới hạn IP vẫn áp dụng với máy dùng chung mạng; đăng xuất
  luôn có thể thu hồi token ngay cả khi các giới hạn này đã bị vượt.

Tham khảo cơ chế khóa tab: [Web Locks API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Locks_API).

## Khôi phục mật khẩu

Endpoint reset không tự đổi mật khẩu chỉ bằng username. Sau khi xác minh chủ
tài khoản, quản trị viên tạo mã dùng một lần, có hạn 15 phút:

```bash
cd backend
node recovery-code.js '<username>'
```

Người dùng nhập username, mã này và mật khẩu mới trong màn hình Reset password.

## Cập nhật ứng dụng và kiểm tra qua LAN

Khởi động backend HTTPS đã cấu hình trước khi phát hành. Nếu đã có `~/.config/money-manager/release.env`, script tự nạp cấu hình này. Khi cấu hình thủ công, thay các giá trị mẫu bằng thông tin triển khai của bạn rồi chạy tại thư mục gốc dự án:

```bash
PUBLIC_BACKEND_URL='https://<DOMAIN>:3002' \
MM_KEYSTORE=/path/release.jks \
MM_STORE_PASSWORD='...' \
MM_KEY_ALIAS='...' \
MM_KEY_PASSWORD='...' \
MM_APPLICATION_ID=com.thanhhao.money_manager.lan \
MM_SIGNER_SHA256='<SHA256-cua-chung-chi-ky>' \
TLS_CERT=/path/fullchain.pem \
TLS_KEY=/path/private-key.pem \
./fastUpdate.sh --notes "Cải thiện giao diện và sửa lỗi"
```

Script sẽ tự động:

- tạo phiên bản hiển thị theo `YYMMDD.N`, ví dụ `260823.1`;
- tăng `versionCode`, tạo APK release đã ký và publish APK/manifest kèm SHA-256;
- kiểm tra format, analyzer, test Flutter và cú pháp backend;
- kiểm tra backend HTTPS đã chạy ở cổng `3002`, rồi in Backend URL cho thiết bị LAN.

Sau khi script hoàn tất, mở tab **Account**, lưu Backend URL HTTPS được script
in ra và chọn **Check for update**. Có thể đổi port
bằng `./fastUpdate.sh --port 3003` hoặc chỉ xem phiên bản dự kiến bằng
`./fastUpdate.sh --dry-run`.

Tính năng tải và cài APK chỉ hoạt động trên Android. App kiểm tra SHA-256,
package name, version tăng, trạng thái non-debug và chữ ký trùng ứng dụng đang
cài trước khi mở trình cài. Không thể cập nhật APK gốc đã khôi phục nếu không có
khóa ký gốc.
