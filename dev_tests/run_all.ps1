# Runs every dev_tests/test_*.tscn headless and reports a pass/fail summary.
# Usage (from the project root or anywhere):
#   powershell -ExecutionPolicy Bypass -File dev_tests\run_all.ps1
# Optionally point at a different Godot build:
#   powershell -ExecutionPolicy Bypass -File dev_tests\run_all.ps1 -Godot "C:\path\to\godot_console.exe"
param(
    [string]$Godot = "d:\Godot\Godot_v4.7-stable_win64_console.exe"
)

$project = Split-Path -Parent $PSScriptRoot
$tests = Get-ChildItem $PSScriptRoot -Filter "test_*.tscn" | Sort-Object Name
$failed = @()

foreach ($t in $tests) {
    Write-Host ""
    Write-Host "=== $($t.Name) ===" -ForegroundColor Cyan
    & $Godot --headless --path $project ("res://dev_tests/" + $t.Name)
    if ($LASTEXITCODE -ne 0) { $failed += $t.Name }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host ("ALL {0} TEST SCENES PASSED" -f $tests.Count) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("FAILED: {0}" -f ($failed -join ", ")) -ForegroundColor Red
    exit 1
}
