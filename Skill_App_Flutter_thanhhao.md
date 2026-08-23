# Skill App Flutter Thanhhao

Ghi chú kinh nghiệm khi làm app Flutter để build được, cài được, chạy ổn trên
web và điện thoại. File này viết từ kinh nghiệm thực tế với project
`task-reminder`.

## 1. Luôn làm từ đúng thư mục gốc Flutter

Thư mục gốc của app này:

```bash
cd /home/thanhhao/thanhhao/Github/App/task-reminder
```

Nếu đang đứng trong `backend/` mà chạy `flutter build apk --release`, Flutter có
thể tự đổi về thư mục gốc. Đây không phải lỗi, nhưng dễ làm mình nhầm output.

Kiểm tra nhanh:

```bash
pwd
flutter pub get
flutter analyze
flutter test
```

## 2. App nên chạy offline trước, backend chỉ dùng để sync

Với app cá nhân như task/reminder/money/check-in, nên thiết kế:

- Đăng nhập local được dù không có backend URL.
- Dữ liệu chính lưu local trước.
- Backend URL chỉ cần khi bấm Sync, Check update, hoặc tải APK.
- Không bắt điện thoại phải chung mạng với máy tính database nếu người dùng chỉ
  muốn thêm/sửa task offline.

Trong `task-reminder`, dữ liệu local dùng `SharedPreferences`:

- `task-reminder-tasks-v1`
- `task-reminder-assignments-v1`
- `task-reminder-backend-url`
- `task-reminder-auth-user`
- `task-reminder-auth-password`

## 3. Chạy preview web đúng cách

Chạy web preview:

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8081
```

Mở bằng IP LAN của máy:

```text
http://192.168.x.x:8081/
```

Lấy IP hiện tại:

```bash
hostname -I | awk '{print $1}'
```

Nếu `127.0.0.1:8081` không hoạt động nhưng IP LAN hoạt động thì không vội sửa
app. Hãy kiểm tra bằng:

```bash
curl -I http://192.168.x.x:8081/
```

Khi đổi mạng Wi-Fi, IP có thể đổi. README, backend `ALLOWED_ORIGINS`, và Backend
URL trong app có thể cần cập nhật theo IP mới.

## 4. Backend chỉ mở đúng origin khi test web

Khi chạy backend để sync/update:

```bash
cd backend
npm install
ALLOWED_ORIGINS=http://192.168.x.x:8081 npm start
```

Không nên để CORS mở quá rộng khi release. Nếu app web đổi port hoặc IP, backend
cần đổi `ALLOWED_ORIGINS` theo.

## 5. HTTP trong Android release phải chọn theo mục tiêu

Nếu release production thật và backend có đăng nhập/mật khẩu, nên dùng HTTPS và
chặn HTTP cleartext:

```kotlin
manifestPlaceholders["usesCleartextTraffic"] = "false"
```

Nếu app cần cập nhật qua backend local dạng `http://192.168.x.x:3002`, Android
release phải cho phép HTTP:

```kotlin
manifestPlaceholders["usesCleartextTraffic"] = "true"
```

Kinh nghiệm với `task-reminder`: app cá nhân chạy backend local để sync/update
APK trong mạng LAN thì có thể bật `usesCleartextTraffic=true` cho release. Nhưng
nếu đưa ra môi trường production hoặc server public, phải chuyển sang HTTPS vì
header `X-Password` có chứa mật khẩu.

## 6. APK release phải được ký

Lỗi signature thường có 3 nguyên nhân:

- APK release chưa ký.
- APK mới ký bằng key khác APK đang cài trên điện thoại.
- Version mới có `versionCode` không tăng.

Kiểm tra APK có ký đúng không:

```bash
/home/thanhhao/.local/share/android-sdk/build-tools/36.0.0/apksigner verify \
  --verbose --print-certs build/app/outputs/flutter-apk/app-release-task-reminder.apk
```

Kết quả tốt cần có:

```text
Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
Number of signers: 1
```

Nếu chỉ dùng `jarsigner`, có thể thấy `jar is unsigned` dù APK đã ký v2. Với APK
Android hiện đại, ưu tiên kiểm tra bằng `apksigner`.

## 7. Không commit keystore và password

File local để ký APK:

```text
android/key.properties
```

File này phải nằm trong `.gitignore`. Không commit:

- `android/key.properties`
- `*.jks`
- `*.keystore`
- APK release trong `backend/releases/*.apk`

Ví dụ `android/key.properties` local khi test bằng debug keystore:

```properties
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=/home/thanhhao/.android/debug.keystore
```

