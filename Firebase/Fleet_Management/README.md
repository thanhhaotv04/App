# NavRide Fleet Management — nền tảng Firebase

Thư mục này chứa cấu hình Firebase backend và quy tắc truy cập cho bản thử
nghiệm ESP32-NavRide Fleet. Project `navride-96851` đã bật Authentication
(Email/Password), tạo Cloud Firestore và triển khai rules/dashboard.
Tài xế chỉ bắt đầu gửi vị trí sau khi được gán xe, bật `Share with Fleet` và
bấm `Start ride` trong app.
Không lưu mật khẩu hay service-account key ở đây.

Đã kiểm thử trên điện thoại thật ngày 09/10/2026: `Start trip` tạo và cập nhật
`fleets/demo/vehicles/bike-01/status/current`; `End trip` ghi
`tripActive: false` và xóa tọa độ/tốc độ khỏi trạng thái hiện tại. Không ghi
lại tọa độ thử nghiệm vào repo hoặc tài liệu.

## Dữ liệu đi theo đường nào?

```text
OsmAnd + phone GPS → Android ESP32-NavRide app → BLE → ESP32 display
                              │
                              └─ mobile data/Wi-Fi → Firebase → manager web app
```

ESP32-S3 hiện nhận chỉ đường và tốc độ cục bộ từ điện thoại; bo chưa có nguồn
GPS riêng hoặc kết nối Firebase. Vì vậy Firebase kết nối với **điện thoại**,
không kết nối trực tiếp ESP32. Chỉ đường BLE vẫn hoạt động khi không có Wi-Fi
hay dữ liệu di động. Khi điện thoại mất Internet, quản lý chỉ thấy dữ liệu cũ
và thời điểm cập nhật, không được báo sai là xe đang online.

`Trips` trong app có `Share with Fleet` và `Start ride / End ride`. Chỉ khi tài
xế đăng nhập, được gán xe, bật chia sẻ và bấm `Start ride`, dịch vụ vị trí nền mới gửi tọa
độ và tốc độ lên Firestore (nhiều nhất một bản cập nhật mỗi 30 giây). Tọa độ
giả lập, quá cũ hoặc độ chính xác kém hơn 50 m không được tải lên.
Điểm lịch sử đầu tiên được lưu khi có GPS hợp lệ. Các điểm tiếp theo chỉ được
lưu nếu cách điểm trước hơn 100 m và đã qua ít nhất **1 phút**, kể cả khi
offline. Nếu không có Wi-Fi nhưng điện thoại còn 4G/5G, app vẫn có thể đồng bộ.
Điểm và hồ sơ chuyến được ghi vào SQLite riêng của app trước khi tải lên.
Chỉ sau ACK server hoặc xác minh bản ghi đã tồn tại và trùng dữ liệu, app mới
xóa bản chờ; không xóa lịch sử trên Firebase. Đây là ngưỡng phía app để
loại nhiễu GPS, không phải kiểm soát tần suất ở server.

Marker do tài xế chủ động tạo trong chuyến đi bằng điện thoại hoặc `Menu → Marker`
trên ESP32. Có ba loại `Save Point`, `Food`, `Danger`; vị trí lấy từ GPS hợp lệ
của điện thoại và **không** theo ngưỡng 1 phút/100 m của các điểm tự động.
Nếu chọn chụp ảnh trên điện thoại, app nén JPEG tối đa 150 KiB và mã hóa lại
pixel để bỏ EXIF/GPS. Metadata ở `vehicles/{vehicleId}/markers/{markerId}`;
ảnh riêng ở `markers/{markerId}/photos/image`, chỉ tải khi người dùng mở ảnh
trên dashboard. Cả marker và ảnh được xếp hàng offline; xóa bản chờ sau khi
server xác nhận. Quyền đọc chỉ cấp cho tài xế được gán xe và admin duy nhất.
Ảnh nằm trong Firestore để bản thử không phải bật Cloud Storage; số lượng
ảnh vẫn dùng quota Firestore và hàng đợi ảnh offline giới hạn 40 ảnh.

## Bước 1: Tạo Firebase project

