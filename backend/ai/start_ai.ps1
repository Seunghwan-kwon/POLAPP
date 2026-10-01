$ErrorActionPreference = 'Stop'

$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    throw '가상환경이 없습니다. README의 설치 절차를 먼저 확인하세요.'
}

Set-Location -LiteralPath $PSScriptRoot
Write-Host 'POLAPP AI 서버: http://0.0.0.0:8765'
Write-Host '종료하려면 Ctrl+C를 누르세요.'
& $python ai_server.py
