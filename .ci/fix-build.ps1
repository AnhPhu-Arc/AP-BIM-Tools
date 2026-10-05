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
