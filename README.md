# Track Tạ

Ứng dụng Android theo dõi tập tạ theo tuần, giao diện tiếng Việt, hoạt động ngoại tuyến. Bản cài: [GitHub Releases · Track Tạ](https://github.com/Sang6215/track-ta/releases/latest) (Android 7.0 trở lên; ARM32, ARM64, x86_64). Ứng dụng Windows đi kèm trong `desktop/`, đóng gói bằng `tools/build_windows.ps1` để chạy trên Windows 10/11 64 bit.

## Windows và USB

Giải nén toàn bộ ZIP, mở `TrackTa-Windows.exe`. Cài đè APK 1.4.0 lên bản 1.1.0 bằng cùng khóa ký để giữ dữ liệu. Bản 1.1.0 chưa có giao thức USB; bản mới đọc dữ liệu cũ tại cùng khóa lưu trữ và giữ ảnh tại cùng thư mục.

Bật Gỡ lỗi USB, cho phép máy tính, rồi trên điện thoại mở **Dữ liệu → Kết nối Windows qua USB → Bắt đầu kết nối**. Trên Windows chọn thiết bị, nhập mã 6 số và ghép nối. Giữ màn hình kết nối trên điện thoại mở trong khi truyền. Phiên có thời hạn 15 phút, dùng cổng loopback Android được chuyển tiếp qua USB bằng adb và token ngẫu nhiên sau ghép nối. Không cần root điện thoại.

Windows có chỉnh lịch/bài tập, thêm và nhân bản buổi, lưu trữ bài giữ lịch sử, sửa nhật ký, thêm tuần trống, biểu đồ, so sánh tuần, xuất JSON/CSV và khôi phục bản làm việc. Chỉ gửi thay đổi khi bấm đồng bộ, có xem trước và ghép ba chiều với bản lần trước; xung đột cần chọn dữ liệu muốn giữ. Android kiểm tra phiên bản dữ liệu trước khi ghi để tránh ghi đè chỉnh sửa vừa phát sinh. Hai thiết bị đều sao lưu trước khi nhận thay đổi.

Ảnh tháng có tải bản gốc về Windows, so sánh hai tháng, thêm/thay/xóa ảnh điện thoại. Ảnh cũ được giữ bằng tên chứa mã nội dung trên Windows và có bản trước trong dữ liệu riêng Android. Thay/xóa ảnh cũng kiểm tra mã nội dung trước khi ghi.

Dữ liệu Windows ở `%LOCALAPPDATA%\TrackTaWindows`, tách bản làm việc/sao lưu/ảnh theo thiết bị. JSON version 2 chứa lịch tập và nhật ký; không chứa ảnh. Windows đọc JSON version 1 từ Android 1.1.0, nhưng Android 1.1.0 không đọc JSON version 2. Hướng dẫn chi tiết ở `desktop/HUONG-DAN-WINDOWS.txt` và trong ZIP.

## Sử dụng

1. Chuyển APK sang điện thoại, mở file và cho phép cài ứng dụng từ nguồn này khi Android hỏi.
2. Mở **Track Tạ**. Lịch và dữ liệu Excel được nạp sẵn ngay lần mở đầu, không cần đăng nhập hoặc tải dữ liệu.
3. Chọn tuần và buổi Upper / Lower / Push / Pull / Legs, chạm một hiệp để ghi tạ, reps, ghi chú rồi bấm **Lưu hiệp**.
4. Chọn **Tiến độ** để xem lịch sử và biểu đồ từng bài. Vào **Phân tích nhóm cơ** để xem mô hình trước/sau và số hiệp cho từng nhóm cơ chính theo tuần. Khi mở hiệp để ghi, mô hình tự tô sáng cơ chính (xanh lá) và cơ phụ (xanh lam); cũng có thể chạm **Xem nhóm cơ tác động** trên thẻ bài tập. Chạm tên tuần để chuyển tuần hoặc thêm tuần sau tuần 8.
5. Vào **Dữ liệu** để xuất bản sao lưu JSON, khôi phục trên máy khác hoặc xuất CSV mở bằng Excel. Khôi phục yêu cầu xác nhận trước khi thay thế nhật ký.
6. Vào **Ảnh tháng** để chụp ảnh (ưu tiên camera trước) hoặc chọn ảnh từ máy. Mỗi tháng lưu một ảnh; chạm ảnh để xem lớn, chọn hai tháng để so sánh. Có thể thay, xóa hoặc lưu từng ảnh ra máy.
7. Chạm biểu tượng đồng hồ, chọn 60/90/120/180 giây. Cho phép **Thông báo** và **Báo thức & lời nhắc** khi Android yêu cầu. Có thể vuốt đóng app; hết giờ Android sẽ báo bằng chuông, rung và thông báo. Mở lại đồng hồ sẽ thấy thời gian còn lại; **Dừng đồng hồ** sẽ hủy báo thức.

## Dữ liệu nguồn

Nguồn: `Lich_Tap_5_Ngay_Tuan.xlsx`, giữ nguyên file gốc. `tools/import_excel.py` chỉ đọc workbook và tạo `assets/seed.json`.

- 5 buổi, 28 bài tập, 91 hiệp kế hoạch mỗi tuần, 8 tuần có sẵn.
- 108 hiệp có dữ liệu: tuần 1 có 56, tuần 2 có 34, tuần 3 có 18. Tuần 4–8 và các ô chưa ghi vẫn trống.
- Không có ngày bắt đầu trong Excel nên app giữ tuần theo số thứ tự, không tự gán ngày lịch.
- Giữ nguyên các chuỗi như `2x12.5kg`. Biểu đồ quy đổi thành 25 kg, không tự cộng thanh đòn. Giữ cùng cách ghi và thiết bị khi so sánh.
- Plank ghi giây; hít xà trợ lực theo dõi kg hỗ trợ (thấp hơn là ít hỗ trợ hơn). Không nhập tạ khi dùng trọng lượng cơ thể, app hiển thị BW.
- Dấu tích nghĩa là hiệp có reps / thời gian. Có thể lưu tạ hoặc ghi chú trước rồi bổ sung reps.
- Phân tích nhóm cơ dùng phân loại gần đúng cho 28 bài tập. Chỉ tính hiệp đã có reps/thời gian; nếu một bài có hai nhóm cơ chính, hiệp được tính cho cả hai. Mô hình không đo mức kích hoạt cơ thực tế.
- Chỉ nạp Excel khi chưa có nhật ký cục bộ; lần mở tiếp theo dùng dữ liệu đã lưu, không nạp lại hiệp đã xóa.
- Không có máy chủ, tài khoản hoặc đồng bộ mạng. Ảnh tháng được lưu trong vùng dữ liệu riêng của app, không tải lên mạng và được giữ khi cài bản cập nhật cùng chữ ký. Bản sao lưu JSON chỉ có nhật ký tập, không chứa ảnh; hãy dùng **Lưu ảnh ra máy** cho từng tháng trước khi gỡ app hoặc xóa dữ liệu. Âm/rung của đồng hồ tuân theo cài đặt thông báo, chế độ im lặng và Không làm phiền của Android. Android không cho báo thức chạy sau khi người dùng chọn **Buộc dừng** trong cài đặt ứng dụng.

## Phát triển và đóng gói

Flutter 3.41.5 / Dart 3.11.3, JDK 21, Android SDK 36. Các công cụ Android và JDK cục bộ nằm trong `.tooling` và không đưa vào mã nguồn.

```powershell
flutter pub get
flutter test
dart analyze lib test
./tools/build_release.ps1
python -m unittest discover -s desktop/tests -p test_*.py
python desktop/tests/ui_smoke.py
./tools/build_windows.ps1
```

Script Windows kiểm tra bản EXE với cả nền tảng giao diện Windows và chế độ offscreen trước khi tạo ZIP. Bản 1.0.1 sửa lỗi mở QtGui do thu thập nhầm `icuuc.dll`; Qt dùng ICU do Windows cung cấp. Kết quả kiểm tra bản ZIP đã giải nén và giao thức USB nằm ở `release/PC-TEST-REPORT.json` và `release/USB-TEST-REPORT.json`. Đồng bộ và xử lý xung đột được kiểm tra trên giả lập. Trên điện thoại V2352A thật, đã cập nhật từ 1.1.0 lên 1.3.0 bằng cách cài đè ngày 12/10/2026, đối chiếu đủ 296 hiệp trong 10 tuần với bản trước cập nhật, kiểm tra ghép nối USB và sao lưu 2 ảnh tháng. Kiểm tra trên điện thoại thật chỉ đọc/sao lưu, không sửa nhật ký hoặc ảnh để thử nghiệm.

Khóa ký phát hành riêng ở `android/trackta-release.jks`, cấu hình ở `android/key.properties`. Giữ riêng và sao lưu hai file này để APK cập nhật sau dùng đúng chữ ký. Không đưa khóa vào Git hoặc gửi cùng APK. Script đóng gói dùng khóa sẵn có, không thay khóa. Khi phát hành bản mới, tăng version trong `pubspec.yaml` và tên file đầu ra.

`lib/models.dart` xử lý dữ liệu, lưu trữ, sao lưu, CSV. `lib/main.dart` chứa lịch tập, ghi hiệp, dữ liệu và đồng hồ. `lib/muscles.dart` chứa phân loại bài tập, mô hình cơ thể và phân tích theo tuần. `lib/photo_journal.dart` và `lib/photos.dart` xử lý ảnh tháng. `lib/rest_alarm.dart` gọi báo thức Android trong `android/app/src/main/kotlin`. `lib/progress.dart` chứa biểu đồ và lịch sử. APK là bản dành cho điện thoại Android.

`lib/usb_sync.dart` cung cấp phiên ghép nối và API loopback. `desktop/trackta_core.py` kiểm tra dữ liệu, ghép thay đổi và lưu bản làm việc; `desktop/usb_client.py` giao tiếp USB; `desktop/window.py` là giao diện PySide6. PyInstaller đóng gói Python/Qt và công cụ USB vào bản Windows; không cần Python trên máy người dùng.

Kiểm tra tự động bao gồm dữ liệu nguồn, tạ đôi, tuần trống, lưu rồi mở lại, không nạp lại hiệp đã xóa, thêm tuần, sao lưu/khôi phục, từ chối file lỗi, tạ trợ lực, Plank, CSV, phân loại đủ 28 bài, đếm hiệp cơ chính, thay/xóa ảnh tháng, giao diện trên màn hình 360 / 390 px, dữ liệu từng phần của tuần debloat (2 tuần, 1 tuần, trợ lực) và xác thực điều chỉnh AI (biên ±20%, JSON hỏng, fallback công thức).

## Tuần debloat (Android 1.4.0 / Windows 1.1.0)

Khi tuần 1–4 đều có ít nhất một hiệp đã tập, Android hiện thẻ **Tuần debloat** trong Lịch tập; Windows hiện nút cùng tên trong Nhật ký. Mỗi bài dùng các tuần có dữ liệu trong tuần 1–4 (bài có 1–3 tuần vẫn tính bằng hồi quy trên các tuần đó; chỉ bài chưa có hiệp nào bị bỏ qua): lấy tạ cao nhất, trợ lực thấp nhất hoặc thời gian cao nhất rồi hồi quy tuyến tính để dự báo tuần 5. Dự báo được kẹp vào 0–mức tốt nhất trong các tuần đã ghi (trợ lực: thấp nhất) theo lựa chọn đã chốt. Nhân 60% cho tạ/Plank, chia 60% cho trợ lực. Tạ làm tròn 2,5 kg (từng quả khi cả bốn tuần ghi `2x`), trợ lực làm tròn lên; thời gian làm tròn 5 giây, tối thiểu 5 giây. BW chỉ điền reps mục tiêu thấp nhất.

Bản xem trước có dữ liệu bốn tuần, dự báo thô và đã kẹp, số hiệp điền/giữ và lý do bỏ qua bài thiếu dữ liệu. Chỉ điền hiệp trống tuần 5; không sửa Excel hoặc dữ liệu đã ghi. Gợi ý mang `source: debloat`, không tính hoàn thành, biểu đồ hay số hiệp nhóm cơ; mở và lưu hiệp sẽ chuyển sang `app`/`windows` để xác nhận. Áp dụng lại không ghi đè. Nhãn `debloatWeeks` là trường tùy chọn trong JSON version 2, được giữ qua mở lại và USB. Windows ghép hợp các nhãn; dùng Windows 1.1.0 và Android 1.4.0 để giữ trạng thái gợi ý. Chặn gửi gợi ý tới Android cũ vì bản cũ sẽ tính nhầm hoàn thành.

Kiểm tra ngày 21/10/2026: 26 kiểm tra Flutter, 15 kiểm tra Python, phân tích Dart không có lỗi. Đã kiểm tra giao diện xem trước/áp dụng Android và đối chiếu kết quả chính xác với Windows cho tạ thường, trợ lực và Plank trên giả lập. ZIP giải nén chạy bằng nền tảng Windows với đường dẫn có dấu/khoảng trắng, ghép nối và tải nhật ký/ảnh bằng công cụ USB đi kèm. Chữ ký APK 1.4.0 khớp 1.3.0. Báo cáo hiện tại: `release/DEBLOAT-TEST-REPORT.json` và `release/DEBLOAT-USB-TEST-REPORT.json`; sau đó đã cài đè 1.4.0 lên điện thoại V2352A thật theo yêu cầu: giữ nguyên 362 hiệp trong 10 tuần, đối chiếu đúng mã nội dung của 2 ảnh tháng, ghép nối USB thành công và thấy thẻ Tuần debloat. Chưa áp dụng gợi ý lên nhật ký thật. Báo cáo cập nhật: `release/PHONE-UPDATE-1.4.0-REPORT.json`.

## Trợ lý AI Gemini và dữ liệu từng phần (Android 1.5.0 / Windows 1.2.0)

Từ bản 1.5.0, bài chỉ cần **một tuần có hiệp đã tập** trong tuần 1–4 là được tính vào tuần debloat: hồi quy chạy trên các tuần có sẵn (đúng một tuần thì dự báo bằng chính giá trị đó), kẹp theo mức tốt nhất của các tuần đã ghi. Bài chưa có hiệp nào vẫn bị bỏ qua và hiện lý do. Android và Windows tính trùng khớp nhau.

Trên Android, mục **Trợ lý AI (Gemini)** trong tab Dữ liệu cho nhập API key tạo miễn phí tại Google AI Studio (aistudio.google.com/apikey; model mặc định `gemini-2.5-flash`, đổi được). Có key thì bản xem trước tuần debloat tự phân tích khi mở, bấm **Phân tích lại** để chạy lại. AI viết nhận xét chung, cảnh báo và nhận xét từng bài; được điều chỉnh tạ/giây nhưng chỉ chấp nhận trong ±20% giá trị công thức (làm tròn lại theo cùng bước 2,5 kg / 5 giây), reps kẹp trong khoảng mục tiêu; ngoài biên hoặc sai định dạng thì giữ nguyên giá trị công thức. Điều chỉnh của AI vẫn là gợi ý `source: debloat`, chưa tính hoàn thành cho tới khi lưu hiệp.

API key chỉ lưu trong SharedPreferences của thiết bị, không nằm trong bản sao lưu JSON hay dữ liệu USB. Khi phân tích, tên bài, mức tạ các tuần 1–4 và dự báo được gửi tới Google qua internet; không gửi ảnh, ghi chú hay key. Không có key hoặc không có mạng, ứng dụng vẫn đầy đủ tính năng với gợi ý công thức. Tính năng AI chỉ có trên Android; Windows giữ thuật toán xác định và đọc gợi ý AI như gợi ý thường qua USB.

Ngày 24/10/2026: 42 kiểm tra Flutter và 18 kiểm tra Python đạt; phân tích Dart không có lỗi. APK 1.5.0 và ZIP Windows 1.2.0 cần chạy `tools/build_release.ps1` và `tools/build_windows.ps1` để tạo.

## Giao diện Cobalt + Lime (Android 1.5.1)

Bản 1.5.1 đổi màu chủ đạo từ lime sang cobalt `#6B9BFF`: logo, ngày đang chọn, CTA, thanh tiến độ, đồng hồ nghỉ và tab đang mở. Lime `#D4F58A` chuyển thành màu phụ cho dữ liệu và thành tích: hiệp đã ghi, biểu đồ PR, nhóm cơ phụ, nhận xét AI. Coral `#FF6B6B` chỉ dành cho thao tác xóa. Token nằm trong `lib/palette.dart`. Không thay đổi dữ liệu, hành vi hay giao thức USB; APK dùng cùng khóa ký nên cài đè giữ nguyên nhật ký.

Ngày 29/10/2026: 44 kiểm tra Flutter đạt, phân tích Dart không có lỗi; APK 1.5.1 đã cài đè lên V2352A và kiểm tra các màn Lịch tập, Tiến độ, Phân tích nhóm cơ, đồng hồ nghỉ và Dữ liệu.

## Track Tạ 2.0 (Android 2.0.0)

Bản 2.0.0 áp bố cục “Performance Dark” đã duyệt trong `design/trackta-2.0.html`, giữ bảng màu Cobalt + Lime:

- **Lịch tập gọn:** bỏ tiêu đề lớn, tuần + chevron thành một hàng; strip 7 ngày có cả ngày nghỉ; card buổi tập có vòng %; bài đang tập mở sẵn nên set đầu tiên nằm trên fold, các bài còn lại thu gọn; sơ đồ cơ chuyển vào sheet “Cơ tác động”.
- **Focus mode:** editor toàn màn hình với tạ/reps hai cột, stepper, quick chip, strip chuyển hiệp, banner nghỉ nối với đồng hồ nền (`+30s`, bỏ qua), ghi chú thu gọn và nút lưu cố định trong vùng cuộn.
- **Tiến độ:** chọn 4 tuần / 3 tháng / tất cả; ba thẻ buổi tập – PR – chuỗi tuần; chart có trục chia đều, vùng tô và mốc PR; card cân bằng nhóm cơ tuần này kèm link sang bản đồ cơ.
- **Typography:** Barlow + Barlow Condensed (giấy phép OFL, đóng gói trong `assets/fonts`).

Dữ liệu JSON, hành vi lưu và giao thức USB không đổi; APK dùng cùng khóa ký nên cài đè giữ nguyên nhật ký.

Ngày 29/10/2026: 44 kiểm tra Flutter đạt, phân tích Dart không có lỗi; APK 2.0.0 cài đè lên V2352A và kiểm tra Lịch tập, Focus, Tiến độ, Phân tích nhóm cơ, Dữ liệu.
