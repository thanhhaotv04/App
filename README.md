# VietNam Map Checkin

Ứng dụng Flutter lưu hành trình tại Việt Nam theo tài khoản. Giao diện có đúng năm mục:

- **Checkin:** lưu điểm bất kỳ theo tỉnh/thành và địa điểm, ngày giờ, ghi chú, nhiều ảnh; form thêm không còn Tags, Favorite place hay Memory score. Có thể xem, sửa, lưu ảnh ra máy và xóa từng ảnh.
- **Album:** tạo, đổi tên, tìm kiếm và chia sẻ album ZIP; chọn ảnh bìa, đổi thứ tự ảnh, chọn nhiều ảnh hoặc chụp ảnh, ghi Place và Note, sao chép ảnh từ Checkin hoặc gắn check-in đã có. Xóa album hay ảnh sao chép không xóa Checkin gốc.
- **Map:** bản đồ Việt Nam, số tỉnh/thành đã đi, lịch sử check-in theo tỉnh với tìm kiếm, lọc và sắp xếp.
- **Insights:** Vietnam coverage, Progress by 8 regions, Travel rhythm, Travel recap và Timeline tự nhóm chuyến đi cách nhau tối đa 48 giờ.
- **Account:** tài khoản, giao diện, Backend URL, Sync Center, backup mã hóa, lịch backup tự động, chế độ riêng tư, dung lượng ảnh, xóa tài khoản và Update.

Check-in và ảnh được lưu trên thiết bị trước, rồi đồng bộ hai chiều khi backend khả dụng. Dữ liệu của các tên đăng nhập được tách riêng. Đăng nhập cùng tên và mật khẩu của tài khoản hiện có để lấy lại check-in và album từ backend. Tài khoản đã lưu trên thiết bị có thể đăng nhập offline; sau đó mở **Account**, đặt Backend URL và chọn **Sync now** nếu địa chỉ máy chủ thay đổi. Không gỡ hoặc xóa dữ liệu của ứng dụng cũ trước khi dữ liệu trên backend đã được kiểm tra. Để cập nhật tại chỗ, giữ nguyên Android application ID và khóa ký của bản đang cài.

Màn hình đầu có **Register** cho người chưa có tài khoản và **Sign in** cho người đã đăng ký; không hiển thị Backend URL tại đây. Sau khi đăng nhập hoặc đăng ký thành công, lần mở app tiếp theo vào thẳng tài khoản đang dùng, kể cả khi backend tạm ngắt. Chọn **Account → Sign out** để đổi tài khoản; sau khi thoát, app yêu cầu đăng nhập lại. Việc tạo tài khoản mới cần kết nối backend theo địa chỉ mặc định hoặc địa chỉ đã lưu trên thiết bị. Username không được trùng với tài khoản đã có, kể cả khác chữ hoa/thường hoặc khoảng trắng ở hai đầu. Nếu backend tạm ngắt, chỉ tài khoản đã lưu trên thiết bị mới có thể đăng nhập offline bằng đúng mật khẩu cũ; đăng nhập không tự tạo tài khoản mới. Sau khi đăng nhập, có thể đổi Backend URL trong **Account**.

Album và ảnh đã xóa được đánh dấu theo tài khoản để không xuất hiện lại sau khi Sync.

## Chức năng dữ liệu và bảo mật

- **GPS:** nút Use current location xin quyền vị trí, lưu tọa độ và tự nhận diện tỉnh/thành từ GeoJSON ngoại tuyến.
- **Sync Center:** hiển thị thao tác đang chờ, số lần thử/lỗi; xóa offline không bị tải lại từ server; xung đột cho phép chọn bản local hoặc server.
- **Privacy:** công tắc tự lưu ngay. Local only áp dụng cho check-in mới; Hide exact coordinates áp dụng cho tọa độ của check-in mới và mọi album được chia sẻ. Không tự xóa tọa độ đã đồng bộ trước đó.
- **Backup:** file `.vmcbackup` dùng PBKDF2-SHA256 và AES-256-GCM, có thể gồm ảnh; backup tự động lưu hàng ngày/hàng tuần trong thư mục dữ liệu ứng dụng.
- **Ảnh:** loại EXIF/GPS và metadata khi thêm, upload hoặc chia sẻ; giữ chiều ảnh, độ trong suốt và ảnh động. Backend kiểm tra chữ ký JPEG/PNG/GIF/WebP, giới hạn 12 MB/file, quota mặc định 500 MB/tài khoản. URL ảnh phải thuộc backend đã cấu hình; không chuyển tiếp token qua redirect.
- **Phiên đăng nhập:** token chỉ lưu trong secure storage và gắn với backend đã đăng nhập. Khi đổi địa chỉ máy chủ, đăng xuất rồi đăng nhập lại để đồng bộ; dữ liệu offline vẫn còn. Backend giới hạn thử mật khẩu trên cả API đăng nhập và API dữ liệu, kiểm tra quyền sở hữu ảnh bằng bản ghi thực tế và cấm cache dữ liệu riêng tư.
- **Update:** APK được kiểm tra SHA-256 do backend cung cấp trước khi chuyển cho Android cài đặt.

