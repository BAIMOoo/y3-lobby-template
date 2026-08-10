param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\assets\ui\scheme_b')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null

function New-Color {
    param([string]$Hex, [int]$Alpha = 255)

    $value = $Hex.TrimStart('#')
    return [System.Drawing.Color]::FromArgb(
        $Alpha,
        [Convert]::ToInt32($value.Substring(0, 2), 16),
        [Convert]::ToInt32($value.Substring(2, 2), 16),
        [Convert]::ToInt32($value.Substring(4, 2), 16)
    )
}

function New-RoundedPath {
    param(
        [System.Drawing.RectangleF]$Bounds,
        [float]$Radius
    )

    $diameter = $Radius * 2
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($Bounds.Left, $Bounds.Top, $diameter, $diameter, 180, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Top, $diameter, $diameter, 270, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Bounds.Left, $Bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Write-SurfaceTexture {
    param(
        [string]$FileName,
        [string]$Fill,
        [string]$Border,
        [int]$FillAlpha = 245
    )

    $bitmap = [System.Drawing.Bitmap]::new(32, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $path = New-RoundedPath ([System.Drawing.RectangleF]::new(0.5, 0.5, 31, 31)) 4
    $brush = [System.Drawing.SolidBrush]::new((New-Color $Fill $FillAlpha))
    $pen = [System.Drawing.Pen]::new((New-Color $Border 255), 1)
    $graphics.FillPath($brush, $path)
    $graphics.DrawPath($pen, $path)
    $bitmap.Save((Join-Path $resolvedOutput $FileName), [System.Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose()
    $brush.Dispose()
    $path.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

function Write-ButtonTexture {
    param(
        [string]$FileName,
        [string]$Top,
        [string]$Bottom,
        [string]$Border,
        [int]$Alpha = 255
    )

    $bitmap = [System.Drawing.Bitmap]::new(128, 48, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $bounds = [System.Drawing.RectangleF]::new(0.5, 0.5, 127, 47)
    $path = New-RoundedPath $bounds 3
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $bounds,
        (New-Color $Top $Alpha),
        (New-Color $Bottom $Alpha),
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $pen = [System.Drawing.Pen]::new((New-Color $Border $Alpha), 1)
    $graphics.FillPath($brush, $path)
    $graphics.DrawPath($pen, $path)
    $highlight = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb([Math]::Min($Alpha, 28), 255, 255, 255), 1)
    $graphics.DrawLine($highlight, 4, 2, 124, 2)
    $bitmap.Save((Join-Path $resolvedOutput $FileName), [System.Drawing.Imaging.ImageFormat]::Png)
    $highlight.Dispose()
    $pen.Dispose()
    $brush.Dispose()
    $path.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

Write-SurfaceTexture 'scheme_b_panel%ID134217729.png' '#1e1912' '#6d5c37' 236
Write-SurfaceTexture 'scheme_b_panel_soft%ID134217730.png' '#231d15' '#5d5135' 226
Write-SurfaceTexture 'scheme_b_panel_deep%ID134217731.png' '#15120e' '#4c432e' 244
Write-SurfaceTexture 'scheme_b_input%ID134217732.png' '#151c18' '#756542' 250

Write-ButtonTexture 'scheme_b_button_normal%ID134217733.png' '#30291d' '#211d17' '#6c6046'
Write-ButtonTexture 'scheme_b_button_hover%ID134217734.png' '#423823' '#2c261b' '#b29a60'
Write-ButtonTexture 'scheme_b_button_pressed%ID134217735.png' '#211c15' '#2c251a' '#9b8248'
Write-ButtonTexture 'scheme_b_button_disabled%ID134217736.png' '#29261f' '#211f1a' '#484334' 180

Write-ButtonTexture 'scheme_b_primary_normal%ID134217737.png' '#7a642d' '#5b471e' '#c6a85e'
Write-ButtonTexture 'scheme_b_primary_hover%ID134217738.png' '#91783a' '#6c5425' '#e0c374'
Write-ButtonTexture 'scheme_b_primary_pressed%ID134217739.png' '#5f4b22' '#4f3d1a' '#c0a257'
Write-ButtonTexture 'scheme_b_primary_disabled%ID134217740.png' '#50462f' '#3d3728' '#6a6048' 180

Write-ButtonTexture 'scheme_b_danger_normal%ID134217741.png' '#633e3d' '#4b3030' '#8a5552'
Write-ButtonTexture 'scheme_b_danger_hover%ID134217742.png' '#754744' '#593535' '#d1817c'
Write-ButtonTexture 'scheme_b_danger_pressed%ID134217743.png' '#4c2e2e' '#3c2525' '#aa625e'
Write-ButtonTexture 'scheme_b_danger_disabled%ID134217744.png' '#433334' '#35292a' '#5c4546' 180

$backdropPath = Join-Path $resolvedOutput 'scheme_b_backdrop%ID134217745.png'
if (-not (Test-Path -LiteralPath $backdropPath)) {
    throw "Missing GPT Image backdrop: $backdropPath"
}

Write-Host "Generated Scheme B UI assets in $resolvedOutput"
