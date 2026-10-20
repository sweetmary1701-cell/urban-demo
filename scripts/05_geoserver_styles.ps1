# ============================================================
#  GeoServer 样式配置：上传 SLD 并绑定到图层
#  用法:  pwsh -File "scripts\05_geoserver_styles.ps1"
#
#  说明：所有中文字面量都转成 XML 字符引用（&#x6B63;&#x5E38;），
#        因此生成的 SLD 文件是纯 ASCII —— 从根上避免编码问题。
#
#  执行顺序：必须先跑 04_geoserver_publish.ps1（图层不存在则绑定会失败）。
# ============================================================
$ErrorActionPreference = 'Stop'

$Base  = 'http://localhost:8086/geoserver'
$Auth  = 'admin:geoserver'
$Tmp   = $env:TEMP
$Utf8  = New-Object System.Text.UTF8Encoding($false)
$Ascii = New-Object System.Text.ASCIIEncoding

# ---------- 中文 -> XML 字符引用 ----------
function CRef([string]$s) {
    -join ($s.ToCharArray() | ForEach-Object { '&#x{0:X};' -f [int]$_ })
}

# ---------- SLD 骨架 ----------
$SldHead = @'
<?xml version="1.0" encoding="UTF-8"?>
<StyledLayerDescriptor version="1.0.0"
    xmlns="http://www.opengis.net/sld"
    xmlns:ogc="http://www.opengis.net/ogc"
    xmlns:xlink="http://www.w3.org/1999/xlink"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.opengis.net/sld http://schemas.opengis.net/sld/1.0.0/StyledLayerDescriptor.xsd">
  <NamedLayer>
    <Name>__NAME__</Name>
    <UserStyle>
      <Name>__NAME__</Name>
      <Title>__TITLE__</Title>
      <FeatureTypeStyle>
'@

$SldFoot = @'
      </FeatureTypeStyle>
    </UserStyle>
  </NamedLayer>
</StyledLayerDescriptor>
'@

# ---------- 规则生成器 ----------
function LineRule {
    param($Name, $Field, $Value, $Color, $Width)
    $f = if ($Field) {
@"
          <ogc:Filter>
            <ogc:PropertyIsEqualTo>
              <ogc:PropertyName>$Field</ogc:PropertyName>
              <ogc:Literal>$Value</ogc:Literal>
            </ogc:PropertyIsEqualTo>
          </ogc:Filter>
"@
    } else { '          <ElseFilter/>' }
@"
        <Rule>
          <Name>$Name</Name>
$f
          <LineSymbolizer>
            <Stroke>
              <CssParameter name="stroke">$Color</CssParameter>
              <CssParameter name="stroke-width">$Width</CssParameter>
              <CssParameter name="stroke-linecap">round</CssParameter>
              <CssParameter name="stroke-linejoin">round</CssParameter>
            </Stroke>
          </LineSymbolizer>
        </Rule>
"@
}

function FillRule {
    param($Name, $Field, $Value, $FillColor, $FillOpacity, $StrokeColor, $StrokeWidth)
    $f = if ($Field) {
@"
          <ogc:Filter>
            <ogc:PropertyIsEqualTo>
              <ogc:PropertyName>$Field</ogc:PropertyName>
              <ogc:Literal>$Value</ogc:Literal>
            </ogc:PropertyIsEqualTo>
          </ogc:Filter>
"@
    } else { '          <ElseFilter/>' }
$stroke = if ($StrokeWidth) {
@"
            <Stroke>
              <CssParameter name="stroke">$StrokeColor</CssParameter>
              <CssParameter name="stroke-width">$StrokeWidth</CssParameter>
            </Stroke>
"@
    } else { '' }
@"
        <Rule>
          <Name>$Name</Name>
$f
          <PolygonSymbolizer>
            <Fill>
              <CssParameter name="fill">$FillColor</CssParameter>
              <CssParameter name="fill-opacity">$FillOpacity</CssParameter>
            </Fill>
$stroke
          </PolygonSymbolizer>
        </Rule>
"@
}

function PointRule {
    param($Name, $Field, $Value, $Fill, $Size, $StrokeColor = '#03121f', $StrokeWidth = 1)
    $f = if ($Field) {
@"
          <ogc:Filter>
            <ogc:PropertyIsEqualTo>
              <ogc:PropertyName>$Field</ogc:PropertyName>
              <ogc:Literal>$Value</ogc:Literal>
            </ogc:PropertyIsEqualTo>
          </ogc:Filter>
"@
    } else { '          <ElseFilter/>' }
@"
        <Rule>
          <Name>$Name</Name>
$f
          <PointSymbolizer>
            <Graphic>
              <Mark>
                <WellKnownName>circle</WellKnownName>
                <Fill><CssParameter name="fill">$Fill</CssParameter></Fill>
                <Stroke>
                  <CssParameter name="stroke">$StrokeColor</CssParameter>
                  <CssParameter name="stroke-width">$StrokeWidth</CssParameter>
                </Stroke>
              </Mark>
              <Size>$Size</Size>
            </Graphic>
          </PointSymbolizer>
        </Rule>
"@
}

