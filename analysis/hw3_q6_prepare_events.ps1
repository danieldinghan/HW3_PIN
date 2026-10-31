$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'HW3/TEJ20261031024209/20261031024214.txt'
$samplePath = Join-Path $root 'HW3/results/sample_600_final.csv'
$output = Join-Path $root 'HW3/results/q6_2019q2_disclosure_events.csv'

$raw = @(Import-Csv -LiteralPath $source -Delimiter "`t" -Encoding Unicode)
$sample = @(Import-Csv -LiteralPath $samplePath)
$codes = [Collections.Generic.HashSet[string]]::new()
foreach ($row in $sample) { [void] $codes.Add($row.code) }
if ($sample.Count -ne 600 -or $codes.Count -ne 600) { throw 'Unexpected HW3 sample size' }

$events = foreach ($row in $raw) {
    if ($row.'事件日' -notmatch '^2019\d{4}$') { continue }
    if ($row.'證券代碼' -notlike 'R1TSE2*' -or $row.'季別' -ne '2') { continue }
    if ($row.'公告日' -ne $row.'事件日') { throw 'Event and disclosure date differ' }
    $match = [regex]::Match($row.'公司及名稱', '^\s*(\d{4,6})\b')
    if (-not $match.Success) { throw 'Cannot parse stock code' }
    $code = $match.Groups[1].Value
    if (-not $codes.Contains($code)) { continue }
    [pscustomobject]@{
        code = $code
        disclosure_date = $row.'公告日'
        event_source = 'TEJ R1TSE2 listed consolidated 2Q disclosure date'
    }
}

$events = @($events | Sort-Object code, disclosure_date -Unique)
if (@($events | Group-Object code | Where-Object Count -gt 1).Count -gt 0) {
    throw 'Multiple distinct disclosure dates for a sample firm in 2019'
}
if ($events.Count -lt 500) { throw 'Unexpectedly low 2019 event coverage' }
$events | Export-Csv -LiteralPath $output -NoTypeInformation -Encoding utf8
Write-Output "Source rows: $($raw.Count); 2019 Q2 sample events: $($events.Count); output: $output"
