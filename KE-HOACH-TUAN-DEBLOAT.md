# Kế hoạch triển khai tuần debloat

## 1. Hành vi đã chốt

- Tuần debloat là **tuần 5**, chỉ xuất hiện sau khi tuần 1–4 đều có dữ liệu.
- Mỗi tuần lấy **hiệp tốt nhất** của từng bài:
  - Tạ thường: mức tạ lớn nhất.
  - Hít xà trợ lực: mức hỗ trợ nhỏ nhất.
  - Plank: số giây lớn nhất.
- Dùng hồi quy tuyến tính trên 4 điểm tuần để dự báo tuần 5, sau đó:
  - Tạ thường: `dự báo × 60%`.
  - Trợ lực: `dự báo ÷ 60%` để tăng mức hỗ trợ.
  - Plank: `dự báo × 60%`.
- Điền reps mục tiêu thấp nhất, riêng Plank điền số giây đề xuất.
- Làm tròn tạ 2.5 kg; giữ cách ghi `2x...` nếu dữ liệu 4 tuần dùng cách đó.
- Chỉ điền vào các hiệp đang trống của tuần 5, không ghi đè dữ liệu đã có.
- Lưu nhãn tuần debloat vào JSON và đồng bộ USB.
- Triển khai cả Android và Windows, sau đó build APK/ZIP.

## 2. Model tính toán

Tạo module mới `lib/debloat.dart` gồm:

- `DebloatSuggestion`: bài tập, tạ gợi ý, reps/thời gian, 4 giá trị tuần, dự báo.
- `DebloatPlan`: danh sách gợi ý, bài bị bỏ qua vì thiếu dữ liệu, số hiệp sẽ điền.
- Hàm `buildDebloatPlan(store, targetWeek: 5, factor: 0.6)`.
- Hàm `formatSuggestedWeight(...)` giữ dạng `2x12.5kg`, làm tròn 2.5 kg.
- Hàm kiểm tra điều kiện: tuần 1–4 mỗi tuần có ít nhất một hiệp hoàn thành.

Thuật toán cho từng bài:

1. Lấy 4 tuần `1..4`, mỗi tuần lấy hiệp tốt nhất theo cách đo.
2. Nếu thiếu bất kỳ tuần nào → bỏ qua bài đó.
3. Hồi quy tuyến tính `y = a + bx` với `x = 1..4`, dự báo `x = 5`.
4. Kẹp dự báo trong khoảng `0..mức tốt nhất 4 tuần` để tránh ngoại suy bất thường.
5. Áp hệ số 60%, làm tròn 2.5 kg hoặc 5 giây.
6. Bài BW không có tạ: chỉ điền reps mục tiêu thấp nhất.
7. Bài không đủ 4 tuần dữ liệu: không tạo hiệp, hiển thị lý do trong bản xem trước.

**Lưu ý quan trọng:** hiệp được điền sẵn sẽ có `source: 'debloat'` và **không được tính là đã tập**. Chỉ khi người dùng mở hiệp và bấm lưu, `source` chuyển thành `'app'`/`'windows'` thì mới tính hoàn thành.

## 3. Lưu trữ Android

Sửa `lib/models.dart`:

- Thêm `Set<int> debloatWeeks` vào `TrainingStore` (`models.dart:97`).
- Thêm field tùy chọn `debloatWeeks` vào `backup()` (`models.dart:167`) và `readBackup()` (`models.dart:174`); file cũ không có field thì mặc định rỗng.
- Kiểm tra danh sách tuần hợp lệ, không trùng, nằm trong `1..weeks`.
- Thêm `isDebloat(week)`.
- Thêm phương thức ghi nhiều hiệp trong một transaction, ví dụ `applyDebloat(week, values)`, có rollback nếu lưu lỗi. Không gọi lồng nhiều `update()` vì dễ nghẽn transaction.
- Cập nhật `SetEntry.complete` để trả `false` khi `source == 'debloat'`.
- Giữ nguyên JSON version 2; `debloatWeeks` là field tùy chọn để không phá bản cũ.

## 4. UI Android

Sửa `lib/main.dart`, có thể tách thêm `lib/debloat_ui.dart`:

