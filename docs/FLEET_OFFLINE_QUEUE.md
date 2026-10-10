# Lưu và đồng bộ lịch sử hành trình

Chỉ thu GPS khi người dùng bấm **Start trip**. Lưu điểm đầu tiên khi GPS hợp
lệ; các điểm sau cách nhau ít nhất **1 phút** và cách điểm đã lưu trước
**hơn 100 m**, cả online lẫn offline. Trạng thái xe trực tiếp vẫn cập nhật tối
đa 30 giây/lần, độc lập với lịch sử.

## Dữ liệu đi đâu?

1. Lưu hồ sơ bắt đầu chuyến/điểm/kết thúc chuyến vào SQLite riêng của app.
2. Khi có Internet, Android thử gửi theo thứ tự bằng HTTPS và ID token tài xế.
3. Chỉ xóa bản chờ sau ACK server hoặc đọc lại thấy đúng ID và đúng dữ liệu.
4. Lịch sử trên Firebase không bị xóa; dashboard tiếp tục xem được.

Không tải lịch sử mới qua cache Firestore SDK. SDK vẫn giữ cache phân công
xe, trạng thái trực tiếp và các lệnh ghi cũ để không mất dữ liệu khi nâng cấp.
Không có service-account key/token trong hàng đợi; Security Rules cũ vẫn áp
dụng. Hàng đợi tách theo UID, không ghi tọa độ/token vào log và không backup
tự động. SQLite bật secure delete và tự thu hồi trang trống sau khi xóa.

Lỗi mạng/server/mất quyền xe không được làm mất bản chờ. Khôi phục quyền xe
rồi dùng **Retry sync** nếu bị từ chối. App chặn đăng xuất/xóa dữ liệu khi còn
bản chờ. Gỡ app hoặc xóa dữ liệu qua Android vẫn làm mất điểm chưa sync.
Android Doze có thể trì hoãn đồng bộ; Force stop cần mở app lại. Việc mở lại
app/khởi động máy chỉ thử đồng bộ, không tự bật GPS hay bắt đầu chuyến mới.

## Kiểm thử

Trong `App`:

```sh
flutter analyze
flutter test
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

Trong repo `FireBase/Fleet_Management`: `npm run test:rules`.

Đã kiểm thử trên máy tính: nhịp 1 phút và ngưỡng >100 m, SQLite đóng/mở lại,
tách tài khoản, chỉ xóa từng bản sau ACK, lỗi/redirect/mất ACK, chống trùng
điểm, không mở lại chuyến đã kết thúc. Firestore Emulator kiểm chứng định
dạng REST và Security Rules, không ghi dữ liệu thử vào project thật.

Trên điện thoại Android 16 đã kiểm tra SQLite thật bằng database thử riêng:
lưu offline → đóng/mở lại → giữ bản khi thiếu ACK → xóa khi ACK; không bật
GPS, không đổi mạng và không ghi Firebase thật. Chưa chạy chuyến GPS thật
1 phút/lần hoặc kiểm tra Doze/reboot với bản này.

### An toàn khi chạy kiểm thử trên điện thoại đang sử dụng

**Phải End trip, sao lưu dữ liệu và kiểm tra đúng hồ sơ cá nhân trước.**
`connectedDebugAndroidTest` từng tự gỡ cả app chính sau khi chạy; lần kiểm thử
này đã làm mất dữ liệu cục bộ. App chính đã được cài lại, nhưng không tìm thấy
bản sao để khôi phục cấu hình cũ. Lịch sử Firebase không bị sửa/xóa.

`android/gradle.properties` đã đặt
`android.injected.androidTest.leaveApksInstalledAfterRun=true` để chặn bước
tự gỡ sau kiểm thử. Không dùng thao tác gỡ app/clear data để sửa lỗi cài đặt.
Nếu chạy thủ công, chỉ cài đè vào user cá nhân bằng `adb install --user 0 -r`,
không cài APK test thay APK app chính. APK dùng hằng ngày là
`App/build/app/outputs/apk/debug/app-debug.apk`; APK `androidTest` chỉ để kiểm
thử, không có giao diện NavRide. Ưu tiên emulator/thiết bị test riêng.
