$ErrorActionPreference = 'Stop'
$report = '.\source\AP.BimTools.Core\Services\ReportService.cs'
$txt = Get-Content $report -Raw
if ($txt -notmatch 'using System.IO;') { $txt = "using System.IO;`r`n" + $txt }
Set-Content $report $txt -Encoding UTF8

$prompt = '.\source\AP.BimTools.Core\UI\PromptDialog.cs'
$txt = Get-Content $prompt -Raw
$txt = $txt.Replace('var grid = new Grid {', 'var grid = new System.Windows.Controls.Grid {')
$txt = $txt.Replace('var input = new TextBox {', 'var input = new System.Windows.Controls.TextBox {')
$txt = $txt.Replace('Grid.SetRow(text, 0); Grid.SetRow(input, 1); Grid.SetRow(buttons, 2);', 'System.Windows.Controls.Grid.SetRow(text, 0); System.Windows.Controls.Grid.SetRow(input, 1); System.Windows.Controls.Grid.SetRow(buttons, 2);')
Set-Content $prompt $txt -Encoding UTF8

$studio = '.\source\AP.BimTools.Structure\RebarStudio\RebarStudioWindow.cs'
$txt = Get-Content $studio -Raw
$txt = $txt.Replace('private void AddSection(Panel panel, string title)', 'private void AddSection(System.Windows.Controls.Panel panel, string title)')
$txt = $txt.Replace('private void AddText(Panel panel, string key, string label, string value)', 'private void AddText(System.Windows.Controls.Panel panel, string key, string label, string value)')
$txt = $txt.Replace('private void AddDouble(Panel panel, string key, string label, double value, string suffix)', 'private void AddDouble(System.Windows.Controls.Panel panel, string key, string label, double value, string suffix)')
$txt = $txt.Replace('private void AddInt(Panel panel, string key, string label, int value)', 'private void AddInt(System.Windows.Controls.Panel panel, string key, string label, int value)')
$txt = $txt.Replace('private void AddCheck(Panel panel, string key, string label, bool value)', 'private void AddCheck(System.Windows.Controls.Panel panel, string key, string label, bool value)')
$txt = $txt.Replace('private static Grid Row(string label, out StackPanel valuePanel)', 'private static System.Windows.Controls.Grid Row(string label, out StackPanel valuePanel)')
$txt = $txt.Replace('var grid = new Grid { Margin = new Thickness(0, 4, 0, 4) };', 'var grid = new System.Windows.Controls.Grid { Margin = new Thickness(0, 4, 0, 4) };')
$txt = $txt.Replace('Grid.SetColumn(valuePanel, 1);', 'System.Windows.Controls.Grid.SetColumn(valuePanel, 1);')
Set-Content $studio $txt -Encoding UTF8

# Fix System.IO references used by Nice3point projects targeting older Revit/.NET.
$settings = '.\source\AP.BimTools.Structure\RebarStudio\RebarStudioSettingsStore.cs'
$txt = Get-Content $settings -Raw
if ($txt -notmatch 'using System.IO;') { $txt = "using System.IO;`r`n" + $txt }
Set-Content $settings $txt -Encoding UTF8
$hostFile = '.\source\AP.BimTools\Host.cs'
$txt = Get-Content $hostFile -Raw
if ($txt -notmatch 'using System.IO;') { $txt = "using System.IO;`r`n" + $txt }
Set-Content $hostFile $txt -Encoding UTF8

# Revit 2023 exposes these as accessor methods rather than usable C# indexers.
$docs = '.\source\AP.BimTools.Structure\RebarStudio\RebarDocumentationService.cs'
$txt = Get-Content $docs -Raw
$txt = $txt.Replace('sectionBox.MinEnabled[dim] = true;', 'sectionBox.set_MinEnabled(dim, true);')
$txt = $txt.Replace('sectionBox.MaxEnabled[dim] = true;', 'sectionBox.set_MaxEnabled(dim, true);')
Set-Content $docs $txt -Encoding UTF8