- Trong `pickWeek` (`main.dart:128`): hiển thị `Tuần 5 · Debloat` khi đã đủ điều kiện.
- Trong `workout()` (`main.dart:259`): thêm thẻ **Tuần debloat** khi tuần 1–4 đã có dữ liệu, kể cả khi người dùng đang chọn tuần khác.
- Nút **Xem & áp dụng** mở bottom sheet xem trước:
  - Tên bài, 4 mức tốt nhất, dự báo, tạ/reps đề xuất.
  - Ghi rõ số hiệp trống sẽ điền và số hiệp đã có sẽ giữ nguyên.
  - Nút **Áp dụng vào tuần 5**.
- Sau khi áp dụng:
  - Chuyển sang tuần 5.
  - Hiển thị nhãn `DEBLOAT` và thông báo đã điền gợi ý.
  - Các hiệp gợi ý hiển thị khác biệt (icon gợi ý, màu teal) và vẫn có thể sửa.
- Thêm dòng giải thích công thức trong mục **Dữ liệu**.
- `setRow` (`main.dart:595`) hiển thị trạng thái “gợi ý” thay vì dấu hoàn thành.

## 5. Windows

### `desktop/trackta_core.py`

- Thêm `debloat_plan(doc, target=5, factor=0.6)` và `apply_debloat(doc, plan)`.
- Thêm các hàm kiểm tra điều kiện, định dạng tạ, hồi quy tương tự Android.
- `normalize()` (`trackta_core.py:41`): đọc và kiểm tra `debloatWeeks`.
- `merge_snapshots()` (`trackta_core.py:155`): hợp nhất `debloatWeeks` giữa hai bên.
- `change_summary()`: thêm thay đổi nhãn debloat.
- `progress_values()` và thống kê “hiệp đã ghi”: bỏ qua entry `source == 'debloat'`.

### `desktop/window.py`

- Thêm nút **Tuần debloat** trong trang Nhật ký (`window.py:653`) hoặc cạnh nút thêm tuần.
- Mở dialog xem trước dạng bảng: bài, 4 tuần, dự báo, đề xuất, reps.
- Áp dụng vào bản làm việc Windows, chỉ điền hiệp trống; không tự gửi điện thoại.
- Hiển thị nhãn `DEBLOAT` khi tuần đang chọn nằm trong `debloatWeeks`.
- Khi đồng bộ, nhãn và các hiệp gợi ý đi qua USB như dữ liệu bình thường.

### `desktop/usb_client.py`

- Cập nhật đường dẫn APK, thông báo phiên bản và version Windows.

## 6. Đồng bộ và tương thích

- Snapshot USB đã dùng `store.backup()` nên chỉ cần thêm field vào backup.
- Android `readBackup` kiểm tra field mới; Windows `normalize` giữ field mới.
- JSON version vẫn là 2; Windows 1.1.0 đọc được file cũ, file mới có thêm `debloatWeeks`.
- Cả hai bên dùng chung quy ước:
  - `source = 'debloat'` → hiệp gợi ý, chưa tính hoàn thành.
  - `source = 'app'` hoặc `'windows'` → hiệp đã xác nhận.
- Nếu Windows cũ mở file mới, field debloat có thể bị bỏ; ghi rõ trong hướng dẫn rằng cần Windows 1.1.0 để giữ nhãn.

## 7. Kiểm thử

### Dart

- `test/debloat_test.dart`:
  - `40, 42.5, 45, 47.5` → dự báo thô 50, kẹp còn 47.5, gợi ý **27.5 kg**, reps 6 (đã chốt giữ giới hạn).
  - `2x10kg, 2x12.5kg, 2x12.5kg, 2x15kg` → giữ dạng `2x10kg`.
  - Trợ lực `40, 45, 45, 50` → tăng hỗ trợ, làm tròn lên.
  - Plank `60, 60, 60, 60` → khoảng 35 giây.
  - Thiếu một tuần → bỏ qua bài.
  - Bài BW → chỉ điền reps.
  - Chỉ điền hiệp trống, giữ hiệp đã có.
  - `source='debloat'` không làm tăng `weekDone`.
- Cập nhật `store_test.dart`, `widget_test.dart`, `usb_sync_test.dart`.
- Widget test: chưa đủ 4 tuần → không có thẻ; đủ 4 tuần → có thẻ, xem trước, áp dụng; tuần 5 có nhãn.

### Python