Bản này chỉ phù hợp test/cài đè nếu APK cũ cũng dùng cùng debug key. Khi release
thật, cần tạo release keystore riêng và giữ nó cố định.

## 8. Không tự update version khi chưa được yêu cầu

Nguyên tắc quan trọng: chỉ tăng version, build APK release, và cập nhật
`backend/releases/latest.json` khi người dùng yêu cầu rõ ràng như:

- "cập nhật phiên bản mới"
- "build APK mới"
- "mở backend để cập nhật qua app"
- "release bản mới"

Nếu người dùng chỉ yêu cầu sửa UI, sửa bug, kiểm tra chức năng, hoặc push source
code thì không tự tăng `pubspec.yaml`, không tự sửa `latest.json`, và không tự
tạo APK release. Có thể chạy:

```bash
flutter analyze
flutter test
flutter build web
```

nhưng phải để version/release giữ nguyên cho tới khi có yêu cầu cập nhật.

## 9. Quy tắc đặt tên phiên bản release

Chỉ khi người dùng yêu cầu release/update APK, dùng nhãn phiên bản hiển thị:

```text
YYMMDD.N
```

- `YYMMDD` là ngày phát hành theo múi giờ `Asia/Ho_Chi_Minh`.
- `N` là số lần phát hành trong ngày, bắt đầu từ `1`, tăng thêm `1` cho mỗi
  release thật và trở lại `1` khi sang ngày mới.
- Không tăng `N` cho preview, test, hoặc chỉ sửa source/UI.

Ví dụ: release đầu tiên ngày 2026-08-23 là `260823.1`; release thứ hai cùng
ngày là `260823.2`.

Flutter yêu cầu `pubspec.yaml` dùng semantic version có ba phần số, nên không
ghi trực tiếp `version: 260823.1+...`. Với Android, truyền đúng nhãn hiển thị
qua `--build-name` và giữ `versionCode` là số nguyên tăng liên tục, ví dụ:

```bash
flutter build apk --release --build-name=260823.1 --build-number=26082301
```

Nếu cần đồng bộ metadata trong `pubspec.yaml`, dùng dạng hợp lệ như
`260823.1.0+26082301`; manifest update vẫn dùng `versionName: "260823.1"` và
`versionCode: 26082301`.

Trước khi nói update trong app hoạt động, kiểm tra client đang so sánh đúng
`versionName`/`versionCode` hiện tại, không dùng hằng số cũ bị hard-code.

## 10. Cập nhật fastUpdate.sh trước khi dùng format mới

Trong `task-reminder` đã có script:

```bash
./fastUpdate.sh
```

Hiện tại script này theo quy tắc cũ: tăng patch `x.y.z` và chỉ nhận
`VERSION_NAME` dạng ba phần. Vì vậy không dùng `./fastUpdate.sh` cho format
`YYMMDD.N` cho đến khi script được sửa và kiểm tra trong một yêu cầu release
riêng.

Khi script đã tương thích, nó cần tự động:

- Tạo nhãn `YYMMDD.N` và tăng `versionCode`.
- Cập nhật `backend/releases/latest.json`.
- Chạy `flutter pub get`.
- Chạy `dart format --set-exit-if-changed lib test`.
- Chạy `flutter analyze`.
- Chạy `flutter test`.
- Chạy backend check: `node --check server.js` và `npm test`.
- Build web.
- Build APK release bằng `tools/build_release_apk.sh`.
- Copy APK vào `backend/releases/app-release-task-reminder.apk`.
- Kiểm tra manifest và APK tồn tại.

Sau khi script đã được cập nhật và kiểm tra cho format `YYMMDD.N`, có thể thêm
`--serve` để mở backend sau khi build:

```bash
./fastUpdate.sh --serve
```

Nếu backend đã chạy trên port `3002`, `--serve` chỉ báo lại URL update thay vì
crash vì trùng port.

Không chạy `./fastUpdate.sh` khi chỉ đang sửa UI hoặc kiểm tra chức năng, vì script
sẽ tự tăng version và tạo APK release.

## 11. Manifest update phải trỏ đúng APK

File:

```text
backend/releases/latest.json
```

Ví dụ:

```json
{
  "versionName": "260823.1",
  "versionCode": 26082301,
  "apkFile": "app-release-task-reminder.apk",
  "notes": "New app icon, no-priority tasks, and monthly multi-day scheduling."
}
```

Sau khi build:

```bash
./tools/build_release_apk.sh
```

Tên `apkFile` trong JSON phải khớp với file thật trong `backend/releases/`.

