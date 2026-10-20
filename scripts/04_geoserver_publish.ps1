# ============================================================
#  GeoServer 图层发布
#  用法:  pwsh -File "scripts\04_geoserver_publish.ps1"
#
#  做三件事（全部通过 REST API，不需要手点管理界面）：
#    1. 建工作区 urban
#    2. 建 PostGIS 数据源 urban_demo，指向本项目的数据库
#    3. 发布 10 个图层
#
#  执行顺序：
#    sql/ 全部脚本  ->  本脚本  ->  05_geoserver_styles.ps1
#    （样式必须绑在已存在的图层上，所以本脚本要跑在样式脚本之前）
#
#  幂等：会先递归删除 urban 工作区再重建。这会导致已绑定的样式一并丢失，
#        所以本脚本跑完必须接着跑 05_geoserver_styles.ps1。
# ============================================================
$ErrorActionPreference = 'Stop'

# ---------- 配置（按实际环境修改） ----------
$Base      = 'http://localhost:8086/geoserver'   # 注意：本项目 GeoServer 端口是 8086
$Auth      = 'admin:geoserver'                   # GeoServer 默认管理员账号
$Workspace = 'urban'
$Store     = 'urban_demo'

$DbHost = 'localhost'
$DbPort = '5432'
$DbName = 'urban_demo'
$DbUser = 'postgres'
$DbPass = 'postgres'

$Tmp   = $env:TEMP
$Ascii = New-Object System.Text.ASCIIEncoding

# 图层清单：n = 数据库里的表/视图名，t = GeoServer 中的标题（英文，避开编码问题）
$Layers = @(
    @{ n = 'v_road';        t = 'Road network (5 classes + congestion)' },
    @{ n = 'v_district';    t = 'Administrative district (with heat stats)' },
    @{ n = 'metro_line';    t = 'Metro lines' },
    @{ n = 'metro_station'; t = 'Metro stations' },
    @{ n = 'bus_route';     t = 'Bus routes' },
    @{ n = 'bus_stop';      t = 'Bus stops' },
    @{ n = 'signal';        t = 'Traffic signals' },
    @{ n = 'camera';        t = 'Cameras / violation capture' },
    @{ n = 'police_unit';   t = 'Police units' },
    @{ n = 'incident';      t = 'Traffic incidents' }
)

function Write-Text {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $Ascii)
}

function Post-Json {
    param([string]$Url, [string]$Json)
    $f = Join-Path $Tmp 'gs_post.json'
    Write-Text $f $Json
    return (& curl.exe -s -o "$Tmp\gs_resp.txt" -w '%{http_code}' -u $Auth -X POST `
        -H 'Content-Type: application/json' --data-binary "@$f" --max-time 120 $Url)
}

# ------------------------------------------------------------
Write-Host "===== 0. 检查 GeoServer 是否可用 ====="
$code = & curl.exe -s -o NUL -w '%{http_code}' -u $Auth --max-time 20 "$Base/rest/about/version"
if ($code -ne '200') {
    Write-Host "  GeoServer 未响应（HTTP $code）" -ForegroundColor Red
    Write-Host "  请先执行:  Start-Service GeoServer"
    Write-Host "  并等待 http://localhost:8086/geoserver/web/ 能打开（约 10~40 秒）"
    exit 1
}
Write-Host "  GeoServer 可用"

# ------------------------------------------------------------
Write-Host "`n===== 1. 重建工作区 $Workspace ====="
& curl.exe -s -o NUL -u $Auth -X DELETE --max-time 60 `
    "$Base/rest/workspaces/${Workspace}?recurse=true" 2>$null
$c = Post-Json "$Base/rest/workspaces" "{`"workspace`":{`"name`":`"$Workspace`"}}"
Write-Host "  创建工作区 HTTP $c"

# ------------------------------------------------------------
Write-Host "`n===== 2. 建 PostGIS 数据源 $Store ====="
# 用单引号模板 + Replace，避免 PowerShell 把 JSON 里的 $ 当成变量
$dsTpl = @'
{"dataStore":{"name":"__STORE__","enabled":true,"connectionParameters":{"entry":[{"@key":"dbtype","$":"postgis"},{"@key":"host","$":"__HOST__"},{"@key":"port","$":"__PORT__"},{"@key":"database","$":"__DB__"},{"@key":"schema","$":"public"},{"@key":"user","$":"__USER__"},{"@key":"passwd","$":"__PASS__"},{"@key":"Expose primary keys","$":"true"},{"@key":"validate connections","$":"true"}]}}}
'@
$dsJson = $dsTpl.Replace('__STORE__', $Store).Replace('__HOST__', $DbHost).
    Replace('__PORT__', $DbPort).Replace('__DB__', $DbName).
    Replace('__USER__', $DbUser).Replace('__PASS__', $DbPass).Trim()
$c = Post-Json "$Base/rest/workspaces/$Workspace/datastores" $dsJson
Write-Host "  建数据源 HTTP $c"
if ($c -notin '200', '201') {
    Write-Host "  返回: $((Get-Content "$Tmp\gs_resp.txt" -Raw -ErrorAction SilentlyContinue).Trim())"
    exit 1
}

# ------------------------------------------------------------
Write-Host "`n===== 3. 发布 $($Layers.Count) 个图层 ====="
$ftTpl = @'
{"featureType":{"name":"__NAME__","nativeName":"__NAME__","title":"__TITLE__","srs":"EPSG:4326","projectionPolicy":"FORCE_DECLARED","enabled":true}}
'@
foreach ($l in $Layers) {
    $json = $ftTpl.Replace('__NAME__', $l.n).Replace('__TITLE__', $l.t).Trim()
    $c = Post-Json "$Base/rest/workspaces/$Workspace/datastores/$Store/featuretypes" $json
    if ($c -in '200', '201') {
        Write-Host ("  {0,-16} OK" -f $l.n)
    } else {
        $msg = (Get-Content "$Tmp\gs_resp.txt" -Raw -ErrorAction SilentlyContinue) -replace "`r?`n", ' '
        Write-Host ("  {0,-16} 失败 HTTP {1}  {2}" -f $l.n, $c, $msg.Trim())
    }
}

# ------------------------------------------------------------
Write-Host "`n===== 4. 结果核对 ====="
$r = & curl.exe -s -u $Auth --max-time 30 `
    "$Base/rest/workspaces/$Workspace/datastores/$Store/featuretypes.json"
$names = ($r | ConvertFrom-Json).featureTypes.featureType | ForEach-Object { $_.name }
Write-Host "  已发布 $($names.Count) 个图层: $($names -join ', ')"

Write-Host "`n下一步：运行 scripts\05_geoserver_styles.ps1 上传并绑定 SLD 样式。" -ForegroundColor Green
