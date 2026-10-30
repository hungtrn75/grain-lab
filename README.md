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