function PublishStyle {
    param([string]$Name, [string]$Title, [string]$Rules)
    $sld = $SldHead.Replace('__NAME__', $Name).Replace('__TITLE__', $Title) + $Rules + $SldFoot
    $f = Join-Path $Tmp "$Name.sld"
    [System.IO.File]::WriteAllText($f, $sld, $Ascii)

    # 先删旧的（幂等重跑）
    & curl.exe -s -o NUL -u $Auth -X DELETE --max-time 30 "$Base/rest/styles/$Name" 2>$null

    # 注意坑点：用 XML 方式 POST /rest/styles 时 GeoServer 要求 <filename> 字段，
    # 否则报 "Style fileName must not be null"。改用「?name= + SLD 内容」一步到位。
    $err = Join-Path $Tmp 'style_err.txt'
    $c = & curl.exe -s -o $err -w '%{http_code}' -u $Auth -X POST --max-time 60 `
        -H 'Content-Type: application/vnd.ogc.sld+xml' --data-binary "@$f" `
        "$Base/rest/styles?name=$Name"
    if ($c -in '200', '201') {
        "  {0,-18} OK (HTTP {1})" -f $Name, $c
    } else {
        "  {0,-18} 失败 HTTP {1}  {2}" -f $Name, $c,
            (((Get-Content $err -Raw -ErrorAction SilentlyContinue) -replace "`r?`n", ' ').Trim())
    }
}

function BindStyle {
    param([string]$Layer, [string]$Style)
    $body = '{"layer":{"defaultStyle":{"name":"' + $Style + '"}}}'
    $f = Join-Path $Tmp "bind.json"
    [System.IO.File]::WriteAllText($f, $body, $Ascii)
    $c = & curl.exe -s -o NUL -w '%{http_code}' -u $Auth -X PUT --max-time 30 `
        -H 'Content-Type: application/json' --data-binary "@$f" `
        "$Base/rest/layers/urban:$Layer"
    "  绑定 {0,-16} <- {1,-18} HTTP {2}" -f $Layer, $Style, $c
}

# ============================================================
#  1. 路网 —— 按等级着色
# ============================================================
Write-Host "`n===== 上传 SLD 样式 ====="
$rules = ''
$rules += LineRule 'hw'  'road_class_code' 'hw'  '#ff4d4f' 4.4
$rules += LineRule 'exp' 'road_class_code' 'exp' '#ff9c2b' 3.8
$rules += LineRule 'art' 'road_class_code' 'art' '#ffd666' 3.0
$rules += LineRule 'sec' 'road_class_code' 'sec' '#4facfe' 2.2
$rules += LineRule 'brn' 'road_class_code' 'brn' '#6c86a6' 1.3
PublishStyle 'road_class' 'Road classification' $rules

# ------------------------------------------------------------
#  2. 路网 —— 按拥堵着色
# ------------------------------------------------------------
$rules = ''
$rules += LineRule 'severe' 'congestion_code' 'severe' '#ff3b3b' 4.4
$rules += LineRule 'mod'    'congestion_code' 'mod'    '#ff8c42' 4.0
$rules += LineRule 'slight' 'congestion_code' 'slight' '#ffd166' 3.4
$rules += LineRule 'ok'     'congestion_code' 'ok'     '#8ddb3c' 2.6
$rules += LineRule 'smooth' 'congestion_code' 'smooth' '#12e6a0' 2.0
$rules += LineRule 'other'  $null $null '#4a6a8a' 1.2
PublishStyle 'road_congestion' 'Road congestion' $rules

# ------------------------------------------------------------
#  3. 行政区热力
# ------------------------------------------------------------
$rules = ''
# 注意：SLD 不支持 rgba()，透明度要靠单独的 fill-opacity 参数
$rules += FillRule 'lv4' 'heat_code' 'lv4' '#ff3c3c' 0.42 '#5abeff' 1.0
$rules += FillRule 'lv3' 'heat_code' 'lv3' '#ff673c' 0.32 '#5abeff' 1.0
$rules += FillRule 'lv2' 'heat_code' 'lv2' '#ffc13d' 0.22 '#5abeff' 1.0
$rules += FillRule 'lv1' 'heat_code' 'lv1' '#13508c' 0.10 '#5abeff' 1.0
$rules += FillRule 'other' $null $null '#13508c' 0.08 '#5abeff' 1.0
PublishStyle 'district_heat' 'District heat' $rules

