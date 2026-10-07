# AP-BIM Tools v2.1.1 - ribbon icon startup fix
$ErrorActionPreference = 'Stop'

$proj = '.\source\AP.BimTools\AP.BimTools.csproj'
$txt = Get-Content $proj -Raw
if ($txt -notmatch '<Resource Include="Icon\*\.png"') {
  $txt = $txt.Replace(
    '<Resource Include="RibbonIcon32.png"/>',
    '<Resource Include="RibbonIcon32.png"/>' + [Environment]::NewLine + '    <Resource Include="Icon*.png"/>'
  )
}
Set-Content $proj $txt -Encoding UTF8

$app = '.\source\AP.BimTools\Application.cs'
$txt = Get-Content $app -Raw

$old = @'
    private static BitmapImage LoadIcon(string? iconName, int size)
    {
        var file = iconName is null ? $"RibbonIcon{size}.png" : $"Icon{iconName}{size}.png";
        var uri = new Uri($"pack://application:,,,/AP.BimTools;component/{file}", UriKind.Absolute);
        return new BitmapImage(uri);
    }
'@

$new = @'
    private static BitmapImage LoadIcon(string? iconName, int size)
    {
        var file = iconName is null ? $"RibbonIcon{size}.png" : $"Icon{iconName}{size}.png";

        try
        {
            return new BitmapImage(new Uri($"pack://application:,,,/AP.BimTools;component/{file}", UriKind.Absolute));
        }
        catch
        {
            try
            {
                return new BitmapImage(new Uri($"pack://application:,,,/AP.BimTools;component/RibbonIcon{size}.png", UriKind.Absolute));
            }
            catch
            {
                // Never block Revit startup because of a missing/corrupt ribbon image.
                return new BitmapImage();
            }
        }
    }
'@

if ($txt.Contains($old)) {
  $txt = $txt.Replace($old, $new)
} elseif ($txt -notmatch 'Never block Revit startup because of a missing/corrupt ribbon image') {
  throw 'LoadIcon method pattern not found; refusing to build without the startup safety fix.'
}
Set-Content $app $txt -Encoding UTF8
