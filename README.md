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

### Dong Bo Du Lieu

Ung dung luu check-in va anh cuc bo truoc. Khi backend khong co san, du lieu
van dung duoc va cac check-in chua dong bo se nam trong `Sync queue`.

Khoi dong backend tren may tinh:

```bash
cd /home/thanhhao/thanhhao/Github/App/VietNam-map-checkin
npm install
npm run backend
```

Hoac dung `./fastUpdate.sh`; script se mo backend sau khi build APK.

Kiem tra backend tren may tinh:

```bash
curl http://127.0.0.1:3000/api/health
```

Tren dien thoai hoac may khac cung Wi-Fi:

1. Dang nhap app bang tai khoan cua ban.
2. Mo tab `Sync`.
3. Dat `Backend URL` thanh `http://<PC_LAN_IP>:3000`.
4. Nhan `Sync now`.

Vi du:

```text
http://192.168.x.x:3000
```

Dong bo hai chieu se:

- Tai check-in tu backend ve may hien tai.
- Day check-in cuc bo chua co tren backend len may tinh.
- Gop du lieu theo `check-in id` va giu trang thai `synced`.
- Luu du lieu local theo username dang dang nhap, khong dung chung giua cac tai khoan.
- Gui kem anh dang cho trong may khi day len backend; anh tren backend nam tai
  `user/Picture/<username>/<city>/`.
- Tren Android/desktop anh nam trong thu muc rieng cua username; tren web anh
  offline nam trong bo nho trinh duyet cung username de co the retry upload.
- Khi nhan check-in co anh tu backend, tai mot ban sao ve app de xem offline.
- Neu anh bi doi hoac xoa tren backend, ban local cu cung duoc thay the hoac xoa
  de hai ben hien thi cung mot trang thai.
- Tiep tuc cho phep tao du lieu offline neu Wi-Fi/backend mat ket noi.

Moi request check-in deu gui `X-User-Name` va `X-Password`. Backend xac thuc
username nay, luu ban ghi theo `account.id`, va chi tra ve du lieu cua dung tai
khoan do. Neu doi username trong Settings, check-in va thu muc anh local cung
duoc chuyen sang username moi.

Neu hien `Sync error`, kiem tra hai thiet bi cung Wi-Fi, backend dang chay,
firewall cho phep cong 3000, va dien thoai dang dung IP LAN cua may tinh thay
vi `127.0.0.1`.
