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

## 5. Release Android phải chặn HTTP cleartext

Trong Android release, nên để:

```kotlin
manifestPlaceholders["usesCleartextTraffic"] = "false"
```

Debug có thể dùng HTTP local để test:

```kotlin
manifestPlaceholders["usesCleartextTraffic"] = "true"
```

Kinh nghiệm: nếu release APK cần sync backend thật, hãy dùng HTTPS. HTTP local chỉ
nên dùng cho debug/test trong mạng LAN.

## 6. APK release phải được ký

Lỗi signature thường có 3 nguyên nhân:

- APK release chưa ký.
- APK mới ký bằng key khác APK đang cài trên điện thoại.
- Version mới có `versionCode` không tăng.

Kiểm tra APK có ký đúng không:

```bash
/home/thanhhao/.local/share/android-sdk/build-tools/36.0.0/apksigner verify \
  --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
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

## 8. Khi update phiên bản phải tăng version

Trong `pubspec.yaml`:

```yaml
version: 1.0.1+2
```

Trong đó:

- `1.0.1` là `versionName`.
- `2` là `versionCode`.

Mỗi lần phát hành APK update, `versionCode` phải tăng. Nếu không tăng, Android
hoặc hệ thống update có thể không nhận là bản mới.

## 9. Manifest update phải trỏ đúng APK

File:

```text
backend/releases/latest.json
```

Ví dụ:

```json
{
  "versionName": "1.0.1",
  "versionCode": 2,
  "apkFile": "task_reminder.apk",
  "notes": "New app icon, no-priority tasks, and monthly multi-day scheduling."
}
```

Sau khi build:

```bash
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk backend/releases/task_reminder.apk
```

Tên `apkFile` trong JSON phải khớp với file thật trong `backend/releases/`.

## 10. Checklist trước khi nói app đã ổn

Chạy tối thiểu:

```bash
flutter analyze
flutter test
flutter build web
flutter build apk --release
```

Kiểm tra APK:

```bash
/home/thanhhao/.local/share/android-sdk/build-tools/36.0.0/apksigner verify \
  --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
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

## 11. Khi đổi icon app

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

## 12. Kinh nghiệm xử lý lỗi thường gặp

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

## 13. Nguyên tắc làm feature cho app cá nhân

- Ưu tiên offline-first.
- Không bắt người dùng nhập backend URL khi không sync.
- UI system text nên thống nhất một ngôn ngữ, ví dụ English.
- Nội dung task người dùng nhập vẫn phải hỗ trợ tiếng Việt.
- Mỗi feature mới nên có test cho logic và test cho thao tác chính trên mobile
  width.
- Sau khi sửa release/security/signing, luôn build APK thật và verify chữ ký.

