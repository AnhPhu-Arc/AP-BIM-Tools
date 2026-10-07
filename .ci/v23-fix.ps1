$ErrorActionPreference = 'Stop'
$path = '.\source\AP.BimTools.Structure\RebarStudio\RebarStudioWindow.cs'
$txt = Get-Content $path -Raw
$txt = $txt.Replace('new Grid()', 'new System.Windows.Controls.Grid()')
$txt = $txt.Replace('new Grid {', 'new System.Windows.Controls.Grid {')
$txt = $txt.Replace('private static Grid Row(', 'private static System.Windows.Controls.Grid Row(')
$txt = $txt.Replace('Grid.SetColumn(', 'System.Windows.Controls.Grid.SetColumn(')
$txt = $txt.Replace('Grid.SetRow(', 'System.Windows.Controls.Grid.SetRow(')
$txt = $txt.Replace('new Line{', 'new System.Windows.Shapes.Line{')
$txt = $txt.Replace('new Line {', 'new System.Windows.Shapes.Line {')
Set-Content $path $txt -Encoding UTF8