# ------------------------------------------------------------
#  4. 信号灯（按状态）
# ------------------------------------------------------------
$rules = ''
$rules += PointRule 'ok'    'status' (CRef '正常') '#12e6a0' 7
$rules += PointRule 'warn'  'status' (CRef '警告') '#ffc53d' 8
$rules += PointRule 'fault' 'status' (CRef '故障') '#ff3b3b' 9 '#ffe0e0' 1.6
$rules += PointRule 'other' $null $null '#12e6a0' 6
PublishStyle 'pt_signal' 'Traffic signals' $rules

# ------------------------------------------------------------
#  5. 监控 / 抓拍
# ------------------------------------------------------------
$rules = ''
$rules += PointRule 'monitor'   'kind' (CRef '视频监控') '#35c8ff' 7
$rules += PointRule 'violation' 'kind' (CRef '违法抓拍') '#c17bff' 7
$rules += PointRule 'other'     $null $null '#35c8ff' 6
PublishStyle 'pt_camera' 'Cameras' $rules

# ------------------------------------------------------------
#  6. 警力
# ------------------------------------------------------------
$rules = ''
$rules += PointRule 'onduty'     'status' (CRef '在岗') '#2ee6c0' 9
$rules += PointRule 'dispatch'   'status' (CRef '出勤') '#3d8bff' 9
$rules += PointRule 'standby'    'status' (CRef '待命') '#8fa8c0' 8
$rules += PointRule 'other'      $null $null '#2ee6c0' 8
PublishStyle 'pt_police' 'Police units' $rules

# ------------------------------------------------------------
#  7. 交通事故
# ------------------------------------------------------------
$rules = ''
$rules += PointRule 'severe' 'level' (CRef '严重') '#ff3b3b' 13 '#ffd166' 2
$rules += PointRule 'heavy'  'level' (CRef '较重') '#ff8c42' 11 '#ffd166' 2
$rules += PointRule 'normal' 'level' (CRef '一般') '#ffd166' 9  '#ffd166' 1.5
$rules += PointRule 'other'  $null $null '#ffd166' 9
PublishStyle 'pt_incident' 'Traffic incidents' $rules

# ------------------------------------------------------------
#  8. 地铁线路（颜色取自 colour 属性）+ 车站
# ------------------------------------------------------------
$rules = @'
        <Rule>
          <Name>metro-line</Name>
          <LineSymbolizer>
            <Stroke>
              <CssParameter name="stroke"><ogc:PropertyName>colour</ogc:PropertyName></CssParameter>
              <CssParameter name="stroke-width">4</CssParameter>
              <CssParameter name="stroke-linecap">round</CssParameter>
            </Stroke>
          </LineSymbolizer>
        </Rule>
        <Rule>
          <Name>metro-fallback</Name>
          <ElseFilter/>
          <LineSymbolizer>
            <Stroke>
              <CssParameter name="stroke">#4fa8ff</CssParameter>
              <CssParameter name="stroke-width">4</CssParameter>
              <CssParameter name="stroke-linecap">round</CssParameter>
            </Stroke>
          </LineSymbolizer>
        </Rule>
'@
PublishStyle 'ln_metro' 'Metro lines' $rules

$rules = PointRule 'station' $null $null '#0a1e34' 9 '#ffffff' 2.5
PublishStyle 'pt_metro_station' 'Metro stations' $rules

# ------------------------------------------------------------
#  9. 公交线路 + 站点
# ------------------------------------------------------------
$rules = LineRule 'bus' $null $null '#ffb14d' 2.4
PublishStyle 'ln_bus' 'Bus routes' $rules

$rules = PointRule 'stop' $null $null '#ffb14d' 7
PublishStyle 'pt_bus_stop' 'Bus stops' $rules

# ============================================================
#  绑定样式到图层
# ============================================================
Write-Host "`n===== 绑定样式 ====="
BindStyle 'v_road'         'road_class'
BindStyle 'v_district'     'district_heat'
BindStyle 'signal'         'pt_signal'
BindStyle 'camera'         'pt_camera'
BindStyle 'police_unit'    'pt_police'
BindStyle 'incident'       'pt_incident'
BindStyle 'metro_line'     'ln_metro'
BindStyle 'metro_station'  'pt_metro_station'
BindStyle 'bus_route'      'ln_bus'
BindStyle 'bus_stop'       'pt_bus_stop'

Write-Host "`n完成。" -ForegroundColor Green
