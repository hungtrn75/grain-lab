# 🎞️ GrainLab — Ứng dụng Chỉnh sửa Ảnh RAW & Giả lập Màu Phim (macOS)

Ứng dụng macOS hiện đại chuẩn Native viết bằng **SwiftUI** và **Core Image (Metal GPU)**, cho phép đọc và xử lý file RAW (`.NEF`, `.CR2`, `.CR3`, `.ARW`, `.DNG`, `.RAF`, v.v.), áp dụng hiệu ứng giả lập màu phim với bộ lọc 3D LUT (`.cube`), Tone Curve tùy biến và hạt phim (Film Grain) chân thực.

---

## 🌟 Tính Năng Nổi Bật

1. **Lõi Xử Lý Core Image trên Metal GPU (`CoreImageEngine`)**:
   - `CIContext` khởi tạo với Metal Device (`useSoftwareRenderer: false`, `cacheIntermediates: false`).
   - Hỗ trợ giải mã RAW qua `CIRAWFilter` (điều chỉnh trực tiếp nhiệt độ màu `neutralTemperature`, sắc thái `neutralTint`, độ phơi sáng `exposure`).
   - Hỗ trợ ảnh thường (`.JPEG`, `.PNG`, `.TIFF`, `.HEIC`).
2. **Bộ Parser 3D LUT Adobe `.cube` (`LUTParser` & `LUTRegistry`)**:
   - Tự động parse cấu trúc `.cube` sang bộ đệm Float32 RGBA nạp vào `CIColorCube`.
   - Cơ chế bộ nhớ đệm `NSCache` giúp chuyển đổi LUT tức thì.
   - Kèm sẵn các preset phim kinh điển: **Kodak Portra 400**, **Fujifilm Pro 400H**, **Ilford HP5 Plus (B&W)**, **CineStill 800T**, **Kodachrome 64 Vintage**.
   - Hỗ trợ người dùng nhập (Import) bất kỳ file `.cube` từ máy tính.
3. **5-Stage Film Pipeline**:
   1. RAW Demosaic & White Balance / Exposure Compensation
   2. Tone Controls (Shadows, Highlights, Contrast)
   3. 5-point Tone Curve (`CIToneCurve`)
   4. 3D LUT Color Transform (`CIColorCube` + Alpha Masking)
   5. Authentic Silver-Halide Film Grain (`CIRandomGenerator` + Monochrome + `CISoftLightBlendMode`)
4. **Kiến Trúc MVVM Phản Ứng (`EditorViewModel`)**:
   - Combine Debounce 50ms chống tụt FPS khi kéo thanh trượt liên tục.
   - Tính toán nền `Task.detached` không bao giờ làm đơ Main UI Thread.
   - Hủy bỏ (cancel) tác vụ render cũ khi có tham số mới.
   - Biểu đồ sắc độ Histogram (RGB & Luminance) 64-bin thời gian thực.
5. **Giao Diện 3 Cột Chuẩn macOS (`ContentView` với `NavigationSplitView`)**:
   - **Cột Trái (Sidebar)**: Nút Import RAW, danh sách preset mặc định và preset do người dùng lưu (hỗ trợ Import/Export JSON), thông số EXIF chi tiết.
   - **Cột Giữa (Canvas)**: Hiển thị ảnh, hỗ trợ cử chỉ Zoom (`MagnificationGesture`), Pan (`DragGesture`), chế độ so sánh trước/sau (Before/After), thanh công cụ Zoom (1:1, Fit). Hỗ trợ kéo thả (Drag & Drop) ảnh trực tiếp từ Finder.
   - **Cột Phải (Inspector)**: Đồ thị Histogram, thanh trượt cân bằng trắng & phơi sáng, bảng vẽ đồ thị Tone Curve tương tác, bộ chọn LUT & cường độ, bộ chỉnh độ đậm/kích thước hạt phim, và hộp thoại xuất ảnh gốc (JPEG, PNG, TIFF).

