# VietNam Map Checkin

## Gioi Thieu Co Ban

VietNam Map Checkin la ung dung Flutter dung de luu ky niem du lich tren ban do
Viet Nam. Ung dung cho phep tao check-in theo tinh/thanh, them dia diem, ghi
chu, ngay gio, anh, diem danh gia, tag, yeu thich, xem lich su, thong ke,
sao luu/khoi phuc du lieu va dong bo qua backend Node.js noi bo.

Ung dung uu tien luu du lieu cuc bo truoc. Backend chi can khi muon dong bo du
lieu, luu anh tren may tinh, hoac cho dien thoai kiem tra ban cap nhat APK qua
LAN.

## Tao APK

Lay dependency:

```bash
cd /home/thanhhao/thanhhao/Github/App/VietNam-map-checkin
flutter pub get
```

Build APK release cho dien thoai Android:

```bash
flutter build apk --release --target-platform android-arm64
```

File APK sau khi build:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Chay Tren Web

Chay ban web preview:

```bash
cd /home/thanhhao/thanhhao/Github/App/VietNam-map-checkin
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Mo tren may tinh:

```text
http://127.0.0.1:8080
```

Mo tu dien thoai hoac may khac cung Wi-Fi:

```text
http://<PC_LAN_IP>:8080
```

Build web release:

```bash
flutter build web --release
```

Thu muc web sau khi build:

```text
build/web
```

## Cap Nhat Phien Ban Moi Nhat Va Check Update Qua LAN

Cach nhanh tren Linux:

```bash
chmod +x fastUpdate.sh
./fastUpdate.sh
```

Script se tu tang version, chay test/analyzer, build APK ARM64, cap nhat
`backend/releases/latest.json`, mo backend va kiem tra endpoint update. Dung
`./fastUpdate.sh --help` de xem tuy chon version, port va ghi chu cap nhat.

Tang version trong `pubspec.yaml`, vi du:

```yaml
version: 1.1.4+26
```

Build APK moi:

```bash
flutter build apk --release --target-platform android-arm64
```

Copy APK moi vao backend release:

```bash
cp build/app/outputs/flutter-apk/app-release.apk backend/releases/app-release.apk
```

Sua `backend/releases/latest.json` cho khop version moi:

```json
{
  "versionName": "1.1.4",
  "versionCode": 26,
  "apkFile": "app-release.apk",
  "notes": "Mo ta noi dung cap nhat."
}
```

Chay backend tren may tinh:

```bash
npm install
npm run backend
```

Lay IP LAN cua may tinh:

```bash
hostname -I
```

Tren dien thoai, vao app va dat Backend URL theo dang:

```text
http://<PC_LAN_IP>:3000
```

Vi du minh hoa:

```text
http://192.168.x.x:3000
```

Endpoint de app kiem tra update:

```text
http://<PC_LAN_IP>:3000/api/update/latest
```

File APK duoc tai tu:

```text
http://<PC_LAN_IP>:3000/releases/app-release.apk
```

Luu y: khong dung `127.0.0.1` tren dien thoai, vi dia chi do tro ve chinh dien
thoai chu khong phai may tinh dang chay backend.