## Chạy và kiểm tra

```bash
flutter pub get
flutter analyze
npm install
flutter test
npm test
npm audit --audit-level=moderate
npm run backend
```

Backend mặc định chạy cổng 3000. Với workflow cập nhật LAN hiện tại, đặt Backend URL là `http://<IP-LAN-của-máy-tính>:3000`, không dùng `127.0.0.1`. Có thể dùng HTTPS nếu backend đã cấu hình TLS.

HTTP chỉ phù hợp để thử nghiệm trong LAN tin cậy. Khi triển khai thật, đặt `NODE_ENV=production`, `TLS_CERT_FILE`, `TLS_KEY_FILE` và `CORS_ORIGINS` trước khi chạy backend, rồi dùng Backend URL `https://...`; server sẽ từ chối khởi động production nếu thiếu TLS (trừ khi bật rõ `ALLOW_INSECURE_HTTP=1`). Không đưa mật khẩu qua Wi-Fi công cộng bằng URL HTTP.

Các APK đang phát hành dùng cùng certificate debug cũ để giữ khả năng cập nhật đè. `fastUpdate.sh` tự tạo/dùng `android/vietnam-map-debug.keystore`, alias `thanhhaodebugkey`, mật khẩu `thanhhao`; có thể ghi đè bằng `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` và `ANDROID_KEY_PASSWORD`. Đây là lựa chọn tương thích nhanh nhưng có rủi ro bảo mật; giữ nguyên certificate hiện tại giữa các lần cập nhật.

`npm run backend` **chỉ phục vụ bản phát hành đang có** trong `backend/releases/`; lệnh này không build hoặc thay APK. `flutter build apk` cũng chỉ tạo APK trong `build/app/outputs/flutter-apk/`. Để phát hành bản tiếp theo qua nút **Check for update**, dùng `./fastUpdate.sh` sau khi đã duyệt bản phát hành; script tăng versionCode, build, kiểm tra phiên bản/chữ ký bên trong APK, rồi cập nhật APK và `latest.json`. Nếu tự thay file, phải kiểm tra `versionName`/`versionCode` bên trong APK khớp `latest.json`; chỉ sửa `latest.json` sẽ khiến Android tải lại APK cũ và báo đã cài.

## Quy tắc phiên bản

- Nhãn phát hành dùng `YYMMDD.N` theo múi giờ Việt Nam, ví dụ `260919.1`. Android `versionCode` luôn tăng; bản hiện tại dùng `26091901`.
- Chỉnh sửa mã nguồn và push GitHub không tự phát hành APK hay tăng phiên bản. Chỉ chạy `fastUpdate.sh` khi có yêu cầu phát hành.
- Trước khi công bố Update, kiểm tra `versionName`/`versionCode` **bên trong APK** khớp với `backend/releases/latest.json`, và APK có cùng application ID, chữ ký với bản đang cài. Không sửa nội dung APK của một phiên bản đã công bố; mỗi APK thay đổi phải có versionCode mới.

## Dữ liệu cần giữ khi cập nhật

Backend sử dụng `backend/server-data/accounts.json`, `backend/server-data/checkins.json`, `backend/server-data/albums.json` và toàn bộ `backend/user/Picture/`. Các file/thư mục này bị Git bỏ qua và **không được xóa khi dọn hoặc cập nhật mã nguồn**. Giữ `backend/releases/latest.json` và APK trong `backend/releases/` nếu tiếp tục dùng Update. Ảnh/check-in cục bộ trên điện thoại nằm trong dữ liệu của ứng dụng Android, không nằm trong thư mục mã nguồn. Chức năng Update chỉ cài APK khi có bản phát hành mới trên backend.

## Kiểm tra quyền riêng tư

Xem [báo cáo rà soát và giới hạn kiểm chứng](docs/privacy-review.md). Android không sao lưu dữ liệu riêng tư qua Auto Backup hoặc chuyển thiết bị tự động; dùng backup mã hóa trong app để tự chuyển dữ liệu. Album ZIP vẫn chứa ảnh, địa điểm, ghi chú và ngày do người dùng chủ động chia sẻ, nhưng không chứa đường dẫn lưu trữ nội bộ.