- Thêm test vào `desktop/tests/test_core.py` cho hồi quy, làm tròn, trợ lực, Plank, thiếu dữ liệu, merge `debloatWeeks`, kiểm tra `normalize`.
- Cập nhật `desktop/tests/ui_smoke.py` nếu dialog debloat có thể kiểm tra offscreen.
- Chạy `python desktop/tests/usb_emulator.py` nếu emulator đang hoạt động; nếu không, ghi rõ chưa kiểm tra USB/thiết bị thật.

### Lệnh kiểm tra

```powershell
flutter test
dart analyze lib test
python -m unittest discover -s desktop/tests -p test_*.py
python desktop/tests/ui_smoke.py
```

## 8. Version, tài liệu và build

- Android: `pubspec.yaml` → `1.4.0+5`; APK `Track-Ta-v1.4.0.apk`.
- Windows: `1.1.0`; ZIP `TrackTa-Windows-v1.1.0.zip`.
- Cập nhật:
  - `tools/build_release.ps1`
  - `tools/build_windows.ps1`
  - `desktop/app.py`, `desktop/window.py`, `desktop/usb_client.py`
  - `lib/usb_sync.dart` (`appVersion`)
  - `README.md`
  - `desktop/HUONG-DAN-WINDOWS.txt`
  - `release/HUONG-DAN.txt`
- Build theo thứ tự:
  1. `flutter pub get`
  2. Chạy test/analyze.
  3. `./tools/build_release.ps1`
  4. `./tools/build_windows.ps1`
- Cập nhật `release/SHA256.txt`, `release/SHA256-USB.txt` và báo cáo test bằng kết quả thực tế, không ghi nhận kiểm tra thiết bị thật nếu chưa chạy.

## 9. Tiêu chí hoàn thành

- Trước khi đủ 4 tuần: không có nút/thẻ debloat.
- Sau 4 tuần: thẻ xuất hiện; xem trước đúng công thức; áp dụng chỉ điền hiệp trống.
- Tuần 5 được đánh dấu debloat; các hiệp gợi ý không bị tính là đã tập.
- Sửa và lưu một hiệp gợi ý thì hiệp đó mới tính hoàn thành.
- Nhãn debloat và dữ liệu tồn tại sau khi mở lại app và sau đồng bộ USB.
- APK 1.4.0 và ZIP Windows 1.1.0 được tạo thành công.

## 10. Điểm cần xác nhận

- Các hiệp điền sẵn **không được tính là đã tập** cho đến khi người dùng lưu lại hiệp đó.
- Công thức trợ lực dùng phép chia cho 60% để tăng mức hỗ trợ; nếu muốn giữ nguyên mức hỗ trợ, cần đổi trước khi triển khai.
- Dự báo hồi quy được kẹp không vượt quá mức tốt nhất trong 4 tuần; nếu muốn dùng hồi quy thuần, cần bỏ giới hạn này.

## 11. Kết quả triển khai (21/10/2026)

- Người dùng đã chọn giữ giới hạn dự báo; ví dụ tạ thường ở mục 7 đã sửa thành 27,5 kg theo quy tắc này.
- “Mức tốt nhất” là lớn nhất cho tạ thường/thời gian, thấp nhất cho kg trợ lực. Ví dụ trợ lực 40/45/45/50 kẹp ở 40, chia 60% và làm tròn lên thành 67,5 kg.
- Android 1.4.0 và Windows 1.1.0 đã có xem trước, điền hiệp trống, nhãn tuần, trạng thái gợi ý và xác nhận bằng thao tác lưu hiệp.
- 26 kiểm tra Flutter và 15 kiểm tra Python đạt; phân tích Dart không có lỗi. Đã thử giao diện Android, mở lại và USB trên giả lập, đối chiếu kết quả với Windows.
- Đã tạo `release/Track-Ta-v1.4.0.apk` và `release/TrackTa-Windows-v1.1.0.zip`; kiểm tra EXE sau giải nén đạt. Đã cài bản mới lên V2352A thật theo yêu cầu sau đó; giữ nguyên 362 hiệp/10 tuần và 2 ảnh tháng, kiểm tra USB và thẻ debloat. Chưa áp dụng gợi ý lên nhật ký thật.
- Kết quả chi tiết và SHA256: `release/DEBLOAT-TEST-REPORT.json`, `release/DEBLOAT-USB-TEST-REPORT.json`, `release/SHA256.txt`, `release/SHA256-USB.txt`.