---

## 🏗️ Cấu Trúc Dự Án

```
GrainLab/
├── Package.swift
├── build_app.sh
├── Sources/
│   └── GrainLab/
│       ├── GrainLab.swift                   # App Entry Point (@main)
│       ├── Models/
│           ├── FilmPreset.swift             # Model Codable tham số màu phim
│           └── PresetManager.swift          # Quản lý lưu/đọc/xuất JSON preset
│       ├── Engine/
│           ├── CoreImageEngine.swift        # GPU Metal Pipeline & CIRAWFilter
│           ├── LUTParser.swift              # Trình parse .cube sang CIColorCube
│           └── LUTRegistry.swift            # Quản lý và nạp thư viện LUT
│       ├── ViewModels/
│           └── EditorViewModel.swift        # ViewModel + Combine Debounce + Concurrency
│       ├── Views/
│           ├── ContentView.swift            # NavigationSplitView 3 cột
│           ├── SidebarView.swift            # Cột trái (Presets & EXIF)
│           ├── CanvasView.swift             # Cột giữa (Image Canvas, Zoom, Pan)
│           ├── InspectorView.swift          # Cột phải (Sliders & Controls)
│           ├── HistogramView.swift          # Đồ thị Histogram RGB/Luma
│           ├── ToneCurveEditorView.swift    # Đồ thị Tone Curve trực quan
│           └── ExportSheetView.swift        # Dialog xuất ảnh chất lượng cao
│       └── Resources/                       # Thư mục chứa các file .cube
└── Tests/
    └── GrainLabTests/
        └── GrainLabTests.swift              # Unit Tests toàn diện cho toàn bộ pipeline
```

---

## 🚀 Hướng Dẫn Biên Dịch & Chạy

### 1. Mở trực tiếp trong Xcode
Bạn có thể mở thư mục dự án trực tiếp bằng Xcode:
```bash
xed .
```
Nhấn **Cmd + R** để chạy hoặc **Cmd + U** để chạy Unit Test.

### 2. Biên dịch và chạy từ Terminal qua Swift Package Manager
```bash
# Build
swift build

# Chạy Unit Tests
swift test

# Khởi chạy ứng dụng
swift run
```

### 3. Đóng gói thành file GrainLab.app (macOS Application)
Chạy script tự động đóng gói:
```bash
./build_app.sh
open GrainLab.app
```


## Filmstrip và chỉnh bố cục

- **Import RAW / Photo** hoặc **⌘O** cho phép chọn nhiều ảnh; cũng có thể kéo thả nhiều file vào canvas. Nhấn thumbnail trong filmstrip để chuyển ảnh.
- Mỗi ảnh giữ thông số màu và bố cục riêng trong phiên làm việc hiện tại. Trạng thái này chưa được lưu lại khi thoát app.
- **Copy Edits (⇧⌘C)** và **Paste Edits (⇧⌘V)** sao chép thông số màu, LUT, tone curve và grain. **Paste to All** áp dụng bản đã copy cho toàn bộ ảnh trong filmstrip. Crop và góc xoay không được copy.
- Trong **Crop & Rotate**, chọn **Select Crop on Image…**, kéo vùng muốn giữ rồi nhấn **Apply Crop**. Có thể chọn tỷ lệ có sẵn hoặc chỉnh chiều rộng, chiều cao và vị trí bằng thanh trượt.
- **Left / Right** xoay từng 90°. **Straighten** chỉnh nghiêng ±15° và tự phóng bù để không xuất hiện góc trong suốt. **Reset** khôi phục bố cục gốc.
- Crop và xoay được áp dụng cả khi preview lẫn xuất ảnh ở độ phân giải gốc; file nguồn không bị sửa. Filmstrip hiển thị thumbnail của ảnh nguồn.


## Before / After dạng thanh kéo

