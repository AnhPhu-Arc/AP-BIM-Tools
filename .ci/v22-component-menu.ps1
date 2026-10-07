$ErrorActionPreference = 'Stop'

$app = '.\\source\\AP.BimTools\\Application.cs'
$txt = Get-Content $app -Raw

$newMethod = @'
    private void CreateStructureRibbon()
    {
        // Component-first ribbon: each host has its own visual menu.
        var elements = Application.CreatePanel("Bố trí thép", ProductInfo.StructureTab);

        var beam = AddPulldown(elements, "AP_STR_Beam", "Thép dầm", "Bố trí, kiểm tra và triển khai cốt thép dầm.", "Beam");
        AddMenuItem<BeamRebarAxisStudioCommand>(beam, "Bố trí thép dầm", "Mở Beam Rebar Studio cho dầm được chọn.", "Beam");
        AddMenuItem<ApplySavedRebarPresetCommand>(beam, "Áp dụng preset", "Áp dụng cấu hình AP-Rebar đã lưu cho dầm.", "Operations");
        AddMenuItem<SelectRebarByHostCommand>(beam, "Chọn thép theo dầm", "Chọn toàn bộ Rebar có host là dầm.", "Rebar");
        AddMenuItem<DeleteHostedRebarCommand>(beam, "Xóa thép dầm", "Xóa Rebar đang được host bởi dầm.", "Operations");
        AddMenuItem<CreateRebarDetailSectionsCommand>(beam, "Tạo mặt cắt thép dầm", "Tạo section chi tiết quanh dầm có cốt thép.", "Docs");
        AddMenuItem<CreateRebarReview3DCommand>(beam, "Kiểm tra dầm 3D", "Tạo view 3D Fine để kiểm tra cốt thép dầm.", "Rebar");
        AddMenuItem<ExportRebarBbsCommand>(beam, "Xuất BBS thép dầm", "Xuất thống kê uốn/cắt và khối lượng Rebar.", "Docs");

        var column = AddPulldown(elements, "AP_STR_Column", "Thép cột", "Bố trí, thép chờ, kiểm tra và triển khai cốt thép cột.", "Column");
        AddMenuItem<ColumnRebarStudioCommand>(column, "Bố trí thép cột", "Mở Column Rebar Studio cho cột được chọn.", "Column");
        AddMenuItem<ColumnStarterBarsCommand>(column, "Thép chờ cột -> móng", "Tạo thép chờ cột xuống móng gần nhất.", "Foundation");
        AddMenuItem<ApplySavedRebarPresetCommand>(column, "Áp dụng preset", "Áp dụng cấu hình AP-Rebar đã lưu cho cột.", "Operations");
        AddMenuItem<SelectRebarByHostCommand>(column, "Chọn thép theo cột", "Chọn toàn bộ Rebar có host là cột.", "Rebar");
        AddMenuItem<DeleteHostedRebarCommand>(column, "Xóa thép cột", "Xóa Rebar đang được host bởi cột.", "Operations");
        AddMenuItem<QuickDimColumnPlanCommand>(column, "Dim mặt bằng cột", "Dimension tim cột theo hai phương trên mặt bằng.", "Dim");
        AddMenuItem<CreateRebarDetailSectionsCommand>(column, "Tạo mặt cắt cột", "Tạo section chi tiết quanh cột có cốt thép.", "Docs");
        AddMenuItem<CreateRebarReview3DCommand>(column, "Kiểm tra cột 3D", "Tạo view 3D Fine để kiểm tra cốt thép cột.", "Rebar");

        var wall = AddPulldown(elements, "AP_STR_Wall", "Thép tường/vách", "Bố trí và kiểm tra cốt thép tường/vách.", "Wall");
        AddMenuItem<WallRebarStudioCommand>(wall, "Bố trí thép tường/vách", "Mở Wall Rebar Studio cho tường/vách được chọn.", "Wall");
        AddMenuItem<ApplySavedRebarPresetCommand>(wall, "Áp dụng preset", "Áp dụng cấu hình AP-Rebar đã lưu cho tường/vách.", "Operations");
        AddMenuItem<SelectRebarByHostCommand>(wall, "Chọn thép theo vách", "Chọn toàn bộ Rebar có host là tường/vách.", "Rebar");
        AddMenuItem<DeleteHostedRebarCommand>(wall, "Xóa thép tường/vách", "Xóa Rebar đang được host bởi tường/vách.", "Operations");
        AddMenuItem<QuickDimWallPlanCommand>(wall, "Dim tường mặt bằng", "Dimension hai mặt của tường thẳng.", "Dim");
        AddMenuItem<CreateRebarDetailSectionsCommand>(wall, "Tạo mặt cắt vách", "Tạo section chi tiết quanh tường/vách có cốt thép.", "Docs");
        AddMenuItem<CreateRebarReview3DCommand>(wall, "Kiểm tra vách 3D", "Tạo view 3D Fine để kiểm tra cốt thép tường/vách.", "Rebar");

        var slab = AddPulldown(elements, "AP_STR_Slab", "Thép sàn", "Bố trí và kiểm tra cốt thép sàn.", "Slab");
        AddMenuItem<SlabRebarStudioCommand>(slab, "Bố trí thép sàn", "Tạo thép lớp trên/dưới theo X/Y cho sàn.", "Slab");
        AddMenuItem<ApplySavedRebarPresetCommand>(slab, "Áp dụng preset", "Áp dụng cấu hình AP-Rebar đã lưu cho sàn.", "Operations");
        AddMenuItem<SelectRebarByHostCommand>(slab, "Chọn thép theo sàn", "Chọn toàn bộ Rebar có host là sàn.", "Rebar");
        AddMenuItem<DeleteHostedRebarCommand>(slab, "Xóa thép sàn", "Xóa Rebar đang được host bởi sàn.", "Operations");
        AddMenuItem<CreateRebarDetailSectionsCommand>(slab, "Tạo mặt cắt sàn", "Tạo section chi tiết quanh sàn có cốt thép.", "Docs");
        AddMenuItem<CreateRebarReview3DCommand>(slab, "Kiểm tra sàn 3D", "Tạo view 3D Fine để kiểm tra cốt thép sàn.", "Rebar");

        var foundation = AddPulldown(elements, "AP_STR_Foundation", "Thép móng", "Bố trí, thép chờ, kiểm tra và triển khai cốt thép móng.", "Foundation");
        AddMenuItem<FoundationRebarStudioCommand>(foundation, "Bố trí thép móng", "Tạo thép lớp trên/dưới theo X/Y cho móng.", "Foundation");
        AddMenuItem<ColumnStarterBarsCommand>(foundation, "Tạo thép chờ cột", "Tạo thép chờ cột vào móng gần nhất.", "Column");
        AddMenuItem<ApplySavedRebarPresetCommand>(foundation, "Áp dụng preset", "Áp dụng cấu hình AP-Rebar đã lưu cho móng.", "Operations");
        AddMenuItem<SelectRebarByHostCommand>(foundation, "Chọn thép theo móng", "Chọn toàn bộ Rebar có host là móng.", "Rebar");
        AddMenuItem<DeleteHostedRebarCommand>(foundation, "Xóa thép móng", "Xóa Rebar đang được host bởi móng.", "Operations");
        AddMenuItem<QuickDimPilePlanCommand>(foundation, "Dim cọc mặt bằng", "Dimension tim cọc theo hai phương.", "Dim");
        AddMenuItem<RenumberFoundationsCommand>(foundation, "Đánh số móng", "Đánh lại số Mark cho móng kết cấu.", "Marks");
        AddMenuItem<CreateRebarDetailSectionsCommand>(foundation, "Tạo mặt cắt móng", "Tạo section chi tiết quanh móng có cốt thép.", "Docs");

        var common = Application.CreatePanel("Rebar chung", ProductInfo.StructureTab);
        AddWithIcon<RebarStudioCommand>(common, "Rebar\nStudio", "Cấu hình và bố trí thép cho nhiều loại cấu kiện được chọn.", "Rebar");

        var operations = AddPulldown(common, "AP_Rebar_Operations", "Chỉnh sửa", "Công cụ chỉnh sửa và lựa chọn cốt thép.", "Operations");
        AddMenuItem<SetRebarSpacingCommand>(operations, "Đặt khoảng cách thép", "Đặt Maximum Spacing cho shape-driven Rebar set.", "Operations");
        AddMenuItem<RenumberRebarCommand>(operations, "Đánh số thép", "Đánh lại Mark cho Rebar.", "Marks");
        AddMenuItem<SelectApRebarCommand>(operations, "Chọn AP-Rebar", "Chọn Rebar do AP-Rebar tạo.", "Rebar");
        AddMenuItem<RebarSolidCommand>(operations, "Hiện Rebar Solid", "Hiện Rebar dạng solid trong view 3D.", "Rebar");
        AddMenuItem<RebarUnobscuredCommand>(operations, "Hiện Rebar xuyên host", "Đặt Rebar unobscured trong view hiện tại.", "Rebar");

        var docs = AddPulldown(common, "AP_Rebar_Docs", "Bản vẽ & BBS", "Thống kê, kiểm tra 3D và triển khai hồ sơ Rebar.", "Docs");
        AddMenuItem<ExportRebarBbsCommand>(docs, "Xuất BBS", "Xuất bar bending schedule và khối lượng thép.", "Docs");
        AddMenuItem<CreateRebarScheduleCommand>(docs, "Rebar Schedule", "Tạo native Revit Rebar Schedule.", "Docs");
        AddMenuItem<CreateRebarReview3DCommand>(docs, "Rebar Review 3D", "Tạo view 3D Fine quanh cấu kiện có thép.", "Rebar");
        AddMenuItem<CreateRebarDetailSectionsCommand>(docs, "Tạo Detail Sections", "Tạo section chi tiết cho cấu kiện được chọn.", "Docs");
        AddMenuItem<RebarAuditDetailedCommand>(docs, "Rebar Audit", "Kiểm tra host, mark, quantity và total length.", "QA");
        AddMenuItem<RebarReportCommand>(docs, "Rebar Report", "Xuất thuộc tính và số lượng Rebar.", "Docs");

        var dimensions = Application.CreatePanel("Dim / Tag", ProductInfo.StructureTab);
        var dimMenu = AddPulldown(dimensions, "AP_QuickDim", "Dim, Tag", "Dimension nhanh theo cấu kiện và datum.", "Dim");
        AddMenuItem<QuickDimGridCommand>(dimMenu, "Dim Grid", "Tạo chained dimensions cho nhóm Grid thẳng.", "Dim");
        AddMenuItem<QuickDimLevelCommand>(dimMenu, "Dim Level", "Tạo chained dimensions cho Level.", "Dim");
        AddMenuItem<QuickDimWallPlanCommand>(dimMenu, "Dim tường mặt bằng", "Dimension hai mặt tường thẳng.", "Wall");
        AddMenuItem<QuickDimPilePlanCommand>(dimMenu, "Dim cọc mặt bằng", "Dimension tim cọc theo hai phương.", "Foundation");
        AddMenuItem<QuickDimColumnPlanCommand>(dimMenu, "Dim cột mặt bằng", "Dimension tim cột theo hai phương.", "Column");

        var management = Application.CreatePanel("Kết cấu", ProductInfo.StructureTab);
        var modelMenu = AddPulldown(management, "AP_STR_Model", "Model", "Công cụ model kết cấu.", "Structure");
        AddMenuItem<AllowBeamJoinsCommand>(modelMenu, "Cho phép nối dầm", "Allow joins tại đầu dầm.", "Beam");
        AddMenuItem<DisallowBeamJoinsCommand>(modelMenu, "Khóa nối dầm", "Disallow joins tại đầu dầm.", "Beam");
        AddMenuItem<ZeroBeamOffsetsCommand>(modelMenu, "Đưa offset dầm về 0", "Đặt end elevation offset của dầm về 0.", "Beam");
        AddMenuItem<JoinSelectedGeometryCommand>(modelMenu, "Join Geometry", "Join hai phần tử đầu tiên được chọn.", "Structure");

        var marksMenu = AddPulldown(management, "AP_STR_Marks", "Marks", "Đánh số cấu kiện kết cấu.", "Marks");
        AddMenuItem<RenumberColumnsCommand>(marksMenu, "Đánh số cột", "Đánh lại Mark cho cột.", "Column");
        AddMenuItem<RenumberBeamsCommand>(marksMenu, "Đánh số dầm", "Đánh lại Mark cho dầm.", "Beam");
        AddMenuItem<RenumberFoundationsCommand>(marksMenu, "Đánh số móng", "Đánh lại Mark cho móng.", "Foundation");

        var qaMenu = AddPulldown(management, "AP_STR_QA", "QA/QC", "Kiểm tra và chọn nhanh cấu kiện kết cấu.", "QA");
        AddMenuItem<StructuralAuditCommand>(qaMenu, "Structure Audit", "Kiểm tra nội dung model kết cấu.", "QA");
        AddMenuItem<SelectStructuralColumnsCommand>(qaMenu, "Chọn cột", "Chọn structural columns.", "Column");
        AddMenuItem<SelectFramingCommand>(qaMenu, "Chọn dầm", "Chọn structural framing.", "Beam");
        AddMenuItem<SelectFoundationsCommand>(qaMenu, "Chọn móng", "Chọn structural foundations.", "Foundation");
        AddMenuItem<ExportStructureCommand>(qaMenu, "Xuất dữ liệu kết cấu", "Xuất dữ liệu cấu kiện kết cấu.", "Docs");
    }
'@

$pattern = '(?s)    private void CreateStructureRibbon\(\).*?(?=    private void CreateMepRibbon\(\))'
$updated = [regex]::Replace($txt, $pattern, $newMethod + [Environment]::NewLine + [Environment]::NewLine, 1)
if ($updated -eq $txt) { throw 'CreateStructureRibbon replacement failed.' }
Set-Content $app $updated -Encoding UTF8

$product = '.\\source\\AP.BimTools.Core\\ProductInfo.cs'
$p = Get-Content $product -Raw
$p = $p.Replace('2.1.0', '2.2.0').Replace('2.0.0', '2.2.0')
Set-Content $product $p -Encoding UTF8
