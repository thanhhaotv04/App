# Kiểm tra quyền riêng tư — 09/10/2026

Phạm vi: mã Flutter/Android, backend Node.js, lưu trữ local, API tài khoản/đồng bộ,
luồng cập nhật APK và các file dự kiến đưa lên nhánh `Money-Manager`.

## Các lớp bảo vệ

- Giao dịch mới được mã hóa AES-GCM, với khóa và namespace riêng theo tài khoản,
  ID và máy chủ. Đăng nhập tài khoản khác không tự nhận dữ liệu cũ.
- Backend lấy ID từ phiên đăng nhập, bỏ qua ID do client tự chọn. Phiên chỉ lưu
  hash token trong database; logout và đổi/reset mật khẩu thu hồi phiên.
- Mật khẩu local mới dài 12–128 ký tự, hash PBKDF2-HMAC-SHA256 600.000 vòng.
  Hash local cũ được nâng cấp sau đăng nhập đúng, không đổi khóa dữ liệu.
  Sau 10 lần sai, tài khoản local phải chờ 5 phút.
- Backend dùng scrypt N=32768, r=8, p=3; hash cũ được nâng cấp sau đăng nhập đúng.
  Cấu hình tham khảo [OWASP Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
- Loại bỏ mật khẩu từ cache phiên cũ; không đưa password, token, recovery code,
  nội dung giao dịch hoặc exception thô vào log backend.
- Kết nối từ xa phải dùng HTTPS, không bỏ kiểm tra chứng chỉ/hostname, không
  theo redirect khi gửi thông tin xác thực. CORS giới hạn theo `ALLOWED_ORIGINS`.
- API nhạy cảm dùng `Cache-Control: no-store`; lỗi trả về không chứa stack trace.
  Đồng bộ kiểm tra payload, giới hạn kích thước, xử lý xóa và ghi đồng thời.
- Android tắt backup và loại trừ dữ liệu khỏi device transfer bằng
  [data extraction rules](https://developer.android.com/identity/data/autobackup).
- APK cập nhật phải đúng kích thước/hash, package, chữ ký, version tăng và không
  phải bản debug. FileProvider chỉ chia sẻ thư mục cập nhật.
- Database, dữ liệu runtime, khóa ký và khóa TLS bị loại khỏi Git. Chỉ chứng chỉ
  CA công khai và metadata/hash APK được phép đưa lên GitHub.
- Dependency backend `proxy-addr` có cảnh báo critical đã được vá; `npm audit`
  không còn phát hiện lỗ hổng tại thời điểm kiểm tra.

## Kiểm tra lại

```bash
flutter analyze --no-pub
flutter test --no-pub
cd backend
npm ci
npm test
npm audit --audit-level=moderate
```

Các bài kiểm thử dùng tài khoản và giao dịch giả, kiểm tra cách ly tài khoản,
khôi phục mật khẩu, thu hồi phiên, migration, dữ liệu lỗi và ghi đồng thời.
Gitleaks được dùng để quét mã chuẩn bị commit và lịch sử nhánh; không phát hiện secret.

## Giới hạn cần giữ rõ

- Đây là kiểm tra mã nguồn và chạy test/build; không thay thế kiểm tra server
  production hoặc thử nghiệm trên điện thoại thật. Push source không tự triển khai
  backend đang chạy hay cập nhật APK đã cài.
- Trình duyệt ở `localhost` vẫn hỗ trợ fallback lưu secret trong browser storage
  nếu secure storage không hoạt động, để giữ chế độ local đã có. Người truy cập
  được browser profile hoặc script cùng origin có thể đọc các secret này. Trên
  host khác, app yêu cầu secure storage và nâng cấp bản fallback cũ trước khi dùng.
  Secure storage trên web cũng không chống được script độc hại cùng origin hoặc
  extension có quyền truy cập trang; cần bảo vệ nơi host web và browser profile.
- Màn hình được phủ khi app chuyển sang trạng thái không hoạt động; ẩn số tiền
  là tiện ích chống nhìn trộm. Các chức năng này không phải khóa app hay bảo đảm
  chặn mọi ảnh chụp màn hình của hệ điều hành.
- Database backend được bảo vệ bằng quyền thư mục `0700` và file `0600`; chủ
  server vẫn có thể đọc nội dung. Cần bảo vệ tài khoản hệ điều hành và bản sao lưu.
- Bản dữ liệu từ phiên bản cũ được giữ để phục hồi có xác nhận, không tự nhận
  quyền sở hữu chỉ từ username. Các bản plaintext cũ có thể còn trên thiết bị;
  không chia sẻ browser profile, thư mục dữ liệu hoặc bản backup của app.
- Tài khoản local lưu trên thiết bị; nếu mất mật khẩu hoặc xóa dữ liệu/khóa của
  ứng dụng thì server không thể khôi phục tài khoản đó.