Kiểm tra endpoint:

```bash
curl http://192.168.x.x:3002/api/update/latest
curl -I http://192.168.x.x:3002/releases/app-release-task-reminder.apk
```

Kết quả tốt: endpoint JSON trả `versionName`, `versionCode`, `apkUrl`; link APK
trả `HTTP 200`.

## 12. Checklist trước khi nói app đã ổn

Chạy tối thiểu:

```bash
flutter analyze
flutter test
flutter build web
```

Chỉ khi đang release/update APK mới chạy:

```bash
./tools/build_release_apk.sh
```

Chỉ dùng script tự động sau khi nó đã hỗ trợ format `YYMMDD.N`:

```bash
./fastUpdate.sh
```

Kiểm tra APK khi có build release:

```bash
/home/thanhhao/.local/share/android-sdk/build-tools/36.0.0/apksigner verify \
  --verbose --print-certs build/app/outputs/flutter-apk/app-release-task-reminder.apk
```

Kiểm tra web preview:

```bash
curl -I http://192.168.x.x:8081/
```

Kiểm tra git:

```bash
git status --short
git diff --check
```

Nếu có backend:

```bash
cd backend
node --check server.js
npm test
```

## 13. Khi đổi icon app

Icon Android launcher nằm ở:

```text
android/app/src/main/res/mipmap-*/ic_launcher.png
```

Icon web/PWA nằm ở:

```text
web/favicon.png
web/icons/Icon-192.png
web/icons/Icon-512.png
web/icons/Icon-maskable-192.png
web/icons/Icon-maskable-512.png
web/manifest.json
```

Nên giữ một file master để tái xuất kích thước:

```text
assets/branding/app_icon.png
```

Sau khi đổi icon, phải build lại APK release. Cài APK cũ sẽ không tự đổi icon nếu
chưa cài bản mới thành công.

## 14. Kinh nghiệm UI mobile và popup

- Không gom nhiều option vào một nút nếu người dùng cần bật/tắt từng tính năng.
  Với Add Task, các nhóm như `Icon`, `Priority`, `Schedule` nên có switch riêng.
- Khi tắt `Priority`, lưu task dạng `No priority` và không set reminder time.
- Khi tắt `Schedule`, xóa lịch đang chọn để tránh tạo assignment ngoài ý muốn.
- Các chip trên mobile nên dùng chữ ngắn: ví dụ `15m` thay vì `15p`, `Reminder`
  thay vì `Reminder time`.
- Không ép dialog bằng `SizedBox(width: 560)` trên mobile; dùng
  `ConstrainedBox(maxWidth: 560)` để dialog co theo màn hình.
- Header có title + trailing button dễ overflow ở width 390px; dùng
  `LayoutBuilder` để trailing xuống dòng khi không đủ rộng.
- Mỗi lần chỉnh popup nên thêm widget test ở phone size, ví dụ `390x844`, mở
  popup và bật các option chính rồi kiểm tra `tester.takeException()`.

## 15. Kinh nghiệm xử lý lỗi thường gặp

### Flutter warning Java restricted method

Các dòng như sau thường chỉ là warning Gradle/JDK:

```text
WARNING: A restricted method in java.lang.System has been called
```

Nếu cuối log có:

```text
Built build/app/outputs/flutter-apk/app-release.apk
```

thì build vẫn thành công.

### Signature mismatch khi cài APK

Cách xử lý:

1. Kiểm tra APK mới đã ký bằng `apksigner`.
2. Nếu APK cũ trên điện thoại ký bằng key khác, phải gỡ app cũ rồi cài lại.
3. Nếu muốn update không mất data, phải ký APK mới bằng đúng keystore của APK cũ.

### Web không mở được bằng IP

Kiểm tra:

1. Đúng port chưa, ví dụ `8081`.
2. Đúng IP hiện tại chưa.
3. Flutter web-server có chạy với `--web-hostname 0.0.0.0` không.
4. Tường lửa/router có chặn thiết bị khác trong LAN không.

## 16. Nguyên tắc làm feature cho app cá nhân

- Ưu tiên offline-first.
- Không bắt người dùng nhập backend URL khi không sync.
- Không tự update version/release/APK nếu người dùng chưa yêu cầu.
- UI system text nên thống nhất một ngôn ngữ, ví dụ English.
- Nội dung task người dùng nhập vẫn phải hỗ trợ tiếng Việt.
- Mỗi feature mới nên có test cho logic và test cho thao tác chính trên mobile
  width.
- Sau khi sửa release/security/signing, luôn build APK thật và verify chữ ký.