Nhấn **Before / After** ở toolbar hoặc dưới canvas để bật so sánh. Bên trái là ảnh neutral trước chỉnh màu, bên phải là kết quả hiện tại. Kéo nút ở đường phân cách để thay đổi vùng hiển thị; nhấp đúp đường phân cách để đưa về giữa. Nhấn **Close Compare** để tắt.

Hai bên dùng cùng crop, góc xoay, zoom và pan để giữ chi tiết khớp nhau. Ảnh Before được cache theo bố cục; kéo đường phân cách không chạy lại pipeline xử lý ảnh. Export luôn xuất ảnh đã chỉnh đầy đủ, không xuất thanh so sánh.


## Áp LUT riêng để đối chiếu màu

Trong **Import .cube**, chọn **Import & Apply LUT Only…** để áp LUT 100% với thông số màu neutral, không chồng WB, tone curve hoặc grain của preset trước. Chọn **Import LUT, Keep Current Edits…** nếu muốn giữ các chỉnh sửa đang có. Với LUT đã nhập, nút **Reset Color & Apply LUT at 100%** đưa về cùng chế độ neutral; crop và xoay được giữ nguyên.

Pipeline hiện dùng LUT sRGB display-referred. File `.cube` không tự xác định ảnh nguồn có phải Log hay không. So sánh với ảnh quảng cáo cần cùng ảnh đầu vào và cùng cách phát triển RAW. Không áp LUT lại vào phần After của ảnh mẫu đã chỉnh.


## Halation & Bloom

Trong Inspector, phần **Halation & Bloom** có hai hiệu ứng độc lập, mặc định tắt:

- **Halation** tạo quầng đỏ/cam bên ngoài vùng sáng. **Halo Spread** chỉnh độ lan.
- **Bloom** tạo ánh sáng lan mềm, trung tính. **Bloom Spread** chỉnh độ rộng.
- **Highlight Threshold** chọn ngưỡng vùng sáng làm nguồn; giảm ngưỡng nếu hiệu ứng chưa rõ.
- **Reset** tắt cả hai và trả các thông số về mặc định.

Gợi ý thử: Halation 20–35%, Bloom 10–20%, Threshold 60%. Ảnh có đèn, nắng ngược hoặc phản chiếu sáng sẽ thể hiện rõ hơn ảnh tối đều. Hiệu ứng chạy sau LUT và trước grain, có trong preview, export, preset JSON và copy/paste. Độ lan được tính theo tỷ lệ kích thước ảnh để giữ cảm giác nhất quán giữa preview và export. Preset JSON cũ vẫn được hỗ trợ.


## LUT Browser với thumbnail

Ở phần **Film Simulation (3D LUT)**, nhấn **Browse LUT Previews…**. Browser hiển thị các LUT có sẵn và LUT đã import trên chính ảnh hiện tại, có tìm kiếm theo tên và thumbnail **None / Bypass**. Chọn thumbnail, chỉnh **Intensity**, rồi nhấn **Apply LUT**; **Cancel** giữ nguyên ảnh chính. WB, tone curve, crop và hiệu ứng hiện tại được giữ khi áp dụng.

Ảnh nền được xử lý một lần ở kích thước nhỏ, sau đó tạo lần lượt các thumbnail ở nền. Đóng Browser sẽ hủy tác vụ preview. LUT lỗi có biểu tượng cảnh báo và không thể chọn. Thumbnail là preview thu nhỏ; kiểm tra chi tiết trên canvas sau khi áp dụng.


## Eyedropper cân bằng trắng

Trong **Basic & White Balance**, nhấn **Pick Neutral Gray / White…** rồi nhấp vùng xám hoặc trắng có chi tiết trên ảnh. Công cụ lấy trung bình vùng nhỏ trước LUT, tone curve và hiệu ứng, rồi áp hiệu chỉnh RGB tuyến tính. Hiệu chỉnh cũng áp dụng cho ảnh RAW sau giải mã; đây không phải phép đo nhiệt độ Kelvin hoặc thông số WB từ cảm biến máy ảnh.

