param(
  [Parameter(Mandatory = $true)]
  [string]$PromptB64
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

if ($PromptB64.StartsWith('@')) {
  $promptPath = $PromptB64.Substring(1)
  $promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
} else {
  $promptText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PromptB64))
}

$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$scriptPath = Join-Path $PSScriptRoot 'dashscope-vision.py'
$promptText | & $python $scriptPath
