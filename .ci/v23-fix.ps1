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

$window = '.\source\AP.BimTools.Structure\RebarStudio\RebarStudioWindow.cs'
$txt = Get-Content $window -Raw
$txt = $txt.Replace('Color.FromRgb(', 'System.Windows.Media.Color.FromRgb(')
$txt = $txt.Replace('Color.FromArgb(', 'System.Windows.Media.Color.FromArgb(')
$txt = $txt.Replace('new Rectangle{', 'new System.Windows.Shapes.Rectangle{')
$txt = $txt.Replace('new Rectangle {', 'new System.Windows.Shapes.Rectangle {')
$txt = $txt.Replace('new Ellipse{', 'new System.Windows.Shapes.Ellipse{')
$txt = $txt.Replace('new Ellipse {', 'new System.Windows.Shapes.Ellipse {')
Set-Content $window $txt -Encoding UTF8

$commands = '.\source\AP.BimTools.Structure\Commands\RebarStudioCommands.cs'
$txt = Get-Content $commands -Raw
$txt = $txt.Replace('private static IReadOnlyList<RebarHostInfo> BuildHostInfo(', 'internal static IReadOnlyList<RebarHostInfo> BuildHostInfo(')
$txt = $txt.Replace('new RebarStudioWindow(options, RebarStudioMode.Column, BuildHostInfo(columns.Cast<Element>().ToList()))', 'new RebarStudioWindow(options, RebarStudioMode.Column, RebarStudioCommandRunner.BuildHostInfo(columns.Cast<Element>().ToList()))')
Set-Content $commands $txt -Encoding UTF8