- Tọa độ lấy mẫu theo crop/xoay và mức zoom/pan hiện tại. Khi bật picker, chế độ so sánh được tắt.
- Vùng quá tối, cháy sáng hoặc có màu quá mạnh sẽ được yêu cầu chọn lại. Dùng vật thể bạn biết là xám/trắng trung tính; tránh đèn màu hoặc phản chiếu màu.
- Nhấn **Esc / Cancel** để hủy, **Clear Sample** để bỏ hiệu chỉnh. Chỉnh Temp/Tint thủ công cũng bỏ hiệu chỉnh đã lấy mẫu để tránh chồng hai cách chỉnh WB.
- Hiệu chỉnh được giữ trong preset, copy/paste và export. Lấy mẫu lại sẽ thay thế hiệu chỉnh trước đó.


## Layers & Masks

Trong Inspector, **Layers & Masks → Add** tạo layer chỉnh sửa cục bộ:

- **Linear Gradient**: kéo từ vùng tác động 100% đến vùng 0%. Kéo lại để đổi vị trí/hướng.
- **Radial Gradient**: kéo từ tâm đến mép ellipse; **Feather** chỉnh độ chuyển tiếp. Kéo lại để đổi vị trí/kích thước.
- **Brush**: vẽ lên ảnh, chỉnh **Brush Size**, **Hardness**, **Flow**. Bật **Erase** để xóa vùng mask; **Undo Stroke** bỏ nét cuối, **Clear Mask** xóa toàn bộ nét.

Mỗi layer có tên, bật/tắt, **Layer Opacity**, **Invert Mask** và bộ chỉnh **Exposure, Contrast, Saturation, Warmth**. Layer ở trên trong danh sách được xử lý sau layer ở dưới. Dùng mũi tên để đổi thứ tự, thùng rác để xóa. Mask đỏ và đường hướng dẫn chỉ hiển thị khi **Draw / Edit Mask** đang bật; **Done / Esc** trở về pan bình thường. Có thể dùng Option + cuộn chuột để zoom trong lúc vẽ.

Mask neo theo ảnh nguồn, giữ vị trí khi crop/xoay/cân đường chân trời; zoom và pan chỉ đổi cách xem. Local adjustments chạy sau global tone/LUT, trước Halation/Bloom và grain, có trong preview, LUT Browser và export. Overlay đỏ không được xuất vào ảnh.

Layer được giữ riêng từng ảnh khi chuyển filmstrip trong phiên hiện tại. **Copy/Paste Edits** chỉ sao chép thông số màu toàn ảnh, không sao chép mask. Để giữ layer sau khi thoát app, dùng menu **… → Export Layers…**, rồi **Import Layers…** khi mở lại cùng ảnh. Import sẽ thêm các layer vào danh sách hiện tại. File layer chỉ chứa mask/thông số cục bộ, không chứa ảnh nguồn hoặc chỉnh màu toàn ảnh. Đây là bộ local adjustment cơ bản; chưa có AI mask, luminosity range hay pressure từ bút vẽ.


## Cột công cụ bên phải

Inspector được chia thành bốn tab để giảm cuộn:

- **Edit**: Light & White Balance, eyedropper và Tone Curve.
- **Looks**: Film LUT / LUT Browser, Halation & Bloom, Film Grain.
- **Layers**: Layer và công cụ vẽ mask cục bộ.
- **Crop**: Crop, xoay và cân đường chân trời.

Histogram nằm ở đầu và có thể thu gọn. Các nhóm trong Edit/Looks cũng có thể đóng/mở, có thông tin nhanh về hiệu ứng đang bật. App nhớ tab và trạng thái nhóm giữa các lần mở. Khi rời tab Layers, công cụ vẽ mask được tắt; khi rời Edit, eyedropper được hủy. Export luôn cố định phía dưới, cạnh menu **… → Reset All Adjustments**.