1. Vào [Firebase console](https://console.firebase.google.com/), tạo project
   mới. Bản thử ít xe có thể bắt đầu bằng gói Spark. Ghi lại **Project ID**;
   không gửi/commit tệp service-account JSON.
2. Đăng ký **Android app** với package ID `com.thanhhao.esp32_navride`.
   Android coi đây là app mới, không tự giữ dữ liệu từ app cũ
   `com.thanhhao.esp32_monitor`. Nếu đã đăng ký ID cũ trong Firebase, hãy
   thêm một Android app mới vào **cùng Firebase project** với ID mới; không
   sửa nhãn hiển thị rồi coi như đã đổi package ID.
3. Đăng ký **Web app** cho dashboard; bản này tái sử dụng Web app đã đăng ký
   trong project `navride-96851`.
4. Bật **Authentication → Email/Password**, tạo một tài khoản quản lý và một
   tài khoản tài xế để thử. Bật **Cloud Firestore**; chọn vùng đặt database
   cẩn thận vì muốn đổi vùng về sau phải di chuyển dữ liệu.
5. Chọn **production mode**, không dùng luật test mở công khai kiểu
   `allow read, write: if true`.

## Bước 2: Thử quy tắc bảo mật trên máy

Yêu cầu Node.js 22 trở lên, Java và npm. Sau khi clone repo NavRide, chạy
trong `Firebase/Fleet_Management` (bản làm việc trên máy này cũng có tại
`/home/thanhhao/thanhhao/Github/FireBase/Fleet_Management`):

```bash
cd Firebase/Fleet_Management
npm ci
npm run test:rules
```

Lệnh test chạy Firestore Emulator với project giả `demo-navride-fleet`. Phải
qua test trước khi triển khai. Emulator chỉ nghe `127.0.0.1:8080`, không phải
database thật. Các gói Node ở đây chỉ dùng để thử/triển khai, không nhúng vào
app hay firmware; chạy `npm audit` và xem cảnh báo trước mỗi lần triển khai.

## Bước 3: Triển khai rules lên project thật

Sau khi thay `YOUR_PROJECT_ID` bằng ID của bạn và tự xem lại rules:

```bash
./node_modules/.bin/firebase login:add
./node_modules/.bin/firebase projects:list
./node_modules/.bin/firebase deploy --only firestore:rules --project navride-96851
```

Lệnh deploy **ghi đè rules hiện tại** của project; chỉ chạy lại sau khi sửa
rules và kiểm thử.
File `firestore.rules` khóa toàn bộ đường dẫn không được nêu rõ. Chỉ deploy
khi `projects:list` nhìn thấy đúng `navride-96851`.

## Bước 4: Quản trị viên duy nhất và phân công xe

Chỉ **thanhhao.admin@gmail.com**, đúng UID tại `system/access.adminUid` và
đã xác minh email, mới có quyền quản trị toàn bộ xe. Email đơn thuần hoặc
trường `role: "admin"` trong một fleet **không cấp quyền admin**. Không lưu
mật khẩu trong code. Tài khoản admin đã được chuẩn bị bằng mật khẩu ngẫu
nhiên không công khai; dùng email đặt lại mật khẩu để tự đặt mật khẩu mạnh.
Nếu cần, dashboard có `Forgot password?`, `Send verification email` và
`I have verified my email`.

Script dành cho người có IAM/Firebase CLI của project (không chạy trên web):

```bash
node scripts/admin-setup.cjs                         # chỉ kiểm tra
node scripts/admin-setup.cjs --apply                 # tạo/cấu hình nếu thiếu
node scripts/admin-setup.cjs --send-setup-email      # gửi email đặt mật khẩu
```

Script không thay admin UID đã có bằng UID khác, không in token/mật khẩu.
Khách web/app không được sửa `system/access`, kể cả admin đăng nhập web.

Sau khi đăng nhập admin, mở **Fleet administration**:

- **Save driver**: nhập Fleet ID, UID từ Firebase Authentication, tên tài xế.
- **Save vehicle**: tạo/sửa tên xe, gán tài xế hoặc để trống để chưa phân công.
- **View route**: mở lịch sử của xe, kể cả xe đã Archive.
- **Archive / Restore**: ngừng/khôi phục quyền cloud của xe; giữ toàn bộ lịch sử.
- **Remove access**: thu hồi quyền tài xế trong fleet; không xóa xe/chuyến.

Tạo tài khoản tài xế mới trong Firebase Authentication trước rồi sao chép UID.
Dashboard không có quyền tạo/xóa tài khoản Authentication hay cấp thêm admin.
Thay tài xế có hộp xác nhận: người mới được xem lịch sử đi theo xe, người cũ
mất quyền. Archive hoặc đổi tài xế xóa tọa độ trong **status hiện tại**, không
xóa `trips`/`track_points`. Các thao tác này không điều khiển GPS/BLE trên
điện thoại từ xa; tài xế nên bấm `End ride` khi ngừng sử dụng.

Không có nút xóa vĩnh viễn xe hoặc chuyến hợp lệ. Ngoại lệ: khi admin đăng
nhập, dashboard dọn chuyến đã kết thúc có dưới 2 điểm GPS, giữ marker/ảnh.
Việc xóa Authentication hoặc toàn bộ lịch sử cần quy trình riêng trên
Console/backend tin cậy, không chỉ xóa document xe rồi bỏ lại subcollection.

Trong Firebase console, tạo các document sau. Dùng **UID trong Firebase
Authentication**, không dùng email, làm ID tài liệu thành viên:

```text
fleets/demo                       { name: "Demo fleet" }
system/access                    { adminUid: "SINGLE_ADMIN_UID" }
fleets/demo/members/DRIVER_UID    { role: "driver", displayName: "Driver" }
fleets/demo/vehicles/bike-01      { label: "Bike 01", driverUid: "DRIVER_UID", archived: false }
```

Tài xế không được tạo/sửa thành viên hoặc gán xe. Chỉ admin duy nhất có các
quyền đó trên dashboard; Firestore rules kiểm tra lại từng thao tác.

App của tài xế được gán xe chỉ có quyền ghi
`fleets/demo/vehicles/bike-01/status/current` với đúng các trường
`latitude`, `longitude`, `speedKmh` (số hoặc null), `tripActive`, `capturedAt`
(lúc GPS ghi nhận) và `updatedAt` (lúc server nhận). Khi `tripActive: false`,
tọa độ, tốc độ và `capturedAt` đều là `null`. Dashboard dùng `capturedAt` để
không báo vị trí cũ là mới sau khi đồng bộ trễ. Chỉ tài xế đó và quản lý đội
xe được đọc.
Không lưu thông báo cá nhân, ảnh QR, mật khẩu Wi-Fi hoặc PIN BLE ở đây.
Các điểm lịch sử nằm ở
`fleets/demo/vehicles/bike-01/track_points/{pointId}`; mỗi điểm có vị trí,
độ chính xác, tốc độ, `tripId`, lúc ghi nhận và lúc server nhận. Rules chỉ cho
tài xế được gán xe tạo điểm mới; điểm cũ không thể sửa/xóa từ app. Tài xế
được gán xe đang hoạt động và admin duy nhất được đọc lịch sử của xe đó.
Mỗi chuyến có thêm `fleets/demo/vehicles/bike-01/trips/{tripId}` với
`driverUid`, `startedAt`, `endedAt`, `updatedAt`. Hồ sơ tạo lúc bấm `Start
ride` với Fleet bật, đánh dấu kết thúc khi bấm `End ride`, kể cả khi không có điểm GPS đủ
chính xác. Lệnh ghi hồ sơ cũng được giữ offline rồi đồng bộ sau.

## Bước 5: Chạy app và gửi dữ liệu

Trong `App`, chạy `flutter run -d <Android-device-id>` hoặc cài bản APK mới.
Mở `Settings → Fleet account`, đăng nhập tài khoản tài xế đã tạo trong
Authentication, nhập `Fleet ID` (`demo`) và `Vehicle ID` (`bike-01`). Trong
`Trips`, bật `Share with Fleet` rồi bấm `Start ride`. Bật Location và cấp vị
trí chính xác khi Android hỏi. App kiểm
tra phân công xe trên server trước khi bắt đầu. Khi offline, app chỉ cho bắt
đầu nếu trước đó đã tải phân công đúng tài khoản về cache; điện thoại mới cần
lên mạng một lần để xác minh. Tài khoản chưa được gán xe không gửi tọa độ.
Xem dữ liệu ở **Firestore → Data → fleets → demo →
vehicles → bike-01 → status → current**.

Khi đang chạy, điện thoại lấy **vị trí GPS mới và đủ chính xác**, tiếp tục
gửi tốc độ/chỉ đường đến ESP32 qua BLE cũ, đồng thời ghi Firestore tối đa 30
giây/lần. `End ride` dừng chia sẻ và ghi `tripActive: false` với tọa độ rỗng.
Điểm của chuyến có ít nhất 2 điểm trong `track_points` **vẫn còn** để xem lại
tuyến; xóa dữ liệu cục bộ trong app cũng không xóa lịch sử trên Firebase.
Chỉ quản trị viên có quyền
trong Firebase Console/server tin cậy mới nên xóa các điểm đó.
Không tải mọi gói tốc độ BLE 1 giây/lần lên Firestore. Nếu mất mạng sau khi
đã bắt đầu, hàng đợi SQLite giữ điểm và hồ sơ chuyến chưa đồng bộ; app hiện
trạng thái offline và số điểm chờ đúng cả sau khi mở lại app. Mất Firebase không được làm ngắt
chỉ đường cục bộ. Không gỡ app/xóa dữ liệu app trước khi đồng bộ xong.

Nếu vẫn theo dõi khi OsmAnd ở phía trước, app cần quyền vị trí và khai báo
foreground location service đúng quy định Android. Giải thích rõ cho tài xế
khi nào theo dõi bắt đầu/kết thúc; không âm thầm khởi động lại sau khi dừng.
`Location` callback giữ tọa độ trong RAM để lọc GPS; điểm hợp lệ được ghi vào
hàng đợi SQLite `fleet-outbox.db`. Điểm lịch sử mới không đi qua SDK cache
Firestore: app gửi HTTPS REST bằng ID token của tài xế, vẫn chịu Security
Rules. ID điểm cố định giúp gửi lại sau mất ACK mà không tạo bản trùng.
Các sự kiện được gửi theo thứ tự bắt đầu chuyến → điểm GPS → kết thúc chuyến.
Hàng đợi phân tách theo UID, không chứa token và được loại khỏi backup Android.
SQLite bật `secure_delete` và `auto_vacuum=FULL` để xóa nội dung ô và thu hồi
trang trống sau ACK; đây không phải cam kết xóa pháp chứng trên bộ nhớ flash.
Android JobScheduler tự thử đồng bộ khi có mạng, kể cả sau khi dịch vụ GPS
dừng hoặc thiết bị khởi động lại. Doze/tiết kiệm pin có thể trì hoãn; nếu Force
stop app, cần mở lại NavRide. Không âm thầm bật lại GPS hoặc chuyến đi.
Mất mạng, lỗi server hoặc mất quyền xe không xóa điểm: app giữ dữ liệu, hiển
thị lỗi và cho `Retry sync`. Cần khôi phục quyền xe để đồng bộ dữ liệu bị từ
chối. Đăng xuất/xóa dữ liệu trong app bị chặn khi còn điểm chờ đồng bộ.
Không gỡ app/xóa dữ liệu bằng Android trước khi đồng bộ xong.
Cache phân công xe, trạng thái trực tiếp và lệnh ghi cũ của Firestore vẫn
được giữ để không mất quyền dùng offline/dữ liệu cũ chưa sync; không tự xóa
toàn bộ cache khi nâng cấp. Trạng thái trực tiếp vẫn dùng SDK Firestore tối
đa 30 giây/lần, độc lập với nhịp lưu lịch sử 1 phút.

## Bước 6: Xem dashboard

Mở [NavRide Fleet Dashboard](https://navride-96851.web.app), đăng nhập bằng
tài khoản tài xế đã gán xe hoặc admin duy nhất. Chọn
`Fleet ID`, xe trong danh sách được phép xem và ngày. Dashboard chỉ hiển thị
chuyến có ít nhất 2 điểm GPS; có thể chọn một chuyến hoặc tất cả. Mốc thời
gian, điểm đã ghi và trạng thái hiện tại nằm cạnh bản đồ. Chỉ các điểm
**trong cùng một trip** được nối thành đường trên bản
đồ OpenStreetMap. Đường nối giữa các điểm không phải toàn bộ đường xe thực sự
đã đi; khoảng cách thời gian giữa hai điểm có thể lớn hơn 1 phút nếu xe
không di chuyển đủ 100 m hoặc GPS không đủ chính xác. Dashboard cần Internet
và chỉ thấy các điểm offline sau khi điện thoại đồng bộ.

Mã nguồn web nằm trong `dashboard/`; triển khai bằng
`./node_modules/.bin/firebase deploy --only hosting --project navride-96851`.
Dashboard dùng quyền Firebase Auth + Firestore rules, không mở công khai dữ
liệu GPS. Phiên đăng nhập chỉ tồn tại trong phiên trình duyệt; trang không
bật cache Firestore lưu lâu trên máy dùng chung. Bản đồ dùng tile công cộng
OpenStreetMap cho thử nghiệm nhỏ, có ghi nguồn và không tải trước tile; khi
quy mô đội xe tăng cần nhà cung cấp tile phù hợp với lưu lượng.

Theo lựa chọn hiện tại, chuyến có từ 2 điểm GPS, marker và ảnh được giữ
vô thời hạn; **không bật Firestore TTL**. Khi admin đăng nhập dashboard và có
mạng, trình duyệt quét các xe/chuyến đã kết thúc trên Firestore, kiểm tra tổng
số điểm của từng chuyến rồi xóa chuyến dưới 2 điểm cùng điểm GPS đơn lẻ.
Marker và ảnh của chuyến đó vẫn được giữ. Nếu admin không mở dashboard thì
không có tác vụ dọn phía server; việc dọn cần giữ trang mở đến khi hoàn tất.
Chuyến đang chạy không bị xóa.
Khi triển khai cho nhiều xe, cần thống nhất quy trình xóa thủ công/theo yêu cầu
và kiểm soát chi phí lưu trữ. Hiện lịch sử đi theo xe:
tài xế được gán mới có quyền xem lịch sử cũ, nhưng không được kết thúc chuyến
hoặc ghi thêm điểm vào chuyến của tài xế trước. Rules bảo vệ quyền đọc/ghi nhưng không thể xác
minh quãng đường hoặc nhịp 1 phút từ GPS của máy khách; đội xe lớn nên dùng
backend tin cậy để kiểm soát tần suất/chi phí.

## Kiểm thử dashboard và giới hạn còn lại

```bash
npm run test:dashboard
npm run test:rules
npx playwright install chromium
npm run test:browser
npm audit --omit=dev
```

Kiểm thử trình duyệt dùng dữ liệu Firebase giả, không ghi/xóa dữ liệu thật.
Kiểm thử rules dùng Emulator: giả mạo admin, chưa xác minh email, phân công
xe, đổi tài xế, thu hồi quyền, Archive/Restore, giới hạn truy vấn, ghi offline.
Giao diện được kiểm tra bàn phím, mất mạng, mất quyền, chuyến qua nửa đêm,
320–1440 px, hai theme và axe WCAG; đây không phải chứng nhận accessibility.

Dashboard giữ tuyến đang xem khi mất mạng, nhưng xóa khỏi màn khi Firebase
báo mất quyền. Mỗi truy vấn bị giới hạn: 200 xe/thành viên, 100 chuyến,
1.000 điểm/ngày; admin có `Load more vehicles` cho danh sách toàn hệ thống.
Không lưu lâu dữ liệu GPS vào bộ nhớ trình duyệt.

App Check đã cấu hình reCAPTCHA Enterprise cho hai miền Hosting và Play Integrity
cho APK cài ngoài Google Play; dashboard/app đã tích hợp SDK, các yêu cầu
Firestore REST từ Android gửi `X-Firebase-AppCheck` khi có token. Firestore và
Authentication hiện ở chế độ **UNENFORCED** (theo dõi): chưa chặn app cũ.
APK debug trên điện thoại thử nghiệm đã đăng ký debug token riêng và đổi được
App Check token hợp lệ; dashboard trên Hosting cũng đổi được token hợp lệ.
Không lưu debug token trong repo hay đóng gói vào APK. Điện thoại debug khác
cần đăng ký token riêng tại **Firebase Console → App Check → Apps → Android →
Manage debug tokens**. Trước khi bật enforce, kiểm tra đăng nhập dashboard,
Fleet sync thực tế và tỷ lệ `Verified` trong **App Check → APIs**; chỉ bật khi
không còn app cũ cần dùng. Bản release hiện ký bằng debug
key, nên phải dùng khóa ký release riêng và đăng ký SHA-256 tương ứng trước khi
phát hành rộng rãi. Mật khẩu mới tối thiểu 12 ký tự; tài khoản cũ vẫn đăng nhập
được để tránh bị khóa, nên cần đổi mật khẩu yếu qua email đặt lại mật khẩu.

Chưa bổ sung billing, MFA trả phí hay Cloud Functions.
Những gói có cảnh báo còn lại từ `npm audit` là công cụ Node phát triển/
triển khai, không được phục vụ bởi Hosting; không chạy `audit fix --force`
làm hạ cấp Firebase. Xem chi tiết kiểm thử trong `KIEM_THU_DASHBOARD.md`.

## Trước khi chạy thử ngoài đường

- Thử với xe và điện thoại đứng yên trước; không thao tác dashboard khi lái xe.
- Xác nhận tài xế B không xem/sửa xe A, người chưa đăng nhập không đọc được,
  tọa độ sai bị từ chối.
- Tắt dữ liệu di động để thử: mũi tên/tốc độ BLE vẫn chạy, dashboard không báo
  sai là vị trí mới.
- Kết thúc chuyến phải dừng GPS và cập nhật từ xa.

Tham khảo: [FlutterFire](https://firebase.google.com/docs/flutter/setup),
[Firestore Rules](https://firebase.google.com/docs/firestore/security/get-started),
[Firebase Emulator](https://firebase.google.com/docs/firestore/security/test-rules-emulator),
[Android location service](https://developer.android.com/develop/background-work/services/fgs/changes).
