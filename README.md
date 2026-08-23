# Money Manager

## Giới thiệu cơ bản

Money Manager là ứng dụng Flutter để theo dõi thu nhập, chi tiêu và các khoản
chi định kỳ. Ứng dụng có backend Node.js cục bộ để đồng bộ dữ liệu và phân phối
APK cập nhật trong cùng mạng LAN.

Backend mặc định chạy ở cổng `3002`; điện thoại và máy chạy backend phải cùng
một mạng LAN khi đồng bộ hoặc kiểm tra bản cập nhật.

## Tạo APK

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
npm install
npm start
```

Terminal 2 — chạy web:

```bash
flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Mở `http://localhost:8080` trên máy chạy app, hoặc
`http://<IP-LAN-MAY-CHAY>:8080` từ thiết bị cùng mạng. Trong màn hình đăng nhập
hoặc Account, đặt **Backend URL** thành:

```text
http://<IP-LAN-MAY-CHAY>:3002
```

Trên Linux, dùng `hostname -I` để xem IP LAN của máy chạy backend.

Kiểm tra backend đã sẵn sàng:

```bash
curl http://<IP-LAN-MAY-CHAY>:3002/api/health
```

## Cập nhật ứng dụng và kiểm tra qua LAN

Chạy lệnh sau tại thư mục gốc dự án:

```bash
./fastUpdate.sh --notes "Cải thiện giao diện và sửa lỗi"
```

Script sẽ tự động:

- tạo phiên bản hiển thị theo `YYMMDD.N`, ví dụ `260823.1`;
- tăng `versionCode`, tạo APK debug và publish APK/manifest vào backend;
- kiểm tra format, analyzer, test Flutter và cú pháp backend;
- mở hoặc dùng lại backend ở cổng `3002`, rồi in Backend URL cho thiết bị LAN.

Sau khi script hoàn tất, trên điện thoại cùng mạng LAN: mở tab **Account**, lưu
Backend URL được script in ra và chọn **Check for update**. Có thể đổi port
bằng `./fastUpdate.sh --port 3003` hoặc chỉ xem phiên bản dự kiến bằng
`./fastUpdate.sh --dry-run`.

Tính năng tải và cài APK chỉ hoạt động trên Android. APK debug chỉ cài đè được
lên ứng dụng đã cài bằng cùng khóa debug; không thể cập nhật APK gốc đã khôi
phục nếu không có khóa ký gốc.
